#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ ! -f .env ]]; then
  echo "deploy/vps/.env is missing" >&2
  exit 1
fi

deploy_mode="${DEPLOY_MODE:-activate}"
deploy_environment="$(sed -n 's/^DEPLOY_ENV=//p' .env | tail -n 1)"
edge_network="${MARKET_EDGE_NETWORK:-zero-x-da-market-edge}"

case "$deploy_mode" in
  stage|activate) ;;
  *)
    echo "Unsupported DEPLOY_MODE: $deploy_mode" >&2
    exit 1
    ;;
esac

case "$deploy_environment" in
  development|production) ;;
  *)
    echo "DEPLOY_ENV must be development or production" >&2
    exit 1
    ;;
esac

if ! docker network inspect "$edge_network" >/dev/null 2>&1; then
  docker network create "$edge_network" >/dev/null
fi

docker compose config --quiet
docker compose build --pull bot

if [[ "$deploy_mode" == "stage" ]]; then
  echo "0xda-market bot $deploy_environment release staged"
  exit 0
fi

docker compose up -d --wait bot

curl --fail --silent --show-error \
  --retry 10 --retry-delay 3 --retry-connrefused \
  http://127.0.0.1:10001/health >/dev/null

echo "0xda-market bot $deploy_environment is healthy on 127.0.0.1:10001"
