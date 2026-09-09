# The archival lifecycle

A Soroban persistent entry moves through health bands as its TTL decays,
then is restored. This page walks through each stage with the demo's real
observed values.

## The band model

`soroban-state-sentinel` scans a contract off-chain via `getLedgerEntries`
and classifies each entry:

| Band | Meaning |
|---|---|
| `healthy` | plenty of runway |
| `expiring_soon` | between healthy and critical bounds |
| `critical` | the next extension/restore window is at risk |
| `archived` | the entry is gone; reads/writes fail until restored |

The demo scripts scan with `--healthy-days 1 --critical-days 1` — the
sentinel's real defaults (`--healthy-days 30 --critical-days 7`) would flag
a fresh ~7-day entry as Critical immediately. With the demo's thresholds the
`expiring_soon` band collapses away and the full arc is observable.

## The timeline

With testnet parameters as of 2026-09-09 (protocol 28), a new persistent
entry starts at `minPersistentTTL` = **120,960 ledgers ≈ 7 days** at the
~5 s ledger cadence.

| stage | when | entry TTL |
|---|---|---|
| deploy + `initialize()` | ledger L | 120,959 ledgers (~7 days) |
| decays — nobody extends | each ledger | −1 ledger (~5 s each) |
| Critical (demo thresholds) | ≈ L + 103,680 | ≤ 1 day (17,280 ledgers) |
| archived | ≈ L + 120,960 | 0 |

## Healthy — observed

The live deployment (`CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4`)
was scanned at ledger 4,583,777 (2026-09-09):

```
band: healthy
ledgers_remaining: 120,847  (~6d 23h 50m)
size_bytes: 72
```

Real capture: `.transcripts/02-scan-healthy.json` (full `scan --json`
document). The watcher's progress line (`.transcripts/03-wait-check.txt`):

```
[08:27:56Z] ledger 4583777    ttl 120847    (6d 23h 50m) band: Healthy
```

## Critical — pending

The entry flips to Critical at ≤ 17,280 ledgers (~1 day). That is ~6 days
of real-time decay from deployment; the transcript will be appended to
`.transcripts/` when it lands, and this page will show the real capture.

## Archived — pending

At ledger ≈ 4,704,624 the entry archives: `ledgers_remaining` is null and
reads/writes fail until restored. ~7 days of real-time decay from
deployment. Pending the real run — this page will be updated with the real
`band: archived` capture when it happens.

## Restored — pending

The restore path (`RestoreFootprintOp` via `stellar contract restore`)
brings the entry back at the network minimum, then `extend` raises the TTL.
Pending the real run — see [restoring](running-the-demo/restoring.md).

## Why the wait is real

The protocol enforces `minPersistentTTL` at creation and restore, and
`extend_ttl` only ever raises a TTL. There is no way to create a shorter
TTL or speed the decay on testnet — the ~7-day arc is the point: archival
is slow and quiet, and the tooling's job is to make it visible. For fast
script iteration, run against a standalone network where you control ledger
time (see the README's rehearsal note).