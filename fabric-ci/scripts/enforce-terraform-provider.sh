#!/usr/bin/env bash
set -euo pipefail

ROOT="fabric-core/terraform"

echo "Enforcing Terraform provider pinning (scope-aware)..."

GREP_COMMON_ARGS=(-R -I --exclude-dir=.terraform)

# -------------------------------------------------------------------
# Rule 1: Forbid hashicorp/proxmox everywhere
# -------------------------------------------------------------------
if grep "${GREP_COMMON_ARGS[@]}" "hashicorp/proxmox" "$ROOT"; then
  echo "ERROR: Forbidden provider detected: hashicorp/proxmox"
  exit 1
fi

# -------------------------------------------------------------------
# Rule 1b: Forbid insecure TLS flags (pm_tls_insecure) everywhere
# -------------------------------------------------------------------
if grep "${GREP_COMMON_ARGS[@]}" "pm_tls_insecure" "$ROOT"; then
  echo "ERROR: insecure TLS is forbidden: pm_tls_insecure"
  exit 1
fi

# -------------------------------------------------------------------
# Rule 2: For every module/env that declares provider "proxmox",
#         ensure required_providers exists in the same directory
# -------------------------------------------------------------------
FAILED=0

while IFS= read -r -d '' tf; do
  DIR="$(dirname "$tf")"

  if grep -q 'provider "proxmox"' "$tf"; then
    if ! grep -R -q 'required_providers' "$DIR"; then
      echo "ERROR: provider \"proxmox\" without required_providers in: $DIR"
      FAILED=1
    fi
  fi
done < <(find "$ROOT" -name "*.tf" -print0)

# -------------------------------------------------------------------
# Rule 3: No duplicate required_providers blocks per directory
# -------------------------------------------------------------------
find "$ROOT" -type f -name "*.tf" -print0 \
  | xargs -0 -n1 dirname \
  | sort -u \
  | while IFS= read -r dir; do
  count=$(grep -R -h 'required_providers' "$dir"/*.tf 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$count" -gt 1 ]]; then
    echo "ERROR: duplicate required_providers blocks in: $dir"
    FAILED=1
  fi
done

if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi

echo "Terraform provider pinning OK"
