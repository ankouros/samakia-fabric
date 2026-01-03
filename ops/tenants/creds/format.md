# Tenant credentials format (file backend exception)

This directory stores **operator-local**, encrypted tenant credentials.
No secrets are committed to Git.

## Local file backend (exception)

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

## Vault (default)

If `SECRETS_BACKEND=vault` and `VAULT_WRITE=1`, credentials may be written to:

```
vault://tenants/<tenant>/<consumer>
```

Vault is the default backend; writes require `VAULT_WRITE=1`.
File backend usage is an explicit exception.
