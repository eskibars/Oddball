#!/bin/bash

wget -O speedlimits.zip https://data.sfgov.org/download/xjmx-586c/ZIP
rm -fr sfmta_speedlimits
unzip -d sfmta_speedlimits speedlimits.zip
rm -f speedlimits.json
ogr2ogr -f GeoJSON -t_srs crs:84 speedlimits.json sfmta_speedlimits/MTA_DPT_SpeedLimits.shp
jq -c '.features[] | select(.properties.speedlimit > 0)' speedlimits.json | sed -e 's/^/{ "index" : { "_index" : "speedlimit", "_type" : "speedlimit" } }\
/' > speedlimits_filtered.json
curl -XPUT http://127.0.0.1:9200/speedlimit -d '{
  "settings": {
    "number_of_replicas":1
  },
  "mappings": {
    "speedlimit": {
      "_all": { "enabled": false },
      "properties": {
        "type": { "type": "string", "index": "not_analyzed" },
        "cnn": { "type": "integer" },
        "st_type": { "type": "string", "index": "not_analyzed" },
        "speedlimit": { "type": "integer" },
        "geometry": { "type" : "geo_shape", "tree" : "quadtree", "precision" : "1m" }
      }
    }
  }
}'
curl -s -XPOST http://127.0.0.1:9200/_bulk --data-binary  @speedlimits_filtered.json
