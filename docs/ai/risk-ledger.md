# AI Risk Ledger

The AI risk ledger records how AI analysis is used over time.
It is **descriptive**, not punitive, and does not trigger automation.

## What the ledger records

- Analysis types executed and frequency
- Incident correlations (if any)
- Near-miss cases (analysis rejected by operator)
- False positives and false negatives

## What the ledger does NOT do

- No automatic enforcement
- No operator scoring
- No automated remediation

## Ledger storage

Evidence entries are stored under:
`evidence/ai/risk-ledger/`

Each entry should include:
- timestamp (UTC)
- analysis_type
- evidence refs
- operator outcome (accepted/rejected)
- notes
