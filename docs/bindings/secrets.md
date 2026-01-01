# Binding secrets model (design-only)

Bindings reference secrets by **secret_ref** only. Secret material is never
embedded in contracts or manifests.

## Secret reference rules

- Format: `tenants/<tenant>/<consumer>/<name>`
- No inline secrets or credentials in binding files
- References must stay within the same tenant

## Provider expectations

### Database (Postgres/MariaDB)
- Secret content (out of repo):
  - `username`
  - `password`
  - `database` (or DSN components)

### Message queue (RabbitMQ)
- Secret content (out of repo):
  - `username`
  - `password`
  - `vhost`

### Cache (Dragonfly)
- Secret content (out of repo):
  - `password` or `token` (if auth enabled)

### Vector (Qdrant)
- Secret content (out of repo):
  - `api_key` or token

## Where secrets live

Secrets are managed by the Phase 10/11 offline-first secrets interface and
stored locally under `~/.config/samakia-fabric/` (encrypted), or optionally
in Vault if configured. No secrets are committed to Git.
