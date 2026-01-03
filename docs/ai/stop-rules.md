# AI Stop Rules & Kill Switches

AI analysis must halt immediately if safety is in doubt.

## Stop rules (immediate pause)

- Evidence of hallucinated facts
- Evidence of policy violation
- Attempt to bypass MCP allowlists
- Operator distrust or manual freeze
- Regulatory or audit requirement

## Kill switches

Kill switches are operator-only and reversible with evidence.

### Disable all AI analysis

```bash
export AI_ANALYZE_DISABLE=1
```

### Disable specific analysis types

```bash
export AI_ANALYZE_BLOCK_TYPES="plan_review,change_impact"
```

### Disable specific models

```bash
export AI_ANALYZE_BLOCK_MODELS="gpt-oss:20b"
```

## Reversal

- Remove the environment override
- Document the reason for re-enablement in the risk ledger
