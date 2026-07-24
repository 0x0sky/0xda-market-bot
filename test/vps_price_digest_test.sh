#!/usr/bin/env bash
set -Eeuo pipefail

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

bot_root="$root/bot"
runtime_root="$root/runtime"
commands="$root/bin"
release="$bot_root/environments/production/releases/release-1"
mkdir -p "$commands" "$runtime_root" "$release/deploy/vps" "$bot_root/environments/production/shared"
printf 'production\n' >"$runtime_root/active-environment"
printf 'DEPLOY_ENV=production\n' >"$bot_root/environments/production/shared/.env"
: >"$release/deploy/vps/compose.yaml"
ln -s "$release" "$bot_root/environments/production/current"

cat >"$commands/docker" <<'DOCKER'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%q ' "$@" >>"${DOCKER_CALLS}"
printf '\n' >>"${DOCKER_CALLS}"

if [[ "$1" == "compose" ]]; then
  case "${2:-}" in
    config) exit 0 ;;
    ps) printf 'bot-container\n'; exit 0 ;;
    exec) exit 0 ;;
  esac
fi

if [[ "$1" == "inspect" ]]; then
  case "$3" in
    *State.Running*) printf 'true\n' ;;
    *State.Health*) printf 'healthy\n' ;;
    *) exit 1 ;;
  esac
  exit 0
fi

exit 1
DOCKER
chmod +x "$commands/docker"

calls="$root/docker.calls"
PATH="$commands:$PATH" \
DOCKER_CALLS="$calls" \
BOT_DEPLOY_PATH="$bot_root" \
VPS_RUNTIME_PATH="$runtime_root" \
bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/deploy/vps/run-price-digest.sh"

grep -Fq 'compose exec -T bot bundle exec ruby bin/send_price_digest' "$calls"

printf 'development\n' >"$runtime_root/active-environment"
output="$({
  PATH="$commands:$PATH" \
  DOCKER_CALLS="$calls" \
  BOT_DEPLOY_PATH="$bot_root" \
  VPS_RUNTIME_PATH="$runtime_root" \
  bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/deploy/vps/run-price-digest.sh"
} 2>&1)"
grep -Fq 'price digest skipped: development is active' <<<"$output"

echo 'VPS price digest test passed'
