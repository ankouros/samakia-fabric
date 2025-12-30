#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out="${FABRIC_REPO_ROOT}/acceptance/PHASE2_2_ENTRY_CHECKLIST.md"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

pass() { echo "- Result: PASS"; }
fail() { echo "- Result: FAIL"; }

{
  echo "# Phase 2.2 Entry Checklist"
  echo
  echo "Timestamp (UTC): ${now}"
  echo
  echo "## Criteria"
  echo
  echo "1) Phase 2 acceptance marker present"
  echo "- Command: test -f acceptance/PHASE2_ACCEPTED.md"
  if test -f "${FABRIC_REPO_ROOT}/acceptance/PHASE2_ACCEPTED.md"; then pass; else fail; fi
  echo
  echo "2) Phase 2.1 acceptance marker present"
  echo "- Command: test -f acceptance/PHASE2_1_ACCEPTED.md"
  if test -f "${FABRIC_REPO_ROOT}/acceptance/PHASE2_1_ACCEPTED.md"; then pass; else fail; fi
  echo
  echo "3) REQUIRED-FIXES.md has no OPEN items"
  echo "- Command: rg -n \"OPEN\" REQUIRED-FIXES.md"
  if rg -n "OPEN" "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md" >/dev/null 2>&1; then fail; else echo "- Result: PASS (no matches)"; fi
  echo
  echo "4) No insecure TLS flags in automation paths"
  echo "- Command: rg -n \"pm_tls_insecure|PM_TLS_INSECURE|curl -k|--insecure\" -S <automation_paths>"
  if rg -n "pm_tls_insecure|PM_TLS_INSECURE|curl -k|--insecure" -S \
    "${FABRIC_REPO_ROOT}/ops/scripts" \
    "${FABRIC_REPO_ROOT}/fabric-core/terraform" \
    "${FABRIC_REPO_ROOT}/fabric-core/ansible" \
    "${FABRIC_REPO_ROOT}/fabric-ci/scripts" \
    "${FABRIC_REPO_ROOT}/Makefile" \
    --glob '!check-proxmox-ca-and-tls.sh' \
    --glob '!enforce-terraform-provider.sh' \
    --glob '!phase2-1-entry-check.sh' \
    --glob '!phase2-2-entry-check.sh' >/dev/null 2>&1; then
    fail
  else
    echo "- Result: PASS"
  fi
  echo
  echo "5) Proxmox API token only (no root@pam, no node SSH/SCP)"
  echo "- Command: rg -n \"root@pam|pm_user|pm_password|ssh .*proxmox|scp .*proxmox\" -S <automation_paths>"
  if rg -n "root@pam|pm_user|pm_password|ssh .*proxmox|scp .*proxmox" -S \
    "${FABRIC_REPO_ROOT}/ops/scripts" \
    "${FABRIC_REPO_ROOT}/fabric-core/terraform" \
    "${FABRIC_REPO_ROOT}/fabric-core/ansible" \
    "${FABRIC_REPO_ROOT}/fabric-ci/scripts" \
    "${FABRIC_REPO_ROOT}/Makefile" \
    --glob '!check-proxmox-ca-and-tls.sh' \
    --glob '!phase2-1-entry-check.sh' \
    --glob '!phase2-2-entry-check.sh' >/dev/null 2>&1; then
    fail
  else
    echo "- Result: PASS"
  fi
  echo
  echo "6) Inventory contract present"
  echo "- Command: test -f fabric-core/ansible/inventory/terraform.py"
  if test -f "${FABRIC_REPO_ROOT}/fabric-core/ansible/inventory/terraform.py"; then pass; else fail; fi
  echo
  echo "7) Runner env presence (safe check)"
  echo "- Command: bash ops/scripts/runner-env-check.sh"
  if bash "${FABRIC_REPO_ROOT}/ops/scripts/runner-env-check.sh" >/dev/null 2>&1; then pass; else fail; fi
  echo
  echo "Notes:"
  echo "- If any criterion fails, Phase 2.2 work must stop and remediation must be recorded in REQUIRED-FIXES.md."
} > "${out}"

printf "Wrote %s\n" "${out}"
