<?php

$type = $_REQUEST['type'] ? $_REQUEST['type'] : 'speeding';
$route = $_REQUEST['route'];
$index = $_REQUEST['index'];

require '../vendor/autoload.php';

header('Content-type: application/json');

$client = new Elasticsearch\Client(array('hosts' => array('127.0.0.1:9200')));
$mainSearchParams['body']['size'] = 0;
$filters = array();
$locationField = 'location';

if ($index == 'complaints')
{
  $mainSearchParams['index'] = 'complaints';
  $mainSearchParams['type'] = 'complaints';
  $locationField = 'point';
  $mainSearchParams['body']['aggs']['events']['geohash_grid']['field'] = 'point';
}
else
{
  array_push($filters, array('term' => ['eventType' => $type]));
  $mainSearchParams['index'] = 'vehicleevents';
  $mainSearchParams['type'] = 'event';
  $mainSearchParams['body']['aggs']['events']['geohash_grid']['field'] = 'location';
}

$filters = array(['geo_bounding_box' => [$locationField => [
                    'top_left' => ['lat' => 37.850636, 'lon' => -122.551841],
                    'bottom_right' => ['lat' => 37.665367, 'lon' => -122.276801],
                   ]]]);

if ($route)
{
  array_push($filters, array('term' => ['routeTag' => $route]));
}
$mainSearchParams['body']['query']['bool']['must'] = $filters;
$mainSearchParams['body']['aggs']['events']['geohash_grid']['precision'] = 8;
$mainSearchParams['body']['aggs']['events']['geohash_grid']['size'] = 1000;

$mainHits = $client->search($mainSearchParams);
$maxCount = -1;
$mainResults = array();
$geotools = new \League\Geotools\Geotools();
foreach ($mainHits['aggregations']['events']['buckets'] as $mainHitId => $mainHitValue) {
  $geoKey = $mainHitValue['key'];
  $docs = $mainHitValue['doc_count'];
  if ($maxCount == -1)
    $maxCount = $docs;
  $decodedGeo = $geotools->geohash()->decode($geoKey);
  $lat = $decodedGeo->getCoordinate()->getLatitude();
  $lon = $decodedGeo->getCoordinate()->getLongitude();
  $mainResults[] = array('lat' => $lat, 'lon' => $lon, 'score' => 3 * sprintf("%.5f",$docs / $maxCount));
}
echo json_encode($mainResults);

?>
