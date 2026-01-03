#!/usr/bin/env python3
import json
import os
import re
import subprocess
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

try:
    import yaml
except Exception as exc:  # pragma: no cover - hard failure
    raise SystemExit(f"ERROR: missing dependency for MCP server: {exc}")

MAX_BODY_BYTES = 1024 * 1024
MAX_CONTENT_BYTES = 200000


def utc_stamp():
    return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())


def load_json(value):
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return {}


def sanitize_params(params):
    if not isinstance(params, dict):
        return {}
    redacted_keys = {"vector", "embedding", "payload", "content"}
    clean = {}
    for key, value in params.items():
        if key in redacted_keys:
            clean[key] = "<redacted>"
        else:
            clean[key] = value
    return clean


def load_allowlist(path: Path):
    payload = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("allowlist must be a mapping")
    return payload


def load_redaction_patterns(contract_path: Path):
    if not contract_path.exists():
        return []
    payload = yaml.safe_load(contract_path.read_text(encoding="utf-8"))
    redaction = payload.get("redaction", {}) if isinstance(payload, dict) else {}
    patterns = redaction.get("deny_patterns", [])
    return [p for p in patterns if isinstance(p, str)]


def is_relative_to(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def normalize_relpath(relpath: str) -> str:
    rel = relpath.strip().lstrip("/")
    return str(Path(rel).as_posix())


def path_allowed(relpath: str, roots, files):
    rel = normalize_relpath(relpath)
    if rel in files:
        return True
    for root in roots:
        root_norm = normalize_relpath(root)
        if rel == root_norm or rel.startswith(f"{root_norm}/"):
            return True
    return False


def read_text_file(path: Path, redaction_patterns):
    data = path.read_text(encoding="utf-8", errors="ignore")
    for pattern in redaction_patterns:
        if re.search(pattern, data):
            return None, True, False
    truncated = len(data.encode("utf-8")) > MAX_CONTENT_BYTES
    if truncated:
        data = data.encode("utf-8")[:MAX_CONTENT_BYTES].decode("utf-8", errors="ignore")
    return data, False, truncated


def git_safe_ref(value: str) -> bool:
    if value in {"HEAD", "main"}:
        return True
    if re.match(r"^HEAD~\d+$", value):
        return True
    return bool(re.match(r"^[0-9a-fA-F]{7,40}$", value))


def list_files(root: Path, max_items: int = 500):
    items = []
    for path in root.rglob("*"):
        if path.is_file():
            rel = path.relative_to(root)
            items.append(str(rel.as_posix()))
            if len(items) >= max_items:
                break
    return items


def write_audit(repo_root: Path, request_meta, decision, response_meta):
    audit_root = repo_root / "evidence" / "ai" / "mcp-audit"
    audit_root.mkdir(parents=True, exist_ok=True)
    audit_dir = audit_root / f"{utc_stamp()}-{uuid.uuid4().hex[:8]}"
    audit_dir.mkdir(parents=True, exist_ok=True)

    (audit_dir / "request.json").write_text(
        json.dumps(request_meta, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (audit_dir / "decision.json").write_text(
        json.dumps(decision, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (audit_dir / "response.meta.json").write_text(
        json.dumps(response_meta, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    manifest_script = repo_root / "ops" / "ai" / "indexer" / "lib" / "manifest.sh"
    if manifest_script.exists():
        subprocess.run(
            [str(manifest_script), "--dir", str(audit_dir), "--out", str(audit_dir / "manifest.sha256")],
            check=False,
        )

    return audit_dir


def build_fixture(path: Path):
    if not path.exists():
        return {"ok": False, "error": "fixture_missing"}
    return json.loads(path.read_text(encoding="utf-8"))


def prometheus_query(base_url, query, start, end, step):
    params = {"query": query, "start": start, "end": end, "step": step}
    url = f"{base_url}/api/v1/query_range?{urlencode(params)}"
    req = Request(url, method="GET")
    with urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode("utf-8"))


def loki_query(base_url, query, start, end, limit):
    params = {"query": query, "start": start, "end": end, "limit": limit}
    url = f"{base_url}/loki/api/v1/query_range?{urlencode(params)}"
    req = Request(url, method="GET")
    with urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode("utf-8"))


class MCPHandler(BaseHTTPRequestHandler):
    server_version = "MCPReadOnly/1.0"

    def log_message(self, format, *args):
        return

    def do_GET(self):
        if self.path != "/healthz":
            self.send_error(404)
            return
        payload = {"status": "ok", "mcp": self.server.mcp_kind}
        self._send_json(200, payload)

    def do_POST(self):
        if self.path != "/query":
            self.send_error(404)
            return

        content_length = int(self.headers.get("Content-Length", "0"))
        if content_length > MAX_BODY_BYTES:
            self.send_error(413, "payload too large")
            return

        raw_body = self.rfile.read(content_length).decode("utf-8", errors="ignore")
        try:
            body = json.loads(raw_body) if raw_body else {}
        except json.JSONDecodeError:
            self.send_error(400, "invalid json")
            return

        identity = self.headers.get(self.server.identity_header, "").strip()
        tenant = self.headers.get(self.server.tenant_header, "").strip()
        request_id = self.headers.get(self.server.request_id_header, "").strip()

        action = body.get("action")
        params = body.get("params", {})

        decision = {"allowed": False, "reason": "uninitialized"}
        status_code = 200
        response_payload = {"ok": False, "error": "unknown"}

        try:
            response_payload, decision, status_code = self.server.handle_action(
                identity, tenant, action, params
            )
        except Exception as exc:
            decision = {"allowed": False, "reason": f"exception:{exc}"}
            status_code = 500
            response_payload = {"ok": False, "error": "internal_error"}

        response_bytes = len(json.dumps(response_payload).encode("utf-8"))
        response_meta = {
            "status": status_code,
            "bytes": response_bytes,
            "request_id": request_id,
            "action": action,
        }

        request_meta = {
            "mcp": self.server.mcp_kind,
            "identity": identity,
            "tenant": tenant,
            "action": action,
            "params": sanitize_params(params),
            "request_id": request_id,
        }

        write_audit(self.server.repo_root, request_meta, decision, response_meta)
        self._send_json(status_code, response_payload)

    def _send_json(self, status, payload):
        data = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


class MCPServer(HTTPServer):
    def __init__(self, server_address, handler_class):
        super().__init__(server_address, handler_class)
        self.repo_root = Path(os.environ["MCP_REPO_ROOT"]).resolve()
        self.mcp_kind = os.environ["MCP_KIND"]
        self.allowlist_path = Path(os.environ["MCP_ALLOWLIST"]).resolve()
        self.routes = load_json(os.environ.get("MCP_ROUTES_JSON", "{}"))
        self.allowed_actions = set(self.routes.get("actions", []))
        self.identity_header = os.environ.get("MCP_IDENTITY_HEADER", "X-MCP-Identity")
        self.tenant_header = os.environ.get("MCP_TENANT_HEADER", "X-MCP-Tenant")
        self.request_id_header = os.environ.get("MCP_REQUEST_ID_HEADER", "X-MCP-Request-Id")
        self.test_mode = os.environ.get("MCP_TEST_MODE", "0") == "1" or os.environ.get("CI", "0") == "1"
        self.redaction_patterns = load_redaction_patterns(
            self.repo_root / "contracts" / "ai" / "indexing.yml"
        )
        self.allowlist = load_allowlist(self.allowlist_path)

    def handle_action(self, identity, tenant, action, params):
        if action not in self.allowed_actions:
            return (
                {"ok": False, "error": "action_not_allowed"},
                {"allowed": False, "reason": "action_not_allowed"},
                403,
            )

        if identity not in {"operator", "tenant"}:
            return (
                {"ok": False, "error": "invalid_identity"},
                {"allowed": False, "reason": "invalid_identity"},
                403,
            )

        if not tenant:
            return (
                {"ok": False, "error": "missing_tenant"},
                {"allowed": False, "reason": "missing_tenant"},
                400,
            )

        if identity == "operator" and tenant != "platform":
            return (
                {"ok": False, "error": "operator_tenant_restricted"},
                {"allowed": False, "reason": "operator_tenant_restricted"},
                403,
            )

        if self.mcp_kind == "repo":
            return self._handle_repo(action, params)
        if self.mcp_kind == "evidence":
            return self._handle_evidence(action, tenant, params)
        if self.mcp_kind == "observability":
            return self._handle_observability(action, params)
        if self.mcp_kind == "runbooks":
            return self._handle_runbooks(action, params)
        if self.mcp_kind == "qdrant":
            return self._handle_qdrant(action, tenant, params)

        return (
            {"ok": False, "error": "unknown_mcp"},
            {"allowed": False, "reason": "unknown_mcp"},
            500,
        )

    def _handle_repo(self, action, params):
        roots = self.allowlist.get("roots", [])
        files = self.allowlist.get("files", [])

        if action == "list_files":
            target = params.get("path")
            if target:
                if not path_allowed(target, roots, files):
                    return ({"ok": False, "error": "path_not_allowed"}, {"allowed": False, "reason": "path_not_allowed"}, 403)
                root_path = (self.repo_root / normalize_relpath(target)).resolve()
                if not is_relative_to(root_path, self.repo_root):
                    return ({"ok": False, "error": "invalid_path"}, {"allowed": False, "reason": "invalid_path"}, 400)
                items = list_files(root_path)
            else:
                items = []
                for root in roots:
                    root_prefix = normalize_relpath(root)
                    root_path = (self.repo_root / root_prefix).resolve()
                    if root_path.exists():
                        items.extend([f"{root_prefix}/{item}" for item in list_files(root_path)])
                items.extend(files)
            return ({"ok": True, "data": {"files": items}}, {"allowed": True, "reason": "ok"}, 200)

        if action == "read_file":
            target = params.get("path", "")
            if not target or not path_allowed(target, roots, files):
                return ({"ok": False, "error": "path_not_allowed"}, {"allowed": False, "reason": "path_not_allowed"}, 403)
            file_path = (self.repo_root / normalize_relpath(target)).resolve()
            if not is_relative_to(file_path, self.repo_root) or not file_path.is_file():
                return ({"ok": False, "error": "file_not_found"}, {"allowed": False, "reason": "file_not_found"}, 404)
            content, denied, truncated = read_text_file(file_path, self.redaction_patterns)
            if denied:
                return ({"ok": False, "error": "redacted"}, {"allowed": False, "reason": "redacted"}, 403)
            if content is None:
                return ({"ok": False, "error": "read_failed"}, {"allowed": False, "reason": "read_failed"}, 500)
            return (
                {"ok": True, "data": {"path": target, "content": content, "truncated": truncated}},
                {"allowed": True, "reason": "ok"},
                200,
            )

        if action == "git_diff":
            base = params.get("base", "")
            target = params.get("target", "")
            relpath = params.get("path", "")
            if not git_safe_ref(base) or not git_safe_ref(target):
                return ({"ok": False, "error": "invalid_ref"}, {"allowed": False, "reason": "invalid_ref"}, 400)
            if relpath and not path_allowed(relpath, roots, files):
                return ({"ok": False, "error": "path_not_allowed"}, {"allowed": False, "reason": "path_not_allowed"}, 403)
            args = ["git", "diff", "--no-color", base, target]
            if relpath:
                args.extend(["--", relpath])
            result = subprocess.run(args, cwd=self.repo_root, capture_output=True, text=True, check=False)
            output = result.stdout[:MAX_CONTENT_BYTES]
            return (
                {"ok": True, "data": {"diff": output, "truncated": len(result.stdout) > MAX_CONTENT_BYTES}},
                {"allowed": True, "reason": "ok"},
                200,
            )

        if action == "git_log":
            relpath = params.get("path", "")
            limit = int(params.get("limit", 10))
            limit = max(1, min(limit, 20))
            if relpath and not path_allowed(relpath, roots, files):
                return ({"ok": False, "error": "path_not_allowed"}, {"allowed": False, "reason": "path_not_allowed"}, 403)
            args = ["git", "log", f"-n{limit}", "--pretty=format:%H|%s|%ad", "--date=iso"]
            if relpath:
                args.extend(["--", relpath])
            result = subprocess.run(args, cwd=self.repo_root, capture_output=True, text=True, check=False)
            entries = []
            for line in result.stdout.splitlines():
                parts = line.split("|", 2)
                if len(parts) == 3:
                    entries.append({"commit": parts[0], "subject": parts[1], "date": parts[2]})
            return ({"ok": True, "data": {"log": entries}}, {"allowed": True, "reason": "ok"}, 200)

        return ({"ok": False, "error": "unknown_action"}, {"allowed": False, "reason": "unknown_action"}, 400)

    def _handle_evidence(self, action, tenant, params):
        roots = self.allowlist.get("roots", [])
        if action == "list_evidence":
            base = params.get("path", "evidence")
            if not path_allowed(base, roots, []):
                return ({"ok": False, "error": "path_not_allowed"}, {"allowed": False, "reason": "path_not_allowed"}, 403)
            root_path = (self.repo_root / normalize_relpath(base)).resolve()
            if not root_path.exists() or not is_relative_to(root_path, self.repo_root):
                return ({"ok": False, "error": "not_found"}, {"allowed": False, "reason": "not_found"}, 404)
            items = []
            for path in root_path.rglob("*"):
                if path.is_dir():
                    rel = path.relative_to(self.repo_root).as_posix()
                    if f"/{tenant}/" in f"/{rel}/":
                        items.append(rel)
                        if len(items) >= 200:
                            break
            return ({"ok": True, "data": {"directories": items}}, {"allowed": True, "reason": "ok"}, 200)

        if action == "read_file":
            target = params.get("path", "")
            if not target:
                return ({"ok": False, "error": "path_required"}, {"allowed": False, "reason": "path_required"}, 400)
            if not path_allowed(target, roots, []):
                return ({"ok": False, "error": "path_not_allowed"}, {"allowed": False, "reason": "path_not_allowed"}, 403)
            rel = normalize_relpath(target)
            if f"/{tenant}/" not in f"/{rel}/":
                return ({"ok": False, "error": "tenant_isolation"}, {"allowed": False, "reason": "tenant_isolation"}, 403)
            file_path = (self.repo_root / rel).resolve()
            if not is_relative_to(file_path, self.repo_root) or not file_path.is_file():
                return ({"ok": False, "error": "file_not_found"}, {"allowed": False, "reason": "file_not_found"}, 404)
            content, denied, _ = read_text_file(file_path, self.redaction_patterns)
            if denied:
                return ({"ok": False, "error": "redacted"}, {"allowed": False, "reason": "redacted"}, 403)
            return (
                {"ok": True, "data": {"path": rel, "content": content}},
                {"allowed": True, "reason": "ok"},
                200,
            )

        return ({"ok": False, "error": "unknown_action"}, {"allowed": False, "reason": "unknown_action"}, 400)

    def _handle_observability(self, action, params):
        prom = self.allowlist.get("prometheus", {})
        loki = self.allowlist.get("loki", {})
        limits = self.allowlist.get("limits", {})
        max_range = int(limits.get("max_range_seconds", 3600))
        max_step = int(limits.get("max_step_seconds", 300))

        if action == "query_prometheus":
            query_name = params.get("query_name")
            start = int(params.get("start", 0))
            end = int(params.get("end", 0))
            step = int(params.get("step", 60))
            if end <= start or (end - start) > max_range or step > max_step:
                return ({"ok": False, "error": "range_invalid"}, {"allowed": False, "reason": "range_invalid"}, 400)
            expr = None
            for item in prom.get("queries", []):
                if item.get("name") == query_name:
                    expr = item.get("expr")
                    break
            if not expr:
                return ({"ok": False, "error": "query_not_allowed"}, {"allowed": False, "reason": "query_not_allowed"}, 403)
            if self.test_mode:
                fixture = build_fixture(self.repo_root / "ops" / "ai" / "mcp" / "observability" / "fixtures" / "prometheus.json")
                fixture["source"] = "fixture"
                return ({"ok": True, "data": fixture}, {"allowed": True, "reason": "fixture"}, 200)
            if os.environ.get("OBS_LIVE") != "1":
                return ({"ok": False, "error": "live_disabled"}, {"allowed": False, "reason": "live_disabled"}, 403)
            data = prometheus_query(prom.get("base_url"), expr, start, end, step)
            return ({"ok": True, "data": data}, {"allowed": True, "reason": "live"}, 200)

        if action == "query_loki":
            query_name = params.get("query_name")
            start = int(params.get("start", 0))
            end = int(params.get("end", 0))
            limit = int(params.get("limit", 100))
            if end <= start or (end - start) > max_range:
                return ({"ok": False, "error": "range_invalid"}, {"allowed": False, "reason": "range_invalid"}, 400)
            expr = None
            for item in loki.get("queries", []):
                if item.get("name") == query_name:
                    expr = item.get("expr")
                    break
            if not expr:
                return ({"ok": False, "error": "query_not_allowed"}, {"allowed": False, "reason": "query_not_allowed"}, 403)
            if self.test_mode:
                fixture = build_fixture(self.repo_root / "ops" / "ai" / "mcp" / "observability" / "fixtures" / "loki.json")
                fixture["source"] = "fixture"
                return ({"ok": True, "data": fixture}, {"allowed": True, "reason": "fixture"}, 200)
            if os.environ.get("OBS_LIVE") != "1":
                return ({"ok": False, "error": "live_disabled"}, {"allowed": False, "reason": "live_disabled"}, 403)
            data = loki_query(loki.get("base_url"), expr, start, end, limit)
            return ({"ok": True, "data": data}, {"allowed": True, "reason": "live"}, 200)

        return ({"ok": False, "error": "unknown_action"}, {"allowed": False, "reason": "unknown_action"}, 400)

    def _handle_runbooks(self, action, params):
        roots = self.allowlist.get("roots", [])
        if action == "list_runbooks":
            items = []
            for root in roots:
                root_prefix = normalize_relpath(root)
                root_path = (self.repo_root / root_prefix).resolve()
                if root_path.exists():
                    items.extend([f"{root_prefix}/{item}" for item in list_files(root_path)])
            return ({"ok": True, "data": {"runbooks": items}}, {"allowed": True, "reason": "ok"}, 200)

        if action == "read_runbook":
            target = params.get("path", "")
            if not target or not path_allowed(target, roots, []):
                return ({"ok": False, "error": "path_not_allowed"}, {"allowed": False, "reason": "path_not_allowed"}, 403)
            file_path = (self.repo_root / normalize_relpath(target)).resolve()
            if not is_relative_to(file_path, self.repo_root) or not file_path.is_file():
                return ({"ok": False, "error": "file_not_found"}, {"allowed": False, "reason": "file_not_found"}, 404)
            content, denied, _ = read_text_file(file_path, self.redaction_patterns)
            if denied:
                return ({"ok": False, "error": "redacted"}, {"allowed": False, "reason": "redacted"}, 403)
            return (
                {"ok": True, "data": {"path": target, "content": content}},
                {"allowed": True, "reason": "ok"},
                200,
            )

        return ({"ok": False, "error": "unknown_action"}, {"allowed": False, "reason": "unknown_action"}, 400)

    def _handle_qdrant(self, action, tenant, params):
        if action != "search":
            return ({"ok": False, "error": "unknown_action"}, {"allowed": False, "reason": "unknown_action"}, 400)
        vector = params.get("vector")
        if not isinstance(vector, list) or not vector:
            return ({"ok": False, "error": "vector_required"}, {"allowed": False, "reason": "vector_required"}, 400)
        if len(vector) > 4096:
            return ({"ok": False, "error": "vector_too_large"}, {"allowed": False, "reason": "vector_too_large"}, 400)
        top_k = int(params.get("top_k", 5))
        top_k = max(1, min(top_k, 10))

        if self.test_mode:
            fixture = build_fixture(self.repo_root / "ops" / "ai" / "mcp" / "qdrant" / "fixtures" / "search.json")
            fixture["source"] = "fixture"
            return ({"ok": True, "data": fixture}, {"allowed": True, "reason": "fixture"}, 200)

        if os.environ.get("QDRANT_LIVE") != "1":
            return ({"ok": False, "error": "live_disabled"}, {"allowed": False, "reason": "live_disabled"}, 403)

        qdrant_base = self.allowlist.get("base_url")
        collection = "kb_platform" if tenant == "platform" else f"kb_tenant_{tenant}"
        payload = {
            "vector": vector,
            "limit": top_k,
            "with_payload": True,
        }
        source_type = params.get("source_type")
        if source_type:
            payload["filter"] = {"must": [{"key": "source_type", "match": {"value": source_type}}]}

        req = Request(
            f"{qdrant_base}/collections/{collection}/points/search",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read().decode("utf-8"))
        return ({"ok": True, "data": result}, {"allowed": True, "reason": "live"}, 200)


if __name__ == "__main__":
    port = int(os.environ.get("MCP_PORT", "8781"))
    server = MCPServer(("127.0.0.1", port), MCPHandler)
    print(f"MCP {server.mcp_kind} listening on 127.0.0.1:{port}")
    server.serve_forever()
