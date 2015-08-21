<?php
  $type = $_REQUEST['type'];
  $offset = intval($_REQUEST['offset']);

  require '../vendor/autoload.php';

  header('Content-type: application/json');

  $client = new Elasticsearch\Client(array('hosts' => array('127.0.0.1:9200')));

  $mainSearchParams['index'] = 'vehicleevents';
  $mainSearchParams['type'] = 'event';
  $mainSearchParams['body']['size'] = 30;
  $mainSearchParams['body']['from'] = ($offset > 1000) ? 1000 : $offset;
  $mainSearchParams['body']['sort']['eventTime'] = 'desc';

  $includeRoute = $includeNearestStop = FALSE;

  switch ($type) {
    case 'stops':
      $mainSearchParams['body']['query']['term']['eventType'] = 'nearstop';
      $includeRoute = TRUE;
      $includeNearestStop = TRUE;
      break;
    case 'offvehicles':
      $mainSearchParams['body']['query']['term']['eventType'] = 'rogue';
      $includeRoute = TRUE;
      break;
    case 'phantom':
      $mainSearchParams['body']['query']['term']['eventType'] = 'phantomroute';
      $includeRoute = TRUE;
      break;
    case 'speedy':
      $mainSearchParams['body']['query']['term']['eventType'] = 'speeding';
      break;
    default:
      # code...
      break;
  }

  $mainResults = $client->search($mainSearchParams);

  $mainHits = $mainResults['hits']['hits'];

  $resultList = array();
  foreach ($mainHits as $mainHitId => $mainHitValue) {
    $fullResult = array();
    $dirStructured = preg_split("/_+/", $mainHitValue['_source']['dirTag']);
    $mainHitValue['direction']['route'] = $dirStructured[0];
    $mainHitValue['direction']['code'] = $dirStructured[2];
    switch ($dirStructured[1]) {
      case 'I':
        $mainHitValue['direction']['direction'] = 'Inbound';
        break;
      case 'O':
        $mainHitValue['direction']['direction'] = 'Outbound';
        break;
      default:
        $mainHitValue['direction']['direction'] = "Direction \"" . $dirStructured[1] . "\"";
        break;
    }

    $fullResult['vehicle'] = $mainHitValue;
    if ($includeRoute)
    {
      $route = ($type == 'phantom') ? $mainHitValue['_source']['direction']['route'] : $mainHitValue['_source']['routeTag'];
      $routeResults = $client->get(array('index' => 'transitauthority', 'type' => 'route',
                                          'id' => 'route-' . $route));
      $fullResult['route'] = $routeResults['_source']['path'];
    }
    if ($includeNearestStop)
    {
      $nearestStopResults = $client->get(array('index' => 'transitauthority', 'type' => 'stop',
                                                'routing' => 'route-' . $mainHitValue['_source']['routeTag'],
                                                'id' => $mainHitValue['_source']['nearestStop']['id']));
      $fullResult['stop'] = $nearestStopResults;
    }
    $resultList[] = $fullResult;
  }
  echo json_encode($resultList);
?>
