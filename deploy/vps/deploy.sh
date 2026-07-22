#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$0")"

docker compose build --pull bot
docker compose up -d --wait bot

curl --fail --silent --show-error \
  --retry 10 --retry-delay 3 --retry-connrefused \
  http://127.0.0.1:10001/health >/dev/null

echo "0xda-market bot is healthy on 127.0.0.1:10001"
