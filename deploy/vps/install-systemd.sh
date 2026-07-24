#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script as root" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
unit_dir=/etc/systemd/system

install -m 0755 \
  "$script_dir/run-price-digest.sh" \
  /usr/local/sbin/0xda-market-price-digest
install -m 0644 \
  "$script_dir/systemd/0xda-market-price-digest.service" \
  "$unit_dir/0xda-market-price-digest.service"
install -m 0644 \
  "$script_dir/systemd/0xda-market-price-digest.timer" \
  "$unit_dir/0xda-market-price-digest.timer"

systemctl daemon-reload
systemctl enable --now 0xda-market-price-digest.timer
systemctl status --no-pager 0xda-market-price-digest.timer
