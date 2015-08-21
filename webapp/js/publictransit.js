/* Map functions */

var map;
var geoData = [];
var shownFeatures = [];
var shownPins = [];

/**
 * Update a map's viewport to fit each geometry in a dataset
 * @param {google.maps.Map} map The map to adjust
 */
function zoom(map) {
  var bounds = new google.maps.LatLngBounds();
  if (shownFeatures.length > 0)
  {
    map.data.forEach(function(feature) {
      processPoints(feature.getGeometry(), bounds.extend, bounds);
    });
  }
  else {
    for (var i = 0; i < shownPins.length; i++)
    {
      bounds.extend(shownPins[i]);
    }
  }
  map.fitBounds(bounds);
}

/**
 * Process each point in a Geometry, regardless of how deep the points may lie.
 * @param {google.maps.Data.Geometry} geometry The structure to process
 * @param {function(google.maps.LatLng)} callback A function to call on each
 *     LatLng point encountered (e.g. Array.push)
 * @param {Object} thisArg The value of 'this' as provided to 'callback' (e.g.
 *     myArray)
 */
function processPoints(geometry, callback, thisArg) {
  if (geometry instanceof google.maps.LatLng) {
    callback.call(thisArg, geometry);
  } else if (geometry instanceof google.maps.Data.Point) {
    callback.call(thisArg, geometry.get());
  } else {
    geometry.getArray().forEach(function(g) {
      processPoints(g, callback, thisArg);
    });
  }
}

function clearMap()
{
  for (var i = 0; i < shownFeatures.length; i++)
  {
    map.data.remove(shownFeatures[i]);
  }
  shownFeatures = [];
  for (var i = 0; i < shownPins.length; i++)
  {
    shownPins[i].setMap(null);
  }
}

function initMap() {
  // set up the map
  map = new google.maps.Map(document.getElementById('map'), {
    center: new google.maps.LatLng(37.7833, -122.4167),
    zoom: 12
  });
  loadData('stops');
}

function loadData(dataType, params)
{
  var extraParams = (params) ? params : "";
  $.ajax( "events.php?type=" + dataType + extraParams )
        .done(function(data) {
            clearMap();

            geoData = data;

            switch (dataType) {
              case 'stops':
                $('#eventpane').html("<div class=\"eventheader\">Recent Stops</div>");
                $('#eventdescription').html("Recent Stops: Show vehicles recently near a stop location. Stop, vehicle, and route all outlined on map.");
                break;
              case 'offvehicles':
                $('#eventpane').html("<div class=\"eventheader\">Off-Route Vehicles</div>");
                $('#eventdescription').html("Off-Route Vehicles: Vehicles that have GPS readings >100m away from their planned route.  Vehicle and route outlined on map.");
                break;
              case 'phantom':
                $('#eventpane').html("<div class=\"eventheader\">Phantom Routes</div>");
                $('#eventdescription').html("Phantom Route Vehicles: Vehicles that have a route/direction which conflict with Muni's pre-defined route. Vehicle and pre-defined route outlined on map.");
                break;
              case 'speedy':
                $('#eventpane').html("<div class=\"eventheader\">Speedy Vehicles</div>");
                $('#eventdescription').html("Speedy Vehicles: Vehicles that are over the speed limit. " +
                      "For <b>very</b> speedy vehicles, <a href=\"javascript:loadData('speedy','&veryspeedy=true')\">click here</a>"
                );
                break;
              case 'overtime':
                $('#eventpane').html("<div class=\"eventheader\">Overtime Vehicles</div>");
                $('#eventdescription').html("Overtime Vehicles: Vehicles that are running beyond their schedule.");
                break;
              default:

            }
            // $('#eventpane').append('<div class="pagingheader"><div class="backbutton">&lt;--[back]</div><div class="forwardbutton">[next]--&gt;</div>');


            for(var i = 0; i < data.length; i++)
            {
              var v = data[i].vehicle;
              var eventText = v._source.routeTag + " #" + v._source.id;
              if (v._source.eventTime)
              {
                var d = new Date(0);
                d.setUTCSeconds(v._source.eventTime);
                eventText += "<div class=\"eventtime\" data-event-id=\"" + i + "\">(" + d.toLocaleString() + ")</div>"
              }
              $('#eventpane').append('<div class="event" data-event-id="' + i + '">' + eventText + '</div>');
            }

            $('.event').on('click', function(event) {
                var dataId = parseInt($(event.target).attr('data-event-id'));
                clearMap();
                var data = geoData[dataId];
                map.data.setStyle({
                  strokeColor: 'blue',
                  strokeWeight: 3
                });

                if (data.route)
                {
                  var f = {
                    type: 'Feature',
                    properties: {
                      color: 'blue'
                    },
                    id: dataId,
                    geometry: data.route.location
                  };
                  shownFeatures = map.data.addGeoJson(f);
                }
                if (data.vehicle && data.vehicle._source)
                {
                  var v = data.vehicle._source;
                  var vloc = new google.maps.LatLng(parseFloat(v.location[1]),parseFloat(v.location[0]));
                  map.setCenter(vloc);
                  var marker = new google.maps.Marker({
                    position: vloc,
                    map: map,
                    animation: google.maps.Animation.DROP,
                    label: v.routeTag
                  });

                  var infoContent = "<i>Speed: " + v.speedKmHr + "km/h</i><br>";
                  if (v.eventType === 'phantomroute')
                  {
                    var directionInfo = data.vehicle.direction;
                    infoContent += "Vehicle tagged as running route <b>" + directionInfo.route + "</b>. ";
                    infoContent += "Actually running route <b>" + v.routeTag + "</b>";
                    infoContent += " (" + directionInfo.route + ": " + directionInfo.code + ")";
                  }
                  else if (v.eventType === 'rogue') {
                    infoContent += v.nearestStop.distance + "m away from nearest " + v.routeTag + " stop<br>";
                  }
                  else if (v.eventType === 'nearstop') {
                     infoContent += v.nearestStop.distance + "m away from stop<br>";
                  }
                  else if (v.eventType === 'speeding') {
                    infoContent += "Speed limit: <b>" + v.speedLimit + "mi/h</b><br>";
                    infoContent += "Vehicle speed: <b>" + v.vehicleSpeedMPH + "mi/h</b><br>";
                  }
                  var vehicleInfowindow = new google.maps.InfoWindow({
                    content: infoContent
                  });
                  marker.addListener('click', function() {
                    vehicleInfowindow.open(map, marker);
                  });
                  shownPins.push(marker);
                }
                if (data.stop)
                {
                  var s = data.stop._source;
                  var sloc = new google.maps.LatLng(parseFloat(s.location[1]),parseFloat(s.location[0]));
                  map.setCenter(sloc);
                  var marker = new google.maps.Marker({
                    position: sloc,
                    map: map,
                    title: "Stop #"  + s.stopId
                  });
                  var stopInfowindow = new google.maps.InfoWindow({
                    content: "<a href=\"http://transit.511.org/schedules/realtimedepartures.aspx#onlystopid=" +
                              s.stopId + " target=_new\">511.org for stop ID" + s.stopId + "</a>"
                  });
                  marker.addListener('click', function() {
                    stopInfowindow.open(map, marker);
                  });
                  shownPins.push(marker);
                }

                zoom(map);
            });
        });
}

$(function() {
  $('a[data-toggle="tab"]').on('click', function(event) {
      var dataType = $(event.target).attr('data-event-type');
      if (dataType)
      {
        loadData(dataType);
      }
  });
});
