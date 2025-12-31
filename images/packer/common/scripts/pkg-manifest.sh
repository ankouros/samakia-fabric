#!/usr/bin/env bash
set -euo pipefail

out_dir="/etc/samakia-image"
manifest="$out_dir/pkg-manifest.txt"

sudo mkdir -p "$out_dir"

if command -v dpkg-query >/dev/null 2>&1; then
  sudo dpkg-query -W -f='${Package} ${Version}\n' | sort | sudo tee "$manifest" >/dev/null
else
  echo "ERROR: dpkg-query not found; cannot generate package manifest" >&2
  exit 1
fi
