# Platform Manifest

This manifest captures platform-level invariants that operators and auditors can
verify at a glance.

## AI Capability Statement

- AI is analysis-only and has zero execution authority.
- AI does not and cannot act.
- Provider: Ollama only (`http://192.168.11.30:11434`).
- Allowed models:
  - `gpt-oss:20b`
  - `starcoder2:15b`
  - `nomic-embed-text`
- Allowed MCPs (read-only):
  - repo
  - evidence
  - observability
  - runbooks
  - qdrant
- Routing and access are fixed by contract; any change requires a new Phase and
  governance approval.
