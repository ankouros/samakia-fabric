#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  forensics-severity-guide.sh <S0|S1|S2|S3|S4>

Prints:
  - required evidence depth per category
  - signing / dual-control / TSA requirements
  - authorization checklist

This helper is read-only:
  - no filesystem writes
  - no network access
  - no evidence collection

Policy source: INCIDENT_SEVERITY_TAXONOMY.md
EOF
}

sev="${1:-}"
case "${sev}" in
  S0|S1|S2|S3|S4) ;;
  -h|--help|"")
    usage
    exit 0
    ;;
  *)
    echo "ERROR: invalid severity: ${sev} (expected S0..S4)" >&2
    usage
    exit 2
    ;;
esac

print_matrix() {
  cat <<'EOF'
Evidence categories:
- System metadata
- Process state
- Network state
- Auth/security logs
- File integrity hashes
- Package inventory
- Application evidence
- External references
EOF
}

case "${sev}" in
  S0)
    cat <<'EOF'
Severity: S0 (Non-incident)

Evidence depth:
- None (do not produce an evidence packet by default)

Crypto requirements:
- Signing: No
- Dual-control: No
- TSA: No

Authorization:
- On-call operator triage only

Notes:
- Record a short triage note and close as noise/false positive.
EOF
    ;;
  S1)
    cat <<'EOF'
Severity: S1 (Low)

Evidence depth:
- System metadata: minimal
- Process state: minimal
- Network state: minimal
- Auth/security logs: minimal (scoped; avoid sensitive exports)
- File integrity hashes: minimal
- Package inventory: none
- Application evidence: minimal
- External references: standard

Crypto requirements:
- Signing: Optional
- Dual-control: No
- TSA: No

Authorization:
- Standard on-call process
EOF
    ;;
  S2)
    cat <<'EOF'
Severity: S2 (Medium)

Evidence depth:
- System metadata: standard
- Process state: standard
- Network state: standard
- Auth/security logs: standard (approved scope)
- File integrity hashes: standard
- Package inventory: standard
- Application evidence: standard
- External references: standard

Crypto requirements:
- Signing: Required
- Dual-control: Optional
- TSA: Optional

Authorization:
- Incident commander approves evidence scope
- Security consulted if logs may include sensitive content
EOF
    ;;
  S3)
    cat <<'EOF'
Severity: S3 (High)

Evidence depth:
- System metadata: standard
- Process state: deep
- Network state: deep
- Auth/security logs: deep (approved scope)
- File integrity hashes: deep
- Package inventory: standard
- Application evidence: standard
- External references: deep

Crypto requirements:
- Signing: Required
- Dual-control: Required
- TSA: Optional

Authorization:
- Incident commander + security lead approve scope
- Legal/HR per policy if data exposure suspected
EOF
    ;;
  S4)
    cat <<'EOF'
Severity: S4 (Critical)

Evidence depth:
- System metadata: deep
- Process state: deep
- Network state: deep
- Auth/security logs: deep (policy-approved)
- File integrity hashes: deep
- Package inventory: standard
- Application evidence: deep
- External references: deep

Crypto requirements:
- Signing: Required
- Dual-control: Required
- TSA: Required

Authorization:
- Incident commander + security lead + required authority (per policy)
- Legal involvement expected where applicable
EOF
    ;;
esac

echo
print_matrix
echo
echo "See: INCIDENT_SEVERITY_TAXONOMY.md and OPERATIONS_POST_INCIDENT_FORENSICS.md"
