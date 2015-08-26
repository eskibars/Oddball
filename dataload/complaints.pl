#!/usr/bin/perl

use strict;
use Data::Dumper;
use LWP::Simple;
use XML::XML2JSON;
use Search::Elasticsearch;

my @servers = [ '127.0.0.1:9200' ];
my $e = Search::Elasticsearch->new( nodes => @servers );
my $b = $e->bulk_helper();

# find the last complaint time
my $results = $e->search( index => 'complaints', type => 'complaints', body => {
  sort => { updated => { order => 'desc' } },
  size => 1
});

my @resulthits = @{ $results->{'hits'}->{'hits'} };
my $querystring = "\$where=updated>'";
$querystring .= ($#resulthits >= 0) ? $resulthits[0]->{'_source'}{'updated'} : '2015-08-21T00:00:00';
$querystring .= "'";

my $url = 'https://data.sfgov.org/resource/nmwp-sgbh.json?' . $querystring;
my $jsoncontent = get($url);
my $XML2JSON = XML::XML2JSON->new( attribute_prefix => '');
my @complaints = @{ $XML2JSON->json2obj($jsoncontent) };
foreach (@complaints)
{
  delete $_->{'point'}->{'human_address'};
  delete $_->{'point'}->{'needs_recoding'};
  $_->{'point'}->{'lat'} = delete $_->{'point'}->{'latitude'};
  $_->{'point'}->{'lon'} = delete $_->{'point'}->{'longitude'};
  $b->add_action( index => { index => 'complaints', type => 'complaints', id => 'muni-' . $_->{'case_id'}, _source => $_ } );
}
$b->flush();
