<?php
  require '../vendor/autoload.php';

  header('Content-type: application/json');

  $client = new Elasticsearch\Client(array('hosts' => array('127.0.0.1:9200')));
  $mainSearchParams['index'] = 'vehicleevents';
  $mainSearchParams['type'] = 'event';
  $mainSearchParams['body']['aggs']['vehicleevents']['filter']['not']['filter']['term']['eventType'] = 'nearstop';
  $mainSearchParams['body']['aggs']['vehicleevents']['aggs']['routeevents']['terms']['field'] = 'routeTag';
  $mainSearchParams['body']['aggs']['vehicleevents']['aggs']['routeevents']['terms']['size'] = 0;
  $mainSearchParams['body']['size'] = 0;
  $mainResults = $client->search($mainSearchParams);

  echo json_encode($mainResults['aggregations']['vehicleevents']['routeevents']);
?>
