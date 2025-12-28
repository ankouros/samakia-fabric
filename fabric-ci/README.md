# Fabric CI

Continuous integration workflows and validation scripts for Samakia Fabric.

## Scope

- Terraform formatting and validation
- Ansible linting and checks
- Documentation and policy validation

## Status

Scripts are present and can be wired into CI:

- `scripts/lint.sh`: provider pinning + Terraform fmt check
- `scripts/validate.sh`: Terraform init/validate + Ansible syntax checks
- `scripts/smoke-test.sh`: inventory generation smoke test
