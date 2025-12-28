# Samakia Fabric – Style Guide

This document defines **coding, structure, and naming conventions**
for all parts of the Samakia Fabric repository.

Its purpose is to:
- Maintain long-term clarity
- Prevent configuration entropy
- Enable predictable automation
- Make the codebase safe for humans and AI agents

This guide is **mandatory**.

---

## General Principles

Across all languages and tools:
- Prefer clarity over cleverness
- Prefer explicitness over implicit defaults
- Prefer determinism over flexibility
- Prefer boring solutions that work

If something is ambiguous, it is wrong.

---

## Repository Structure Style

### Directory Naming

- Lowercase
- Hyphen-separated
- Descriptive, not abbreviated

Good:

```text
fabric-core/terraform/modules/lxc-container
```

Bad:

```text
tf/mods/lxcCnt
```

### File Naming

- Lowercase
- Hyphen-separated where applicable
- Tool-conventional names respected

Examples:

```text
main.tf
variables.tf
outputs.tf
packer.pkr.hcl
bootstrap.yml
```

---

## Terraform Style Guide

### File Layout (Mandatory)

Each module MUST have:

```text
main.tf
variables.tf
outputs.tf
```

Optional:
- `README.md`

### Formatting

Always run:

```bash
terraform fmt -recursive
```

Formatting-only changes should be kept in their own commit when possible.

### Resource Structure

Terraform resources must be structured in this order:
1. Identity and placement
2. Template or source
3. Runtime behavior
4. Compute resources
5. Storage
6. Networking
7. Access and metadata
8. Lifecycle guards

Example sections should be clearly separated with comments.

### Variables

All inputs must be variables:
- No magic values
- No implicit defaults for critical fields

Variable rules:
- Use `snake_case`
- Include a description
- Use strong typing

### Providers

- Providers are declared once per environment
- Modules must not re-declare providers unless necessary
- Provider source must be explicit (e.g. `Telmate/proxmox`)

### Comments

Use comments to explain **why**, not **what**.

Good:

```hcl
# Proxmox 9 API forbids modifying this after creation
```

Bad:

```hcl
# This sets memory
memory = 2048
```

---

## Packer Style Guide

### Image Philosophy

Golden images must:
- Be minimal
- Be generic
- Be reusable across environments

No environment-specific logic is allowed.

### Provisioning Scripts

Provisioning scripts:
- Must be idempotent
- Must fail fast (`set -euo pipefail`)
- Must not create users
- Must not inject SSH keys

Scripts must be readable and commented by section.

### Artifact Naming

Artifacts must be:
- Versioned
- Explicit

Example:

```text
ubuntu-24.04-lxc-rootfs-v2.tar.gz
```

Never overwrite previous versions.

---

## Ansible Style Guide

### Playbooks

- YAML only
- No inline shell unless unavoidable
- Use `become: true` explicitly

Playbooks must declare:

```yaml
hosts:
gather_facts:
become:
```

### Roles

Reusable logic must live in roles. Roles must be:
- Small
- Focused
- Idempotent

### Variables

- Use `snake_case`
- No hardcoded secrets
- Prefer defaults with overrides

### Inventory

Inventory should be generated. Static inventory files are discouraged.
Terraform is the source of truth for hosts.

---

## Bash and Shell Scripts

Shell scripts must:
- Use `#!/usr/bin/env bash`
- Enable strict mode

```bash
set -euo pipefail
```

Avoid:
- Complex one-liners
- Silent failures

---

## Documentation Style

### Tone

- Clear
- Neutral
- Operational

Avoid:
- Marketing language
- Jokes
- Ambiguity

### Structure

Documents should follow:
- Clear headings
- Logical flow
- Explicit rules

If something is a rule, state it as a rule.

### Terraform Provider Policy

- All Terraform roots and modules MUST declare `required_providers`
- Implicit providers are forbidden
- `hashicorp/proxmox` MUST NOT be used
- Only `telmate/proxmox` is allowed
- Provider versions MUST be pinned

Violations will be blocked by pre-commit and CI.



---

## Naming Conventions

### Resources

- Descriptive
- Purpose-oriented

Examples:

```text
monitoring_1
gateway_internal
storage_backup
```

Avoid:

```text
test1
foo
temp
```

### Tags

- Lowercase
- Hyphen-separated
- Meaningful

Example:

```text
fabric, monitoring, prod
```

---

## Error Handling Philosophy

- Fail fast
- Fail loud
- Never mask errors

If an error is expected, it must be handled explicitly.

---

## Anti-Patterns (Do Not Do)

- Mixing responsibilities across layers
- Hardcoding infrastructure assumptions
- Editing generated files manually
- Silent defaults
- “Quick fixes” without documentation

---

## Consistency Over Time

Consistency is more important than personal preference.

If the codebase already follows a pattern:
- Continue the pattern
- Do not introduce alternatives casually

---

## Enforcement

This style guide applies to:
- Humans
- AI agents
- Automation

Violations may result in:
- Rejected contributions
- Required refactors
- Rollbacks

---

## Final Note

Style is not about aesthetics.

In Samakia Fabric, style is about:
- Safety
- Predictability
- Longevity

If a change makes the system harder to reason about, it is wrong.
