#!/bin/sh
# Grab a screenshot of the running dev channel via the Roku dev installer.
# Usage: scripts/dev_screenshot.sh <out.jpg>   (reads ROKU_IP / ROKU_DEV_USER / ROKU_DEV_PASS from .env)
set -e
cd "$(dirname "$0")/.."
. ./.env
html=$(curl -s -m30 --digest -u "$ROKU_DEV_USER:$ROKU_DEV_PASS" -F mysubmit=Screenshot -F passwd= -F archive= "http://$ROKU_IP/plugin_inspect")
path=$(printf '%s' "$html" | grep -o 'pkgs/dev\.[a-z]*?time=[0-9]*' | head -1)
[ -n "$path" ] || { echo "no screenshot link in response"; exit 1; }
curl -s -m30 --digest -u "$ROKU_DEV_USER:$ROKU_DEV_PASS" -o "$1" "http://$ROKU_IP/$path"
echo "$1"
