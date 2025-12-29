#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${ENV:-samakia-prod}"

echo "== Phase 1 acceptance (static checks) =="
bash fabric-ci/scripts/lint.sh
bash fabric-ci/scripts/validate.sh

echo
echo "== Phase 1 acceptance (guardrails) =="
bash ops/scripts/env-parity-check.sh
bash ops/scripts/runner-env-check.sh

echo
echo "== Phase 1 acceptance (inventory) =="
ENV="${ENV_NAME}" make inventory.check

echo
echo "== Phase 1 acceptance (terraform plan; non-interactive) =="
ENV="${ENV_NAME}" make tf.plan CI=1

echo
echo "OK: Phase 1 acceptance passed"
