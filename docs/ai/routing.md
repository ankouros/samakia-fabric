# AI Routing Policy

Routing is deterministic and defined in `contracts/ai/routing.yml`.

## Defaults
- ops reasoning: `gpt-oss:20b`
- code: `starcoder2:15b`
- embeddings: `nomic-embed-text`

## Task routes
- `ops.analysis` -> `gpt-oss:20b`
- `ops.summary` -> `gpt-oss:20b`
- `ops.incident` -> `gpt-oss:20b`
- `code.review` -> `starcoder2:15b`
- `code.generate` -> `starcoder2:15b`
- `embeddings` -> `nomic-embed-text`

No dynamic routing or external model selection is allowed.
