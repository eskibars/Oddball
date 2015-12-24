<?php
  $type = $_REQUEST['type'];
  $offset = intval($_REQUEST['start']);
  $route = $_REQUEST['route'];
  $lat = $_REQUEST['lat'];
  $lon = $_REQUEST['lon'];
  $eventTime = $_REQUEST['eventtime'];

  require '../vendor/autoload.php';

  header('Content-type: application/json');

  $client = new Elasticsearch\Client(array('hosts' => array('127.0.0.1:9200')));

  $mainSearchParams['index'] = 'vehicleevents';
  $mainSearchParams['type'] = 'event';
  $mainSearchParams['body']['size'] = 30;
  $mainSearchParams['body']['from'] = ($offset > 1000) ? 1000 : $offset;
  $mainSearchParams['body']['sort']['eventTime'] = 'desc';

  if ($route)
  {
    $mainSearchParams['body']['query']['bool']['must']['term']['routeTag'] = $route;
  }

  $includeRoute = $includeNearestStop = FALSE;

  switch ($type) {
    case 'stops':
      $mainSearchParams['body']['query']['bool']['must']['term']['eventType'] = 'nearstop';
      $includeRoute = TRUE;
      $includeNearestStop = TRUE;
      break;
    case 'offvehicles':
      $mainSearchParams['body']['query']['bool']['must']['term']['eventType'] = 'rogue';
      $includeRoute = TRUE;
      break;
    case 'phantom':
      $mainSearchParams['body']['query']['bool']['must']['term']['eventType'] = 'phantomroute';
      $includeRoute = TRUE;
      break;
    case 'speedy':
      $mainSearchParams['body']['query']['bool']['must']['term']['eventType'] = 'speeding';
      if ($_REQUEST['veryspeedy'] === 'true')
      {
        $mainSearchParams['body']['filter']['script']['script'] = "doc['vehicleSpeedMPH'].value - doc['speedLimit'].value > mindelta";
        $mainSearchParams['body']['filter']['script']['params']['mindelta'] = 10;
      }
      break;
    default:
      $mainSearchParams['body']['query']['bool']['must_not']['term']['eventType'] = 'nearstop';
      $includeRoute = TRUE;
      break;
  }

  if (is_numeric($lat) && is_numeric($lon))
  {
    $mainSearchParams['body']['query']['geo_shape']['point']['shape']['type'] = 'circle';
    $mainSearchParams['body']['query']['geo_shape']['point']['shape']['coordinates'] = array($lon, $lat);
    $mainSearchParams['body']['query']['geo_shape']['point']['shape']['radius'] = '400m';
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
      try
      {
        $routeResults = $client->get(array('index' => 'transitauthority', 'type' => 'route',
                                            'id' => 'route-' . $route));
        $fullResult['route'] = $routeResults['_source']['path'];
      } catch (Exception $e){}
    }
    if ($includeNearestStop)
    {
      try
      {
        $nearestStopResults = $client->get(array('index' => 'transitauthority', 'type' => 'stop',
                                                  'routing' => 'route-' . $mainHitValue['_source']['routeTag'],
                                                  'id' => $mainHitValue['_source']['nearestStop']['id']));
        $fullResult['stop'] = $nearestStopResults;
      } catch (Exception $e){}
    }
    $resultList[] = $fullResult;
  }
  echo json_encode($resultList);
?>
