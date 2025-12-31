# VM image fixtures (local only)

Phase 8 Part 1 acceptance can optionally validate a local qcow2 artifact.

Place a local qcow2 file outside the repo and provide its path via:

```
QCOW2_FIXTURE_PATH=/path/to/image.qcow2 make phase8.part1.accept
```

Notes:
- Fixtures are **not** committed.
- CI runs are validate-only and do not require a fixture.
