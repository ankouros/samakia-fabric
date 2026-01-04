# MCP Deployment (Read-Only)

This directory contains deployment artifacts for the read-only MCP services.

## Systemd (recommended)

1) Copy the environment template and adjust paths:

```bash
sudo mkdir -p /etc/samakia-fabric
sudo cp ops/ai/mcp/deploy/env.example /etc/samakia-fabric/mcp.env
sudo edit /etc/samakia-fabric/mcp.env
```

2) Copy the service units and adjust the repo path/user if needed:

```bash
sudo cp ops/ai/mcp/deploy/systemd/*.service /etc/systemd/system/
```

3) Reload and start the services:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now mcp-repo.service mcp-evidence.service mcp-observability.service \
  mcp-runbooks.service mcp-qdrant.service
```

4) Stop all MCP services:

```bash
sudo systemctl stop mcp-repo.service mcp-evidence.service mcp-observability.service \
  mcp-runbooks.service mcp-qdrant.service
```

Notes:
- These units run as a non-root user (`samakia` by default). Update the units if your operator user differs.
- MCP audit logs are written under `evidence/ai/mcp-audit/` inside the repo.
- Systemd logs are written to journald by default.
- Live access remains guarded (set `OBS_LIVE=1` or `QDRANT_LIVE=1` in `/etc/samakia-fabric/mcp.env`).
- `make ai.mcp.start`/`make ai.mcp.stop` accept `MCP_SERVICES="mcp-repo ..."` and `MCP_SYSTEMD_SCOPE=user`.

## Environment file

`/etc/samakia-fabric/mcp.env` must define:
- `FABRIC_REPO_ROOT` (absolute path to the repo)
- `RUNNER_MODE=operator`
- `MCP_BIND_ADDRESS` (default `127.0.0.1`)
- `OBS_LIVE=0|1` (observability MCP)
- `QDRANT_LIVE=0|1` (qdrant MCP)

Ports are configured in the systemd unit files via `MCP_PORT`.
