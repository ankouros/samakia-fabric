# Phase 2.1 Entry Checklist

Timestamp (UTC): 2025-12-30T18:33:00Z

## Criteria

1) Phase 2 acceptance marker present
- Command: test -f acceptance/PHASE2_ACCEPTED.md
- Result: PASS

2) REQUIRED-FIXES.md has no OPEN items
- Command: rg -n "OPEN" REQUIRED-FIXES.md
- Result: PASS (no matches)

3) No insecure TLS flags in automation paths
- Command: rg -n "pm_tls_insecure|PM_TLS_INSECURE|curl -k|--insecure" -S <automation_paths>
- Result: PASS

4) Proxmox API token only (no root@pam, no node SSH/SCP)
- Command: rg -n "root@pam|pm_user|pm_password|ssh .*proxmox|scp .*proxmox" -S <automation_paths>
- Result: PASS

5) Inventory contract present
- Command: test -f fabric-core/ansible/inventory/terraform.py
- Result: PASS

6) Runner env presence (safe check)
- Command: bash ops/scripts/runner-env-check.sh
- Result: PASS

Notes:
- If any criterion fails, Phase 2.1 work must stop and remediation must be recorded in REQUIRED-FIXES.md.
