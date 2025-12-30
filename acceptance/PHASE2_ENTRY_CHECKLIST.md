# Phase 2 Entry Checklist

Timestamp (UTC): 2025-12-30T18:03:00Z

## Criteria

1) Phase 0/1 acceptance markers present
- Command: test -f acceptance/PHASE0_ACCEPTED.md && test -f acceptance/PHASE1_ACCEPTED.md
- Result: PASS

2) REQUIRED-FIXES.md has no OPEN items
- Command: rg -n "OPEN" REQUIRED-FIXES.md
- Result: PASS (no matches)

3) No insecure TLS flags
- Command: rg -n "pm_tls_insecure|PM_TLS_INSECURE|curl -k|--insecure" -S .
- Result: PASS (only guardrails/docs)

4) Proxmox API token only (no root@pam, no node SSH/SCP)
- Command: rg -n "root@pam|pm_user|pm_password|ssh .*proxmox|scp .*proxmox" -S .
- Result: PASS (references are documentation/guardrails only; no automation uses root@pam)

5) Inventory contract
- Command: test -f fabric-core/ansible/inventory/terraform.py
- Result: PASS (terraform.py exists and is canonical)

Notes:
- If any criterion fails, Phase 2 work must stop and remediation must be recorded in REQUIRED-FIXES.md.
