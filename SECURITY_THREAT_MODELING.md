# Security Threat Modeling — Samakia Fabric (Read-only, Systematic, Evidence-aware)

This document defines a **repeatable threat modeling discipline** for:
- the Samakia Fabric substrate (Proxmox/LXC + Terraform/Ansible + GitOps)
- typical applications hosted on top of it (APIs, frontends, data stores)

Hard rules:
- Threat modeling outputs are **analysis artifacts**, not facts.
- Threat modeling does not mutate infrastructure, configuration, or evidence.
- References to incidents/evidence must point to **existing, verified** evidence packs (paths + hashes), not copies.

Related documents (inputs/feedback loops):
- `SECURITY.md` (security policy and trust boundaries)
- `INCIDENT_SEVERITY_TAXONOMY.md` (S0–S4 severity mapping)
- `COMPLIANCE_CONTROLS.md` (application compliance overlay controls)
- `OPERATIONS_POST_INCIDENT_FORENSICS.md` (facts-only evidence collection)
- `OPERATIONS_CROSS_INCIDENT_CORRELATION.md` (timelines + hypotheses, derived-only)
- `OPERATIONS_COMPLIANCE_AUDIT.md` (signed snapshots, offline verification)
- `OPERATIONS_KEY_CUSTODY_DUAL_CONTROL.md` (dual-control signing governance)
- `OPERATIONS_EVIDENCE_NOTARIZATION.md` (optional TSA notarization)

---

## A) Scope & Assumptions

### In scope
- **Management plane**: Terraform + Ansible execution from a runner host, GitOps workflow, CI hooks and guardrails.
- **Proxmox control plane**: API access, delegated-user model, template lifecycle, cluster availability assumptions.
- **Compute plane**: LXC containers (unprivileged by default), bootstrap/hardening model, SSH access model.
- **Audit/evidence plane**: drift audits, signed compliance snapshots, forensics packets, legal hold labels, correlation artifacts.
- **Applications**: APIs/frontends and common backing services (DB/MQ/cache) hosted on LXC.

### Out of scope (explicit)
- Physical security (rack access, power, hardware tamper).
- Operator endpoint security beyond stated assumptions (workstations can be compromised; mitigate by process).
- Hypervisor/firmware supply chain validation (mention as risk, not solved here).
- Application-specific business logic flaws (covered by app owners, only integrated as evidence patterns).

### Trust assumptions (explicit)
- Git is the source of truth (access-controlled; reviews are meaningful).
- Proxmox API is accessed over strict TLS via internal CA trusted by the runner host (no insecure flags).
- Proxmox automation uses **API tokens** with least privilege (no `root@pam` for automation).
- Containers are replaceable; rebuild-over-repair is the default remediation posture.
- Evidence signing (single/dual-control) and optional TSA notarization provide integrity/provenance for artifacts, not correctness of conclusions.

---

## B) Modeling Approach (Why this fits Samakia Fabric)

Samakia Fabric is an infrastructure substrate with strong layering contracts. A “single-method” model is insufficient, so we use a combined approach:

1) **Trust boundary + data flow decomposition**
- Identify components, trust boundaries, and what crosses them (tokens, SSH keys, templates, state, evidence).
- This matches the platform’s “layer contracts” and delegated privilege model.

2) **STRIDE threat categorization**
- Classify threats as Spoofing, Tampering, Repudiation, Information Disclosure, DoS, Elevation.
- This provides consistent threat naming and helps drive controls mapping.

3) **Evidence-aware feedback loop**
- For each threat: document how it would be detected/validated using existing evidence channels (compliance snapshots, forensics packets, correlation artifacts).
- This aligns threat modeling with operational reality (day-2, audits, incidents) without adding agents or enforcement.

---

## C) System Decomposition (Components, Boundaries, Data Flows)

### C1) Proxmox cluster (control plane)
- Responsibilities: cluster scheduling, LXC lifecycle, template storage, API authZ/authN.
- Trust boundaries:
  - Proxmox API boundary (token auth, TLS trust).
  - Node shell boundary (root on node; break-glass only; outside automation).
- Data flows (high level):
  - Terraform → Proxmox API (create/modify LXC resources).
  - Template upload → Proxmox API/storage (immutable templates).

### C2) Terraform runner (management plane)
- Responsibilities: declare infrastructure state, produce plans, apply changes explicitly, render Ansible inventory.
- Trust boundaries:
  - Runner host trust store (internal CA trust anchor).
  - TF state / plan outputs boundary (integrity and confidentiality).
- Data flows:
  - Env vars (token IDs/secrets, SSH public keys) → Terraform provider.
  - `terraform output -json` → Ansible inventory.

### C3) Ansible runner (configuration plane)
- Responsibilities: bootstrap and harden containers, enforce policy idempotently.
- Trust boundaries:
  - SSH boundary: root key-only bootstrap then root SSH disabled permanently; ongoing access via `samakia`.
- Data flows:
  - Inventory (IP resolution) → SSH connectivity.
  - Playbooks/roles → container configuration (idempotent).

### C4) LXC containers (compute plane)
- Responsibilities: run workloads; treated as replaceable units.
- Trust boundaries:
  - Container boundary (unprivileged by default; cannot assume host control).
  - Service boundary (apps + data stores + secrets management practices).
- Data flows:
  - SSH keys (authorized_keys) and policy configs (sshd/sysctl/logging).

### C5) Evidence & audit tooling (audit plane)
- Responsibilities: observe drift, package evidence deterministically, sign/notarize, verify offline.
- Trust boundaries:
  - Evidence artifact directory boundaries (immutable after manifest/signature).
  - Derived artifacts boundary (correlation timelines/hypotheses are not evidence).
- Data flows:
  - Terraform drift (`plan`) + Ansible check outputs → compliance snapshot.
  - Forensics command outputs → forensics packet.
  - Legal hold labels → label pack (independent of evidence manifest).
  - Correlation outputs → derived correlation pack (independent).

### C6) External dependencies (bounded)
- Internal CA: trust anchor for Proxmox API TLS (runner host).
- Optional TSA: timestamp notarization for evidence manifests (strict TLS, offline verification).
- Artifact storage: out of scope to implement; referenced as operational practice only.

---

## D) Threat Catalog (STRIDE + S0–S4 + Control Mapping)

Format conventions:
- Each threat is a single entry with consistent fields.
- Severity must map to `INCIDENT_SEVERITY_TAXONOMY.md`.
- “Existing mitigations” must reference current controls/runbooks (no speculative controls).

### TM-FABRIC-001 — Proxmox API token exfiltration from runner host
- Components: Terraform runner, Proxmox API
- STRIDE: Information Disclosure → Elevation
- Preconditions: attacker can read runner env/history/process state or CI logs
- Impact: cluster-wide control within token scope; potential fleet compromise (S4 if broad ACL)
- Likelihood: medium (workstation/runner compromise is plausible)
- Severity (S0–S4): S4
- Existing mitigations:
  - Token-based auth (no passwords) and delegated user model (`SECURITY.md`)
  - Guardrails against insecure TLS (`fabric-ci/scripts/check-proxmox-ca-and-tls.sh`)
  - “No secrets in Git” + pre-commit secret detection (`.pre-commit-config.yaml`)
- Residual risk:
  - Tokens are bearer credentials; compromise is catastrophic within scope
  - Requires operational discipline for shell history and CI logs
- Evidence/incident linkage (optional): compliance snapshots showing env configuration MUST NOT include token values (`OPERATIONS_COMPLIANCE_AUDIT.md`)

### TM-FABRIC-002 — Internal CA trust anchor compromise (Proxmox API MITM)
- Components: Runner host trust store, Proxmox API
- STRIDE: Spoofing, Tampering
- Preconditions: attacker can install/replace CA in runner trust store or intercept CA distribution
- Impact: MITM of Proxmox API; token capture; state tampering (S4)
- Likelihood: low–medium (depends on host hardening and distribution process)
- Severity: S4
- Existing mitigations:
  - Strict TLS requirement (no insecure flags) (`SECURITY.md`, `fabric-ci/scripts/check-proxmox-ca-and-tls.sh`)
  - Explicit CA install procedure (`ops/scripts/install-proxmox-ca.sh`)
- Residual risk:
  - Trust store is a single point of failure; requires OS-level integrity controls outside repo

### TM-FABRIC-003 — Terraform state exposure or tampering
- Components: Terraform runner, state storage (local/remote)
- STRIDE: Information Disclosure, Tampering, Repudiation
- Preconditions: attacker can read/modify tfstate or plan artifacts
- Impact: leak of infrastructure topology; injection of malicious drift; forced destructive changes (S3–S4)
- Likelihood: medium (state is often mishandled)
- Severity: S3 (state exposure) / S4 (state tampering leading to compromise)
- Existing mitigations:
  - Explicit “no secrets in Git” and `.tfvars` ignored (`.gitignore`)
  - Drift detection separates detection from remediation (`ops/scripts/drift-audit.sh`)
- Residual risk:
  - State backend security is operator responsibility; must be documented per deployment

### TM-FABRIC-004 — Provider supply-chain substitution (wrong provider / malicious fork)
- Components: Terraform modules/envs, CI hooks
- STRIDE: Tampering
- Preconditions: dependency confusion or unpinned provider source/version
- Impact: arbitrary infrastructure operations (S4)
- Likelihood: low (if pinning enforced); high (if not)
- Severity: S4
- Existing mitigations:
  - Provider pinning enforcement (`fabric-ci/scripts/enforce-terraform-provider.sh`)
  - Explicit prohibition of forbidden provider (`hashicorp/proxmox`) in policy docs
- Residual risk:
  - Requires continuous enforcement in reviews/CI

### TM-FABRIC-005 — Bootstrap SSH lockout or unintended persistent root SSH
- Components: LXC containers, Ansible bootstrap
- STRIDE: DoS, Elevation
- Preconditions: bootstrap/hardening misorders tasks or misconfigures sshd
- Impact: operator lockout (DoS) or persistent root remote access (S3)
- Likelihood: medium (bootstrap is sensitive)
- Severity: S2 (lockout) / S3 (root SSH remains reachable)
- Existing mitigations:
  - Two-phase model (bootstrap then harden) (`OPERATIONS.md`)
  - Break-glass console-only recovery (`OPERATIONS_BREAK_GLASS.md`)
  - Hardening baseline enforces `PermitRootLogin no` (`fabric-core/ansible/playbooks/harden.yml`)
- Residual risk:
  - Misconfiguration can still occur; rely on console channel for recovery

### TM-FABRIC-006 — SSH key injection drift (unexpected keys in authorized_keys)
- Components: Terraform vars, Ansible, container access model
- STRIDE: Spoofing, Elevation
- Preconditions: unauthorized change to key list in Git or env var
- Impact: persistent unauthorized access (S3/S4 depending on scope)
- Likelihood: medium (keys rotate; mistakes happen)
- Severity: S3
- Existing mitigations:
  - Git review model; key-only access (no passwords) (`SECURITY.md`)
  - Key rotation procedure with “keep 2 keys” guidance (`OPERATIONS_BREAK_GLASS.md`)
- Residual risk:
  - Requires strong repo access controls and review hygiene

### TM-FABRIC-007 — Proxmox delegated-user over-privilege
- Components: Proxmox IAM/ACLs, Terraform provider
- STRIDE: Elevation
- Preconditions: token user is granted broad privileges beyond intended scope
- Impact: compromise blast radius increases to S4
- Likelihood: medium (ACLs are often too broad)
- Severity: S4
- Existing mitigations:
  - Delegated-user contract and “no root@pam” (`SECURITY.md`)
  - Auditability via compliance snapshots (captures env metadata, not secrets) (`OPERATIONS_COMPLIANCE_AUDIT.md`)
- Residual risk:
  - Requires Proxmox-side governance not enforceable by Terraform under delegated constraints

### TM-FABRIC-008 — LXC escape / container-to-host breakout
- Components: LXC containers, Proxmox host
- STRIDE: Elevation
- Preconditions: kernel/LXC vulnerability; privileged container; unsafe feature flags
- Impact: host compromise; cluster compromise (S4)
- Likelihood: low–medium (varies with patching discipline)
- Severity: S4
- Existing mitigations:
  - Unprivileged containers by default; feature flags controlled (not mutated by Terraform) (`SECURITY.md`)
  - Unattended security updates baseline in hardening (`fabric-core/ansible/playbooks/harden.yml`)
- Residual risk:
  - Host kernel is shared; patch cadence and host hardening are critical

### TM-FABRIC-009 — DoS against Proxmox API / cluster quorum instability
- Components: Proxmox API, cluster, management plane
- STRIDE: DoS
- Preconditions: network disruption, API overload, quorum loss
- Impact: inability to manage fleet; cascading failure during incident (S2–S3)
- Likelihood: medium (ops events happen)
- Severity: S3
- Existing mitigations:
  - HA failure domain runbook guidance (`OPERATIONS_HA_FAILURE_DOMAINS.md`)
  - Rebuild-over-repair reduces “live surgery” requirements (`OPERATIONS.md`)
- Residual risk:
  - Workload-level HA remains separate; Proxmox HA is not application HA

### TM-FABRIC-010 — Evidence tampering or chain-of-custody ambiguity
- Components: compliance snapshots, forensics packs, verification tooling
- STRIDE: Tampering, Repudiation
- Preconditions: attacker can modify evidence directory before it is made read-only/signed
- Impact: misleading audit trail; inability to prove facts (S3)
- Likelihood: medium (if evidence not signed promptly)
- Severity: S3
- Existing mitigations:
  - Deterministic manifests + detached signatures (`ops/scripts/compliance-snapshot.sh`, `ops/scripts/verify-compliance-snapshot.sh`)
  - Dual-control signing and TSA notarization options (`OPERATIONS_KEY_CUSTODY_DUAL_CONTROL.md`, `OPERATIONS_EVIDENCE_NOTARIZATION.md`)
- Residual risk:
  - Evidence integrity relies on disciplined signing workflow and key custody

### TM-FABRIC-011 — Legal hold scope creep / silent expansion
- Components: legal hold labels, governance
- STRIDE: Repudiation
- Preconditions: correlation/analysis expands scope without explicit hold declaration
- Impact: non-compliance with legal/regulatory constraints (S3–S4 depending on context)
- Likelihood: low–medium (process failure)
- Severity: S3
- Existing mitigations:
  - Labels-only hold packs, independent signing (`OPERATIONS_LEGAL_HOLD_RETENTION.md`, `ops/scripts/legal-hold-manage.sh`)
  - Explicit correlation workflow requiring explicit scope (`OPERATIONS_CROSS_INCIDENT_CORRELATION.md`)
- Residual risk:
  - Requires human process discipline (approvals and documentation)

### TM-APP-001 — Application secrets leakage into evidence bundles
- Components: application workloads, compliance evidence tooling
- STRIDE: Information Disclosure
- Preconditions: operator attaches configs/logs containing secrets to evidence
- Impact: credential leak; expanded breach scope (S2–S4 depending on secret)
- Likelihood: medium
- Severity: S3 (typical) / S4 (high-value credentials)
- Existing mitigations:
  - Evidence denylist and “hash-only fingerprints” in app evidence (`ops/scripts/app-compliance-evidence.sh`)
  - App controls: `APP-SEC-001` (no secrets committed/evidenced) (`COMPLIANCE_CONTROLS.md`)
- Residual risk:
  - Manual attachments remain a risk; requires review and redaction discipline

### TM-APP-002 — Inadequate audit logging for security-relevant actions
- Components: apps, log pipeline assumptions
- STRIDE: Repudiation
- Preconditions: missing audit events; logs not shipped/retained
- Impact: inability to reconstruct incidents; weak accountability (S2–S3)
- Likelihood: medium
- Severity: S2/S3
- Existing mitigations:
  - App controls: `APP-LOG-001`, `APP-LOG-002` (`COMPLIANCE_CONTROLS.md`)
  - Forensics runbook defines minimal evidence (facts-first) (`OPERATIONS_POST_INCIDENT_FORENSICS.md`)
- Residual risk:
  - Logging stack specifics are deployment-dependent; must be addressed per service group

### TM-APP-003 — Backup/restore non-determinism (RPO/RTO failure)
- Components: stateful services, ops processes
- STRIDE: DoS (data availability), Tampering (if backups untrusted)
- Preconditions: backups not tested; restore procedures missing
- Impact: prolonged outage or data loss; potential legal impact (S3–S4)
- Likelihood: medium
- Severity: S3/S4
- Existing mitigations:
  - App controls: `APP-BACKUP-001`, `APP-BACKUP-002` (`COMPLIANCE_CONTROLS.md`)
  - Rebuild-over-repair policy (infra) (`OPERATIONS.md`)
- Residual risk:
  - App-level HA/backup is outside substrate automation; must be enforced by service owners

### TM-FABRIC-012 — Correlation artifacts misrepresented as evidence
- Components: correlation workspace, governance
- STRIDE: Repudiation, Tampering (of narrative)
- Preconditions: derived timeline/hypothesis register is treated as “facts” without evidence refs
- Impact: flawed decisions; audit/legal confusion (S2–S3)
- Likelihood: medium (common failure mode in IR)
- Severity: S2/S3
- Existing mitigations:
  - Explicit separation rules and required `evidence_ref` format (`OPERATIONS_CROSS_INCIDENT_CORRELATION.md`)
  - Optional signing of derived artifacts proves integrity, not truth (`OPERATIONS_COMPLIANCE_AUDIT.md`)
- Residual risk:
  - Requires reviewer discipline; signatures don’t prevent misinterpretation

---

## E) Control & Gap Mapping (How to Use This Catalog)

Threat entries must identify:
- mitigations by **design** (e.g., unprivileged LXC, strict TLS, no root@pam automation)
- mitigations by **process** (e.g., reviews, dual-control signing, break-glass workflow)
- explicit **gaps** (what is not covered by the substrate and must be addressed by ops/app owners)

Gap recording (non-disruptive):
- Use `ROADMAP.md` for planned work and `DECISIONS.md` for architectural rationale.
- Record threat-driven backlog items as issues/PRs with the threat ID in the title:
  - Example: `TM-FABRIC-003: Terraform state hardening guidance for operators`

---

## F) Prioritization (Severity × Likelihood × Exposure)

Use this rubric to prioritize remediation/backlog work (without implementing it here):
- Severity: map to S0–S4
- Likelihood: low/medium/high
- Exposure: how broadly the threat can impact the fleet (single service vs cluster-wide)

Recommended triage cadence:
- Monthly review for S3/S4 threats and any newly observed incidents.
- Quarterly review for the full catalog.

Output of triage:
- “Accepted risk” with rationale (time-bound where possible)
- “Mitigate” with a backlog item and owner
- “Transfer” (e.g., documented operational requirement outside repo scope)

---

## G) Incident / Forensics Feedback Loop (Keeping Models Honest)

After an incident:
1) Verify evidence integrity (manifest + signatures + optional TSA) before analysis.
2) Update threat likelihood and mitigations based on facts (not conclusions).
3) If repeated patterns are found via correlation:
   - create or update a systemic threat entry
   - link to the correlation workspace (derived artifacts) and the underlying evidence refs
4) If legal hold applies:
   - label affected evidence packs (labels-only) without modifying original manifests

This closes the loop:
threat model → prioritized backlog → operational controls → evidence → updated threat model.

---

## H) Using the Optional Index Helper (Read-only)

If present, use:
```bash
bash ops/scripts/threat-model-index.sh --by severity
bash ops/scripts/threat-model-index.sh --by component
```

This prints a read-only index derived from this document.
It does not write files and does not make network calls.
