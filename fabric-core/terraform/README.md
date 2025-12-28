# Terraform (Fabric Core)

This directory hosts Terraform modules and executable environments.

## Structure

- `modules/`: reusable, environment-agnostic modules
- `envs/`: executable environments with provider config and state
- `providers/`: shared provider definitions

## Rules

- Run Terraform only from `envs/*`
- Keep modules free of environment-specific data
- Use explicit inputs and outputs
