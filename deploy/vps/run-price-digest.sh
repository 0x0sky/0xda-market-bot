#!/usr/bin/env bash
set -Eeuo pipefail

bot_root="${BOT_DEPLOY_PATH:-/opt/0xda-market-bot}"
runtime_root="${VPS_RUNTIME_PATH:-/opt/0xda-market-runtime}"
state_file="$runtime_root/active-environment"

if [[ ! -f "$state_file" ]]; then
  echo "price digest skipped: active environment marker is missing"
  exit 0
fi

active_environment="$(<"$state_file")"
case "$active_environment" in
  production) ;;
  development)
    echo "price digest skipped: development is active"
    exit 0
    ;;
  *)
    echo "price digest failed: unsupported active environment: $active_environment" >&2
    exit 1
    ;;
esac

release="$(readlink -f "$bot_root/environments/$active_environment/current" 2>/dev/null || true)"
env_file="$bot_root/environments/$active_environment/shared/.env"

if [[ -z "$release" || ! -d "$release/deploy/vps" ]]; then
  echo "price digest failed: production bot release is not staged" >&2
  exit 1
fi

if [[ ! -f "$env_file" ]]; then
  echo "price digest failed: production bot runtime file is missing" >&2
  exit 1
fi

if ! grep -qx 'DEPLOY_ENV=production' "$env_file"; then
  echo "price digest failed: production bot DEPLOY_ENV mismatch" >&2
  exit 1
fi

cd "$release/deploy/vps"
docker compose config --quiet

container_id="$(docker compose ps --quiet bot)"
if [[ -z "$container_id" ]]; then
  echo "price digest failed: active bot container is missing" >&2
  exit 1
fi

running="$(docker inspect --format '{{.State.Running}}' "$container_id")"
health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container_id")"
if [[ "$running" != "true" || "$health" != "healthy" ]]; then
  echo "price digest failed: bot running=$running health=$health" >&2
  exit 1
fi

docker compose exec -T bot bundle exec ruby bin/send_price_digest
