#!/usr/bin/env bash
set -euo pipefail

if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y cloud-init
fi

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl enable cloud-init cloud-config cloud-final >/dev/null 2>&1 || true
fi
