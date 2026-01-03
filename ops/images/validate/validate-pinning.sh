#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

errors=0

mapfile -t dockerfiles < <(rg --files -g 'Dockerfile*' -g '*.Dockerfile' -g '*.dockerfile' "$FABRIC_REPO_ROOT" || true)

for file in "${dockerfiles[@]}"; do
  while IFS= read -r line; do
    if [[ "$line" != *"@sha256:"* ]]; then
      echo "FAIL: unpinned Docker base image in $file -> $line" >&2
      errors=$((errors + 1))
    fi
  done < <(rg -n "^FROM " "$file" || true)
done

if ! rg -n "default = \"ubuntu@sha256:" "$FABRIC_REPO_ROOT/fabric-core/packer/lxc/ubuntu-24.04/packer.pkr.hcl" >/dev/null; then
  echo "FAIL: ubuntu_image is not digest-pinned in fabric-core/packer/lxc/ubuntu-24.04/packer.pkr.hcl" >&2
  errors=$((errors + 1))
fi

if rg -n ":latest" \
  --glob 'Dockerfile*' \
  --glob '*.Dockerfile' \
  --glob '*.dockerfile' \
  --glob '*.pkr.hcl' \
  --glob '*.hcl' \
  "$FABRIC_REPO_ROOT" >/dev/null; then
  echo "FAIL: floating :latest tag detected" >&2
  errors=$((errors + 1))
fi

if [[ "$errors" -gt 0 ]]; then
  exit 1
fi

echo "PASS: base image pinning validated"
