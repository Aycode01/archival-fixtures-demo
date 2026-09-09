# Restoring

The restore path is the remediation half of the demo: when the entry is
archived, bring it back with a `RestoreFootprintOp`, then extend it to a
healthy TTL. `scripts/run-full-pipeline.sh` automates the whole cycle;
`.github/workflows/demo-restore.yml` is the same path from CI.

## The two remediation paths

| Entry state | Path | Mechanics |
|---|---|---|
| live but Critical | extend | `extend(ledgers)` via contract = `extend_ttl(key, ledgers, ledgers)` — cheap, no restore needed |
| archived | restore + extend | `stellar contract restore` (`RestoreFootprintOp`) brings it back at `minPersistentTTL`; then extend as a floor |

## run-full-pipeline.sh

The full lifecycle in one command:

```bash
# remediate before archival (the production-correct path)
./scripts/run-full-pipeline.sh --wait-for critical

# full eviction/restore cycle
./scripts/run-full-pipeline.sh --wait-for archived
```

The pipeline scans → detects the band → builds the restore XDR (or just
extends, if the entry is still live) → submits with the TESTNET-ONLY
throwaway key → verifies the entry reads again.

## From CI

`.github/workflows/demo-restore.yml` is the manual remediation workflow: run
it from the Actions UI once the scheduled scan goes red. It:

1. Detects the entry's state off-chain via `scripts/read-entry-ttl.py`
   (TTL 0 = archived).
2. If archived: `stellar contract restore --key VALUE --durability
   persistent` — a `RestoreFootprintOp`, submitted with the
   `TESTNET_THROWAWAY_SECRET_KEY` (TESTNET-ONLY throwaway key).
3. Invokes the contract's `extend` as a floor.
4. Re-reads the TTL off-chain and fails the run if it didn't take.

## Real transcript: pending

The restore phase of the live demo has **not happened yet** — the entry is
still decaying (deployed 2026-09-09, Healthy at ~120,900 ledgers; ~7 days
until Archived). Per this repo's rule, doc output comes from real runs, so
this page will be updated with the real restore transcript once the entry
archives and is restored. No placeholder output is shown here.

To run it yourself once the entry archives:

```bash
./scripts/run-full-pipeline.sh --wait-for archived
```

or trigger `demo-restore.yml` from the Actions UI. The expected post-restore
state (from the mechanics, not yet observed): entry live again at
`minPersistentTTL` 120,960 ledgers, then extended to the configured
`extend_to`, and the off-chain read confirms TTL > 0.