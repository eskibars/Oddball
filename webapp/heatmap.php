<?php

$type = $_REQUEST['type'];
$route = $_REQUEST['route'];

require '../vendor/autoload.php';

header('Content-type: application/json');

$client = new Elasticsearch\Client(array('hosts' => array('127.0.0.1:9200')));
$mainSearchParams['index'] = 'vehicleevents';
$mainSearchParams['type'] = 'event';
$mainSearchParams['body']['size'] = 0;
$filters = array(['term'] => ['eventType' => 'speeding'],
                 ['geo_bounding_box' => ['location' => [
                    'top_left' => ['lat' => 37.850636, 'lon' => -122.551841],
                    'bottom_right' => ['lat' => 37.665367, 'lon' => -122.276801],
                   ]]]);
$mainSearchParams['body']['filter']['and']['filters'] = $filters;
$mainSearchParams['body']['aggs']['vehicleevents']['geohash_grid']['field'] = 'location';
$mainSearchParams['body']['aggs']['vehicleevents']['geohash_grid']['precision'] = 8;
$mainSearchParams['body']['aggs']['vehicleevents']['geohash_grid']['size'] = 1000;

$mainHits = $client->search($mainSearchParams);
$maxCount = -1;
$mainResults = array();
$geotools = new \League\Geotools\Geotools();
foreach ($mainHits['aggregations']['vehicleevents']['buckets'] as $mainHitId => $mainHitValue) {
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
