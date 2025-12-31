# Tenant credentials format (offline-first)

This directory stores **operator-local**, encrypted tenant credentials.
No secrets are committed to Git.

## Default storage

- Path: `~/.config/samakia-fabric/tenants/<tenant>/creds.enc`
- Encryption: AES-256-CBC (PBKDF2), compatible with `openssl enc`
- Passphrase: provided via:
  - `TENANT_CREDS_PASSPHRASE` **or**
  - `TENANT_CREDS_PASSPHRASE_FILE`

## JSON structure (decrypted)

```json
{
  "database": {
    "username": "<tenant>_database",
    "password": "<redacted>",
    "endpoint_ref": "db-primary",
    "issued_at": "<UTC timestamp>",
    "connection": {
      "host": "db.<tenant>.internal",
      "port": 5432,
      "protocol": "tcp",
      "tls_required": true
    }
  }
}
```

## Vault (optional)

If `SECRETS_BACKEND=vault` and `VAULT_WRITE=1`, credentials may be written to:

```
vault://tenants/<tenant>/<consumer>
```

Vault integration is **optional** and **never required** for acceptance.
