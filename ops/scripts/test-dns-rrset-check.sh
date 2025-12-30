#!/usr/bin/env bash
set -euo pipefail

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

tmp="$(mktemp -d)"
cleanup() { rm -rf "${tmp}" 2>/dev/null || true; }
trap cleanup EXIT

zone="infra.samakia.net"

zone_dump="${tmp}/zone.txt"
cat >"${zone_dump}" <<'TXT'
$ORIGIN .
dns-auth-1.infra.samakia.net	60	IN	A	10.10.100.21
dns-auth-2.infra.samakia.net	60	IN	A	10.10.100.22
dns-edge-1.infra.samakia.net	60	IN	A	10.10.100.11
dns-edge-2.infra.samakia.net	60	IN	A	10.10.100.12
dns.infra.samakia.net	60	IN	A	192.168.11.100
infra.samakia.net	60	IN	NS	dns-auth-1.infra.samakia.net.
infra.samakia.net	60	IN	NS	dns-auth-2.infra.samakia.net.
infra.samakia.net	3600	IN	SOA	a.misconfigured.dns.server.invalid hostmaster.infra.samakia.net 0 10800 3600 604800 3600
TXT

rrset_check() {
  local name="$1"
  local rtype="$2"
  local ttl="$3"
  local json_values="$4"
  python3 -c '
import json
import sys

zone = sys.argv[1].rstrip(".")
name = sys.argv[2].rstrip(".")
rtype = sys.argv[3]
ttl = str(sys.argv[4])
values = [str(v).rstrip(".") for v in json.loads(sys.argv[5])]

present = set()
for raw in sys.stdin.read().splitlines():
  line = raw.strip()
  if not line or line.startswith(";"):
    continue
  parts = line.split()
  if len(parts) < 5:
    continue
  rec_name, rec_ttl, rec_class, rec_type, rec_value = parts[0].rstrip("."), parts[1], parts[2], parts[3], parts[4].rstrip(".")
  if rec_type != rtype:
    continue

  if name == "@":
    if rec_name not in ("@", zone):
      continue
  else:
    if rec_name != name and rec_name != f"{name}.{zone}":
      continue

  present.add((rec_ttl, rec_value))

missing = [v for v in values if (ttl, v) not in present]
if missing:
  sys.exit(1)
sys.exit(0)
' "${zone}" "${name}" "${rtype}" "${ttl}" "${json_values}" <"${zone_dump}"
}

rrset_check "dns-edge-1" "A" "60" '["10.10.100.11"]' || fail "expected dns-edge-1 A to be present"
pass "rrset check matches FQDN ownernames for A records"

rrset_check "@" "NS" "60" '["dns-auth-1.infra.samakia.net.","dns-auth-2.infra.samakia.net."]' || fail "expected @ NS to be present"
pass "rrset check matches zone apex for NS records"

if rrset_check "dns-edge-1" "A" "60" '["10.10.100.99"]'; then
  fail "expected missing value to fail"
fi
pass "rrset check fails when value missing"
