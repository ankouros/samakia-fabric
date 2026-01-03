# AI Provider Contract

Samakia Fabric uses a single AI provider for analysis:

- Provider: Ollama
- Base URL: `http://192.168.11.30:11434`
- Mode: analysis-only
- External providers: disabled

The authoritative provider configuration lives at:
- `contracts/ai/provider.yml`

Validation:
- `bash ops/ai/validate-config.sh`
- `make policy.check`

This contract is **non-negotiable**. Any deviation must be introduced as a new phase.
