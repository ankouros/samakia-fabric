# Internal Postgres (Patroni) Acceptance

Timestamp (UTC): 2026-01-04T02:23:09Z

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- ENV=samakia-shared make postgres.internal.plan
- ENV=samakia-shared make postgres.internal.apply
- ENV=samakia-shared make postgres.internal.accept
- BIND_SECRETS_BACKEND=vault VERIFY_LIVE=1 make exposure.verify ENV=samakia-dev TENANT=canary WORKLOAD=sample

Result: PASS

Evidence:
- /home/aggelos/samakia-fabric/evidence/exposure-verify/canary/sample/2026-01-04T02:13:42Z/manifest.sha256
- /home/aggelos/samakia-fabric/evidence/exposure-verify/canary/sample/2026-01-04T02:13:42Z/verify.json

Statement:
Internal shared Postgres HA (Patroni + HAProxy/VIP) is live with proxy-first DNS and Vault-backed canary verification.

Self-hash (sha256 of content above): 89b62bbf2597c8d3b4c3927488bea59dfca39756d95388c5b3981c2bc143bf96
