# Secrets backend (normative)

This document defines the default secrets backend behavior for Samakia Fabric.

## Default

Vault is the **default secrets backend** for operator and production workflows.
The local encrypted file backend is a **documented exception only** (bootstrap,
CI fixtures, or explicit local use).

## Backend selection

- Vault default (recommended):
  - `SECRETS_BACKEND=vault`
  - `BIND_SECRETS_BACKEND=vault`
- File backend exception (explicit override required):
  - `SECRETS_BACKEND=file`
  - `BIND_SECRETS_BACKEND=file`

Runtime defaults use Vault when backend variables are unset. Operators must
set file backend explicitly for exceptions.

## Comparison

| Aspect | Vault (default) | File backend (exception) |
| --- | --- | --- |
| Availability | HA service in shared control plane | Local-only, no HA |
| Access control | Vault auth + audit logs | Runner-local file permissions |
| Encryption | TLS in transit, Vault storage encryption | AES-256-CBC encrypted file |
| CI suitability | Read-only by default; no secrets in logs | Allowed only for fixtures with explicit override |
| Evidence | Backend selection must be visible | Override must be documented |

## Security guarantees

- Secrets are never stored in Git.
- Evidence packets are redacted and secrets-safe.
- Vault usage assumes strict TLS and audited access.
- File backend usage must remain runner-local and encrypted.

## Rotation expectations

- Vault: prefer Vault-native rotation or external rotation workflows. Binding
  operations remain read-only for Vault in current tooling.
- File backend: rotation is manual and guarded via
  `make bindings.secrets.rotate` with explicit execute flags.

## HA assumptions

- Vault is deployed HA (raft) behind the shared VIP and is expected to be
  available for operator and production workflows.
- The file backend has no HA; it is a local fallback for explicit exceptions.

## Governance

- File backend usage requires an explicit override and documented rationale.
- Overrides must appear in evidence or review artifacts.

## Internal Postgres CA

The internal Postgres HAProxy TLS CA is stored runner-local by default:
`~/.config/samakia-fabric/pki/postgres-internal-ca.crt`. Binding secrets should
set `ca_ref: postgres-internal-ca.crt` to enable verify-full TLS checks.
