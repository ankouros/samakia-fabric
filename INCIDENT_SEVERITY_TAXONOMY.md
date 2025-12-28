# Incident Severity Taxonomy (S0–S4) & Evidence Depth Policy

This document defines a defensible incident severity taxonomy for Samakia Fabric operations and maps each level to **proportional evidence collection** and **cryptographic evidence requirements**.

Hard constraints (platform contracts):
- Evidence collection is **read-only**: no remediation, no cleanup, no `terraform apply`
- No root SSH enablement (break-glass remains console-only)
- Strict TLS model unchanged; no insecure flags
- Evidence may be signed (single/dual-control) and optionally TSA-notarized
- No secrets in Git or evidence artifacts
- Rebuild-over-repair remains policy; severity determines evidence depth, not actions

---

## 1) Severity levels (S0–S4)

| Level | Name | Meaning |
|---|---|---|
| S0 | Non-incident | Noise / false positive |
| S1 | Low | Benign anomaly, no impact |
| S2 | Medium | Suspicious activity, limited scope |
| S3 | High | Confirmed compromise or policy breach |
| S4 | Critical | Systemic compromise, data loss, or legal impact |

### S0 — Non-incident
- Definition: Alert/noise that does not represent an incident after triage.
- Examples:
  - transient monitoring false positive
  - known benign scanner hitting a public endpoint (expected)
- Who can classify: on-call operator
- Approvals required for evidence: none
- Escalate to S1/S2 if:
  - repeated anomalies correlate across hosts/services
  - any auth anomaly is present

### S1 — Low
- Definition: Isolated anomaly with no evidence of compromise and no customer/production impact.
- Examples:
  - short-lived CPU spike explained by expected job
  - single failed SSH attempt from known management IP
- Who can classify: on-call operator
- Approvals required for evidence: none beyond standard on-call process
- Escalate to S2 if:
  - unexpected successful authentication
  - unexpected config drift is detected

### S2 — Medium
- Definition: Suspicious activity with limited scope; compromise unconfirmed but plausible.
- Examples:
  - repeated failed logins from unknown IPs
  - unexpected new listener process
  - policy drift detected on a single service host
- Who can classify: on-call operator + security reviewer (or incident commander)
- Approvals required for evidence: incident commander (or security lead) approves scope if logs may include sensitive data
- Escalate to S3 if:
  - confirmed unauthorized access
  - evidence of persistence mechanisms
  - tampering indicators in auth/system logs

### S3 — High
- Definition: Confirmed compromise or confirmed policy breach (security boundary violated).
- Examples:
  - unauthorized SSH access as `samakia`
  - unexpected sudo activity without change record
  - evidence of persistence or credential theft
- Who can classify: incident commander + security lead
- Approvals required for evidence: security lead approves scope; legal/HR per org policy if PII exposure suspected
- Escalate to S4 if:
  - compromise spans multiple systems/failure domains
  - evidence of data access/exfiltration
  - cluster control-plane integrity is in question

### S4 — Critical
- Definition: Systemic compromise, confirmed data loss/exfiltration, or legal/regulatory impact.
- Examples:
  - Proxmox cluster compromise indicators
  - widespread unauthorized access across nodes
  - confirmed sensitive data exposure
- Who can classify: incident commander + security lead + executive/required authority (per policy)
- Approvals required for evidence: security + legal (per org policy); scope is explicitly documented
- Escalation: none (top severity); expand incident response process immediately

---

## 2) Evidence depth matrix (S0–S4)

Evidence categories:
- **System metadata** (identity, time, OS)
- **Process state** (process list, sessions)
- **Network state** (interfaces/routes/sockets)
- **Auth/security logs** (sshd/sudo/journald filters)
- **File integrity hashes** (hashes of critical config, no secrets)
- **Package inventory** (installed packages; update config evidence)
- **Application evidence** (version, config fingerprints, log sink references)
- **External references** (ticket IDs, alert IDs, evidence storage path)

Depth levels:
- **None**: do not collect
- **Minimal**: short, scoped outputs
- **Standard**: reasonable depth for investigation
- **Deep**: expanded scope (still read-only; avoid sensitive artifacts unless explicitly authorized)

| Category | S0 | S1 | S2 | S3 | S4 |
|---|---:|---:|---:|---:|---:|
| System metadata | None | Minimal | Standard | Standard | Deep |
| Process state | None | Minimal | Standard | Deep | Deep |
| Network state | None | Minimal | Standard | Deep | Deep |
| Auth/security logs | None | Minimal | Standard | Deep | Deep (policy-approved) |
| File integrity hashes | None | Minimal | Standard | Deep | Deep |
| Package inventory | None | None | Standard | Standard | Standard |
| Application evidence | None | Minimal | Standard | Standard | Deep |
| External references | Minimal | Standard | Standard | Deep | Deep |

### Prohibited evidence (by severity)

| Severity | Prohibited by default |
|---|---|
| S0 | everything beyond basic triage notes |
| S1 | sensitive logs, large log exports, any dumps |
| S2 | memory dumps, disk images, full database dumps, secret material |
| S3 | memory dumps and disk images unless explicitly authorized; secret material always prohibited |
| S4 | secret material always prohibited; memory/disk imaging only with explicit authorization and separate runbook (not provided here) |

Note: “Deep” does not mean “collect everything”. It means “collect the right things at sufficient depth”.

---

## 3) Cryptographic requirements (signing / dual-control / TSA)

Policy (defensible default):

| Severity | Signing | Dual-control | TSA notarization |
|---|---|---|---|
| S0 | No | No | No |
| S1 | Optional | No | No |
| S2 | Required | Optional | Optional |
| S3 | Required | Yes | Optional |
| S4 | Required | Yes | Required |

Rationale:
- S0: no evidence packet should be created; avoid noise and over-collection.
- S1: evidence may be useful for trend analysis; signature is optional.
- S2: evidence should be integrity-protected; dual-control and TSA are risk-based.
- S3: chain-of-custody becomes critical; dual-control prevents single-actor evidence authority.
- S4: highest scrutiny; dual-control + TSA provide independent proof of authority and time-of-existence.

---

## 4) Authorization policy (who approves what)

Minimum governance:
- S0/S1: on-call operator follows standard ops process.
- S2: incident commander approves evidence scope; security lead consulted if logs may include sensitive content.
- S3/S4: security lead approves evidence scope; legal/HR approvals per organization policy where required.

Always record in evidence metadata:
- who authorized
- when
- scope boundaries (what was excluded and why)
