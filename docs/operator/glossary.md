# Operator Glossary

- **Acceptance**: A deterministic, non-interactive validation run that emits evidence.
- **Evidence packet**: A secrets-safe report + metadata + manifest, stored under gitignored paths.
- **Guard**: Explicit env var or policy condition required to allow mutation.
- **Operator-visible target**: A Make target intended for human or AI operators.
- **VIP**: Virtual IP; service endpoints are VIP-only by policy.
- **Read-only**: No infrastructure mutation (no apply, no config changes).
