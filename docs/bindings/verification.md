# Bindings Verification

Bindings verification is a **read-only** workflow that validates workload-side
connectivity to provisioned bindings. It produces deterministic evidence packets
and never mutates infrastructure.

## Modes

### Offline (default)
- Uses rendered connection manifests under `artifacts/bindings/`.
- Performs **no secret resolution**.
- Produces evidence under `evidence/bindings-verify/<tenant>/<UTC>/`.

Command:
```bash
make bindings.verify.offline TENANT=all
```

### Live (guarded)
- Resolves `secret_ref` via the configured bindings secrets backend.
- Vault is the default backend; file usage requires an explicit override.
- Performs read-only probes to endpoints.
- Requires explicit opt-in and is **not allowed in CI**.

Guards:
- `VERIFY_MODE=live`
- `VERIFY_LIVE=1`

Command:
```bash
VERIFY_MODE=live VERIFY_LIVE=1 \
make bindings.verify.live TENANT=project-birds
```

## Evidence outputs

Evidence is written to:
```
evidence/bindings-verify/<tenant>/<UTC>/
```

Files include:
- `summary.md` (human summary)
- `results.json` (machine-readable results)
- `tls/endpoints.json` (TLS probe details)
- `manifest.sha256` (integrity)

Evidence is gitignored by default.

## Required tooling (live mode)

These tools are used for read-only probes:
- `openssl` (TLS handshake)
- `psql` (Postgres probe)
- `mariadb` or `mysql` (MariaDB probe)
- `curl` (RabbitMQ/Qdrant HTTP probe)
- `redis-cli` (Dragonfly probe)

If a tool is missing, the probe reports a warning for that consumer and the
result remains **read-only**.

## Safety guarantees

- No writes are performed to any backend.
- Missing or unreachable endpoints are reported as **unknown**, not failures.
- Live mode is blocked in CI and requires explicit guards.
