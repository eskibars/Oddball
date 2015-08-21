#!/usr/bin/perl

use strict;
use XML::XML2JSON;
use LWP::Simple;
use Search::Elasticsearch;
use Data::Dumper;

my $url = 'http://webservices.nextbus.com/service/publicXMLFeed?command=routeConfig&a=sf-muni';
my @servers = [ '127.0.0.1:9200' ];

my $e = Search::Elasticsearch->new( nodes => @servers );
my $b = $e->bulk_helper();
my $xmlcontent = get($url);
my $XML2JSON = XML::XML2JSON->new( attribute_prefix => '');
my $obj = $XML2JSON->xml2obj($xmlcontent);

foreach my $route (@{ $obj->{'body'}->{'route'} })
{
  # $route->{'_id'} = $route->{'tag'}; #explicitly set this
  # this is a bit of a pain.  would be nice if we could just specify the field names holding the points
  $route->{'boundingBox'} = { 'type' => 'envelope', 'coordinates' => [
                                                                       [ $route->{'lonMin'} + 0, $route->{'latMin'} + 0 ],
                                                                       [ $route->{'lonMax'} + 0, $route->{'latMax'} + 0 ]
                                                                     ]
                            };
  delete $route->{$_} foreach (qw( latMin latMax lonMin lonMax color oppositeColor )); #get rid of these

  #format the stops into lat/lon coordinates... again, would be nice if we could just name the fields that hold the lat/lon
  #also, it's a bit weird here: needs to be lon-lat, not lat-lon, so a bit confusing
  my @stops = map { { 'title' => $_->{'title'}, 'tag' => $_->{'tag'}, 'stopId' => $_->{'stopId'} + 0,
                    'location' => [ $_->{'lon'} + 0, $_->{'lat'} + 0 ]
              } } @{ $route->{'stop'} };

  # get rid of useForUI tag under "direction", add directiontag to stops
  my @dirStops = ();
  if (ref($route->{'direction'}) eq 'HASH') {
    delete $route->{'direction'}->{'useForUI'};
    my $direction = $route->{'direction'};
    foreach my $stop ( @{ $direction->{'stop'} } )
    {
      push @dirStops, (grep { $_->{'tag'} eq $stop->{'tag'} } @stops)[0];
      $dirStops[$#dirStops]->{'directionTag'} = $direction->{'tag'};
    }
    delete $direction->{'stop'}; #these will be separate documents
  } elsif (ref($route->{'direction'}) eq 'ARRAY') {
    foreach my $direction (@{ $route->{'direction'} })
    {
      delete $direction->{'useForUI'};
      foreach my $stop ( @{ $direction->{'stop'} } )
      {
        push @dirStops, (grep { $_->{'tag'} eq $stop->{'tag'} } @stops)[0];
        $dirStops[$#dirStops]->{'directionTag'} = $direction->{'tag'};
      }

      delete $direction->{'stop'}; #these will be separate documents
    }
  }

  delete $route->{'stop'}; # we'll index these as child documents

  #format the path into a multiline geo string
  my @paths = ();
  foreach my $path (@{ $route->{'path'} })
  {
    my @points = map { [ $_->{'lon'} + 0, $_->{'lat'} + 0 ] } @{ $path->{'point'} };
    push @paths, \@points;
  }
  $route->{'path'} = { 'location' => { 'type' => 'multilinestring', 'coordinates' => \@paths } };

  $b->add_action( index => { index => 'transitauthority', type => 'route', id => 'route-' . $route->{'tag'}, _source => $route } );

  $b->add_action( index => { index => 'transitauthority', type => 'stop', id => 'stop-' . $route->{'tag'} . '-' . $_->{'tag'}, _source => $_, parent => 'route-' . $route->{'tag'} } ) foreach (@dirStops);
}

$b->flush();
