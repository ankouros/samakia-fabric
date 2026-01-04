# Phase 17 Step 4 Acceptance

Timestamp (UTC): 2026-01-04T04:45:36Z

Commands executed:
- pre-commit run --all-files
- make policy.check
- make exposure.plan ENV=samakia-dev TENANT=canary WORKLOAD=sample
- APPROVER_ID=aggelos EXPOSE_REASON="Phase17 canary exposure test" PLAN_EVIDENCE_REF=/home/aggelos/samakia-fabric/evidence/exposure-plan/canary/sample/2026-01-04T04:30:25Z make exposure.approve ENV=samakia-dev TENANT=canary WORKLOAD=sample
- EXPOSE_EXECUTE=1 EXPOSE_REASON="Phase17 canary exposure test" APPROVER_ID=aggelos APPROVAL_DIR=/home/aggelos/samakia-fabric/evidence/exposure-approve/canary/sample/2026-01-04T04:30:32Z make exposure.apply ENV=samakia-dev TENANT=canary WORKLOAD=sample
- BIND_SECRETS_BACKEND=vault VERIFY_LIVE=1 make exposure.verify ENV=samakia-dev TENANT=canary WORKLOAD=sample
- ROLLBACK_EXECUTE=1 ROLLBACK_REQUESTED_BY=aggelos ROLLBACK_REASON="Phase17 mandatory rollback" make exposure.rollback ENV=samakia-dev TENANT=canary WORKLOAD=sample

Result: PASS

Statement:
Real canary exposure executed, verified, and rolled back; Phase 13 choreography proven under real conditions.

Self-hash (sha256 of content above): c0046e76c3f9b72c1a4032c69b3f2717693f0032cb285effb09bb70aa09a8cb5
