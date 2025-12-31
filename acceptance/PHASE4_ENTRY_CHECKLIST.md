# Phase 4 Entry Checklist

Timestamp (UTC): 2025-12-31T03:03:49Z

## Criteria

1) Phase 0 acceptance marker present
- Command: test -f acceptance/PHASE0_ACCEPTED.md
- Result: PASS

2) Phase 1 acceptance marker present
- Command: test -f acceptance/PHASE1_ACCEPTED.md
- Result: PASS

3) Phase 2 acceptance marker present
- Command: test -f acceptance/PHASE2_ACCEPTED.md
- Result: PASS

4) Phase 2.1 acceptance marker present
- Command: test -f acceptance/PHASE2_1_ACCEPTED.md
- Result: PASS

5) Phase 2.2 acceptance marker present
- Command: test -f acceptance/PHASE2_2_ACCEPTED.md
- Result: PASS

6) Phase 3 Part 1 acceptance marker present
- Command: test -f acceptance/PHASE3_PART1_ACCEPTED.md
- Result: PASS

7) Phase 3 Part 2 acceptance marker present
- Command: test -f acceptance/PHASE3_PART2_ACCEPTED.md
- Result: PASS

8) Phase 3 Part 3 acceptance marker present
- Command: test -f acceptance/PHASE3_PART3_ACCEPTED.md
- Result: PASS

9) REQUIRED-FIXES.md has no OPEN items
- Command: rg -n "OPEN" REQUIRED-FIXES.md
- Result: PASS (no matches)

10) CI workflows present
- Command: test -f .github/workflows/{pr-validate.yml,pr-tf-plan.yml,apply-nonprod.yml,drift-detect.yml,app-compliance.yml,release-readiness.yml}
- Result: PASS

11) CI workflows reference policy/checks
- Command: rg -n <required patterns> .github/workflows
- Result: PASS

12) CI plan matrix includes required envs
- Command: rg -n "samakia-" .github/workflows/pr-tf-plan.yml
- Result: PASS

13) Apply workflow gating (non-prod only + confirm phrase)
- Command: rg -n <allowlist + confirm phrase> .github/workflows/apply-nonprod.yml
- Result: PASS

14) Policy gates pass locally
- Command: make policy.check
- Result: PASS

Notes:
- If any criterion fails, Phase 4 work must stop and remediation must be recorded in REQUIRED-FIXES.md.
