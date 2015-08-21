#!/usr/bin/perl

use strict;
use Search::Elasticsearch;

my @servers = [ '127.0.0.1:9200' ];

my $e = Search::Elasticsearch->new( nodes => @servers );

eval { $e->indices->delete( index => $_ ) foreach (qw(transitauthority vehicle vehicleevents)); }; # try to delete.  ignore errors
my $routemappings = {
  boundingBox => { 'type' => 'geo_shape', 'tree' => 'quadtree', 'precision' => '1m' },
  tag         => { 'type' => 'string', 'index' => 'not_analyzed' },
  direction   => {
    type        => 'nested',
    properties  => {
      tag         => { 'type' => 'string', 'index' => 'not_analyzed' }
    }
  },
  path        => {
    type        => 'nested',
    properties  => {
      location    => { 'type' => 'geo_shape', 'tree' => 'quadtree', 'precision' => '1m' }
    }
  }
};

my $stopmappings = {
  location     => { 'type' => 'geo_point' },
  stopId       => { 'type' => 'long' },
  directionTag => { 'type' => 'string', 'index' => 'not_analyzed' },
  tag          => { 'type' => 'string', 'index' => 'not_analyzed' }
};

my $vehiclemappings = {
  id               => { 'type' => 'integer' },
  secsSinceReport  => { 'type' => 'short' },
  heading          => { 'type' => 'short' },
  speedKmHr        => { 'type' => 'short' },
  leadingVehicleId => { 'type' => 'integer' },
  predictable      => { 'type' => 'boolean' },
  location         => { 'type' => 'geo_point' },
  dirTag           => { 'type' => 'string', 'index' => 'not_analyzed' },
  routeTag         => { 'type' => 'string', 'index' => 'not_analyzed' }
};

my $vehicleeventmappings = $vehiclemappings;
$vehicleeventmappings->{'eventTime'} = { 'type' => 'date', 'format' => 'date_hour_minute_second', 'numeric_resolution' => 'seconds' };
$vehicleeventmappings->{'nearestStop'} = { properties => { distance => { 'type' => 'double'}, id => { 'type' => 'string', 'index' => 'not_analyzed' } } };
$vehicleeventmappings->{'eventType'} = { 'type' => 'string', 'index' => 'not_analyzed' };

$e->indices->create( index => 'transitauthority',
                     body => { settings => { number_of_replicas => 0 }, mappings =>
                               {
                                 "route" => { _all => { 'enabled' => 0 }, properties => $routemappings },
                                 "stop" => { _all => { 'enabled' => 0 }, properties => $stopmappings, _parent => { type => 'route' } },
                               }
                             }
                   );

$e->indices->create( index => 'vehicle',
                     body => { settings => { number_of_replicas => 0 }, _all => { 'enabled' => 0 }, mappings => { "vehicle" => { properties => $vehiclemappings } } }
                   );

$e->indices->create( index => 'vehicleevents',
                     body => { settings => { number_of_replicas => 0 }, _all => { 'enabled' => 0 }, mappings => { "event" => { properties => $vehicleeventmappings } } }
                   );
