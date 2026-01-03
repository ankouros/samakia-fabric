# Documentation

This directory contains Samakia Fabric documentation.

## Structure

- `concepts/`: design and architecture concepts
- `tutorials/`: step-by-step guides
- `tutorials/README.md`: tutorial index and required order
- `operator/`: canonical operator UX and cookbook
- `consumers/`: consumer catalog and variants
- `platform/`: platform manifest and executive invariants
- `tenants/`: tenant (project) binding design
- `bindings/`: tenant binding contracts + connection manifests
- `secrets/`: secrets backend expectations and defaults
- `exposure/`: exposure semantics, rollback, change windows
- `runtime/`: runtime signal taxonomy, incident lifecycle, and SLO design
- `network/`: IP/VIP allocation contracts and networking governance
- `selfservice/`: self-service proposal lifecycle and governance design
- `ai/`: AI analysis contracts, routing, and governance
- `observability/`: shared observability policy and enforcement
- `glossary.md`: canonical terminology
- `PRINCIPLES.md`: non-negotiable principles

## Usage

- Start with `../ARCHITECTURE.md` and `../DECISIONS.md`
- Review `../CONTRACTS.md` and `../SECURITY.md` for non-negotiables
- Follow tutorials in order for first-time setup (`tutorials/README.md`)

## Status

Documentation is a first-class artifact. Update docs with every behavioral change.
