# Binding secrets model

Bindings reference secrets by **secret_ref** only. Secret material is never
embedded in contracts, manifests, or evidence.

## Binding fields (required)

Each binding consumer must declare:

- `secret_ref` (string): `tenants/<tenant>/<consumer>/<name>`
- `secret_shape` (enum): `postgres`, `mariadb`, `rabbitmq`, `dragonfly`, `qdrant`
- `rotation_policy`:
  - `enabled` (bool)
  - `mode` (`manual` | `scheduled`)
  - `max_age_days` (optional, int)
  - `rotate_on_drift` (optional, bool)
- `credential_source`:
  - `existing_ref`
  - `operator_input`
  - `generated`
  - `vault_readonly`

## Secret shapes (no values in repo)

Shape templates live under `contracts/secrets/shapes/` and define **keys only**.
No secret values are stored in Git.

- Postgres: `username`, `password`, `database`, `sslmode`, `ca_ref`
- MariaDB: `username`, `password`, `database`, `tls_required`, `ca_ref`
- RabbitMQ: `username`, `password`, `vhost`, `tls_required`, `ca_ref`
- Dragonfly: `password`, `tenant_key_prefix`, `tls_required`, `ca_ref`
- Qdrant: `api_key`, `collection_prefix`, `tls_required`, `ca_ref`

## Secret backends

Vault is the **default secrets backend** for operator and production workflows.
The encrypted file backend is a **documented exception** for bootstrap/CI/local
use. See `docs/secrets/backend.md` for the normative policy.

Defaults now resolve to Vault when unset; set `BIND_SECRETS_BACKEND=file`
explicitly for exceptions.

- Vault backend (default, read-only for bindings):
  - `BIND_SECRETS_BACKEND=vault`
  - `VAULT_ENABLE=1`
- File backend (exception, explicit override):
  - `BIND_SECRETS_BACKEND=file`
  - `SECRETS_PASSPHRASE` or `SECRETS_PASSPHRASE_FILE`

## Materialization (operator-controlled)

Dry-run (evidence only):

```bash
make bindings.secrets.materialize.dryrun TENANT=all
```

Execute (writes to file backend only; guarded, explicit exception):

```bash
MATERIALIZE_EXECUTE=1 \
BIND_SECRETS_BACKEND=file \
BIND_SECRET_INPUT_FILE=./secrets-input.json \
make bindings.secrets.materialize TENANT=project-birds
```

### Input file format

`BIND_SECRET_INPUT_FILE` must be a JSON map of `secret_ref -> object`.
Objects must match the declared `secret_shape` keys.

## Rotation (operator-controlled)

Rotation plan (read-only):

```bash
make bindings.secrets.rotate.plan TENANT=all
```

Rotation dry-run (evidence only):

```bash
make bindings.secrets.rotate.dryrun TENANT=all
```

Execute rotation (writes new secret version only; explicit exception):

```bash
ROTATE_EXECUTE=1 \
ROTATE_REASON="scheduled rotation" \
BIND_SECRETS_BACKEND=file \
ROTATE_INPUT_FILE=./rotation-input.json \
make bindings.secrets.rotate TENANT=project-birds
```

Rotation does **not** cut over workloads or revoke old secrets in Part 2.

### Rotation input file format

`ROTATE_INPUT_FILE` must be a JSON map keyed by **either** the existing
`secret_ref` or the planned `new_secret_ref`. The value must be a secret
object matching the declared `secret_shape` keys.

If no input file is provided, generation is allowed only with:

- `SECRETS_GENERATE=1`
- `SECRETS_GENERATE_ALLOWLIST=tenant1,tenant2`

## Evidence (redacted)

Evidence is stored under `evidence/bindings/<tenant>/<UTC>/` and is always
redacted. Secret values never appear in evidence.

## Prod requirements

Prod operations require a valid change window and signing:

- `MAINT_WINDOW_START` / `MAINT_WINDOW_END`
- `EVIDENCE_SIGN=1` and `EVIDENCE_SIGN_KEY=<id>`

If these are missing, prod materialization or rotation **fails**.
