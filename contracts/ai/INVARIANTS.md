# AI Invariants (Authoritative)

This document is normative. The AI system in Samakia Fabric MUST comply with the
invariants below. Any deviation is a security regression.

## Invariants

- AI is analysis-only.
- AI has zero execution authority.
- AI may only access data via:
  - read-only MCP services
  - read-only Qdrant retrieval
- AI cannot:
  - run shell commands
  - mutate state
  - apply infrastructure changes
  - approve proposals
  - bypass policies
  - perform remediation or rollback
- AI provider is Ollama only.
- Model routing is fixed unless a new Phase (>= 17) explicitly changes it.

## Change Control

Any expansion of AI capabilities requires:
- a new Phase (>= 17) declared in `ROADMAP.md`
- a dedicated ADR in `DECISIONS.md`
- an acceptance plan under `acceptance/`
