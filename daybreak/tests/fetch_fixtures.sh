#!/bin/sh
# Saves current public feeds into tests/fixtures/live/ (gitignored) for run_data.sh.
set -e
DIR=$(cd "$(dirname "$0")" && pwd)/fixtures
mkdir -p "$DIR/live"
cp "$DIR/../../../config/family.example.json" "$DIR/family.example.json"
cd "$DIR/live"
curl -s -m20 "https://api.open-meteo.com/v1/forecast?latitude=33.0393&longitude=-85.0313&timezone=America%2FNew_York&forecast_days=8&temperature_unit=fahrenheit&wind_speed_unit=mph&current=temperature_2m,weather_code,wind_speed_10m&hourly=temperature_2m,weather_code,precipitation_probability,cloud_cover&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,wind_speed_10m_max" -o weather.json
curl -s -m20 -A "Daybreak tests" "https://api.weather.gov/alerts/active?point=33.0393,-85.0313" -o alerts.json
curl -s -m20 "https://waterservices.usgs.gov/nwis/iv/?format=json&sites=02339400&parameterCd=00062" -o lake.json
curl -s -m20 -A "Mozilla/5.0" "https://lagrangepanthers.com/calendar.ashx/calendar.ics" -o lc.ics
for t in georgia:football/college-football/teams/61 auburn:football/college-football/teams/2 falcons:football/nfl/teams/1 hawks:basketball/nba/teams/1 braves:baseball/mlb/teams/15; do
  curl -s -m20 "https://site.api.espn.com/apis/site/v2/sports/${t#*:}/schedule" -o "espn_${t%%:*}.json"
done
echo "fixtures saved to $DIR/live"
