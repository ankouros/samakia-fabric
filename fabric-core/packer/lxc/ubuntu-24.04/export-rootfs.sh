#!/usr/bin/env bash
set -euo pipefail

CID="$1"
OUT="$2"

echo "Exporting container ${CID} to ${OUT}"

docker export "${CID}" | gzip -9 > "${OUT}"

echo "Export completed: ${OUT}"
