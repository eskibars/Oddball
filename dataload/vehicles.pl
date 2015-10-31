#!/usr/bin/perl

use strict;
use XML::XML2JSON;
use LWP::Simple;
use Search::Elasticsearch;

my $maxprocesses = 2;

# todo: switch this over to a proper flock or the like
my $processid = 0;
while (-e ($processid . ".lock") && $processid < $maxprocesses)
{
  $processid++;
}
exit if ($processid == $maxprocesses);
open(FIL,">$processid" . ".lock");
close(FIL);

# can poll this once every 10 seconds
my $url = 'http://webservices.nextbus.com/service/publicXMLFeed?command=vehicleLocations&a=sf-muni&t=0';
my @servers = [ '127.0.0.1:9200' ];

my $e = Search::Elasticsearch->new( nodes => @servers, request_timeout => 9999999 );
my $xmlcontent = get($url);
my $XML2JSON = XML::XML2JSON->new( attribute_prefix => '');
my $obj = $XML2JSON->xml2obj($xmlcontent);

my $b = $e->bulk_helper();

foreach my $vehicle (@{ $obj->{'body'}->{'vehicle'} })
{
  $vehicle->{$_} = ($vehicle->{$_} + 0) foreach (qw ( lat lon id speedKmHr heading secsSinceReport leadingVehicleId ));
  $vehicle->{'location'} = [ $vehicle->{'lon'}, $vehicle->{'lat'} ];

  # for some reason, the directionTag doesn't always exact match
  # the prefix always seems to (e.g. the route may say 5____I_F00 while the vehicle may say 5____I_S00)
  my $results = $e->search( index => 'transitauthority', type => 'stop', body => {
    filter => { bool => { must => [
                                    { has_parent => { parent_type => 'route', filter => { term => { 'tag' => $vehicle->{'routeTag'} } } } },
                                    { prefix => { directionTag => substr($vehicle->{'dirTag'},0,6) } } #for some reason, these occasionally don't exact match
                                  ]
              } },
    sort => { _geo_distance => { 'location' => { lat => $vehicle->{'lat'}, lon => $vehicle->{'lon'} },
                                  order => 'asc', unit => 'm' }
            },
    size => 1,
  } );

  my @resulthits = @{ $results->{'hits'}->{'hits'} };

  my $vehicleid = $vehicle->{'id'} . '-' . (10 * sprintf("%.0f",(time() - $vehicle->{'secsSinceReport'}) / 10.0));
  delete $vehicle->{'lon'};
  delete $vehicle->{'lat'};

  $vehicle->{'eventTime'} = time() - $vehicle->{'secsSinceReport'};

  if ($#resulthits < 0)
  {
    $vehicle->{'eventType'} = 'phantomroute';
    $b->add_action( index => { index => 'vehicleevents', type => 'event', _source => $vehicle } );
  }
  else
  {
    $vehicle->{'nearestStop'} = {};
    $vehicle->{'nearestStop'}->{'id'} = $resulthits[0]->{'_id'};
    $vehicle->{'nearestStop'}->{'distance'} = (@{ $resulthits[0]->{'sort'} })[0];
    $vehicle->{'eventType'} = 'nearstop';

    #add the location to the vehiclestops index if it's distance is less than the last distance
    my $vehiclestopid = $vehicle->{'nearestStop'}->{'id'} . '-' . $vehicle->{'id'} . '-' . (600 * sprintf("%.0f",(time() - $vehicle->{'secsSinceReport'}) / 600.0));
    $b->add_action( update=> { index => 'vehicleevents', type => 'event', id => $vehiclestopid,
      upsert => $vehicle,
      params => { distance => $vehicle->{'nearestStop'}->{'distance'} },
      script => 'if(ctx._source.distance < distance) ctx.op = "none"'
    } );

    my $offpathresults = $e->search( index => 'transitauthority', type => 'route', body => {
      filter => { bool => { must => [
                     { term => { tag => $vehicle->{'routeTag'} } },
                     { nested => { path => 'path', filter => {
                        geo_shape => {
                          'path.location' => {
                             shape => { type => 'circle', coordinates => $vehicle->{'location'}, radius => '100m' },
                             relation => 'disjoint'
                     } } } } }
                   ]
                 } },
      size => 1,
    } );

    if ($offpathresults->{'hits'}->{'total'} > 0)
    {
      $vehicle->{'eventType'} = 'rogue';
      $b->add_action( index => { index => 'vehicleevents', type => 'event', _source => $vehicle } );
    }
  }

  my $vehicleSpeedMPH = $vehicle->{'speedKmHr'} * 0.621371;
  my $speedresults = $e->search( index => 'speedlimit', type => 'speedlimit', body => {
    filter => {
            geo_shape => {
                  geometry => {
                     shape => { type => 'circle', coordinates => $vehicle->{'location'}, radius => '10m' },
                     relation => 'intersects'
          } } },
    size => 1,
  } );

  my @speedresulthits = @{ $speedresults->{'hits'}->{'hits'} };
  if ($#speedresulthits >= 0)
  {
    my $maxspeedlimit = 0;
    foreach my $speedresulthit (@speedresulthits)
    {
      if ($speedresulthits[0]->{'_source'}{'properties'}->{'speedlimit'} > $maxspeedlimit)
      {
        $maxspeedlimit = $speedresulthits[0]->{'_source'}{'properties'}->{'speedlimit'};
      }
    }
    if ($maxspeedlimit < $vehicleSpeedMPH)
    {
      $vehicle->{'eventType'} = 'speeding';
      $vehicle->{'speedLimit'} = $maxspeedlimit;
      $vehicle->{'vehicleSpeedMPH'} = $vehicleSpeedMPH;
      $b->add_action( index => { index => 'vehicleevents', type => 'event', _source => $vehicle } );
    }
  }
}
$b->flush();

END {
    unlink $processid . ".lock";
}
