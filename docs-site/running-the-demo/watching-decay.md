# Watching decay

`scripts/trigger-eviction-wait.sh` is a read-only TTL watcher. It never
signs or submits — it polls `soroban-state-sentinel scan` and prints a
progress line per poll, exiting 0 when a target band is reached.

## The watcher

```bash
# one-shot check
./scripts/trigger-eviction-wait.sh --check

# watch until the entry goes Critical, then exit
./scripts/trigger-eviction-wait.sh --until critical

# watch all the way to Archived
./scripts/trigger-eviction-wait.sh --until archived
```

Real one-shot output (`.transcripts/03-wait-check.txt`), ledger 4,583,777,
~1 ledger per 5 s after deploy:

```
[demo] watching entry 'VALUE' on CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4
[demo] timeline note: with current testnet parameters the entry starts at ~120,959 ledgers
[demo] (~7 days) and decays ~1 ledger every 5s. There is no way to force this faster;
[demo] the protocol minimum is enforced at creation and extensions only raise TTL.
[08:27:56Z] ledger 4583777    ttl 120847    (6d 23h 50m) band: Healthy
```

## The bands, with real output

The watcher's band comes straight from the sentinel's `scan --json`. Only
the Healthy band has a real capture so far — the rest land on the real-time
decay schedule and will be appended when they do:

| band | trigger (demo thresholds) | real capture |
|---|---|---|
| `healthy` | TTL > 17,280 ledgers | ✅ `.transcripts/02-scan-healthy.json` — 120,847 ledgers, size 72 B |
| `critical` | TTL ≤ 17,280 ledgers (~1 day) | ⏳ ≈ 6 days after deploy — pending |
| `archived` | TTL 0 | ⏳ ≈ 7 days after deploy — pending |

The Healthy scan's entry object (excerpt):

```json
{
  "id": "key.0",
  "kind": "contract_data",
  "durability": "persistent",
  "band": "healthy",
  "ledgers_remaining": 120847,
  "days_remaining": 6,
  "size_bytes": 72
}
```

The demo scans with `--healthy-days 1 --critical-days 1` so the arc is
observable in a demo window — the sentinel's real defaults are 30 d / 7 d,
which would flag a fresh entry as Critical immediately. The `expiring_soon`
band collapses away under the demo thresholds.

## How the scan reaches the entry

`soroban-state-sentinel scan` uses RPC `getLedgerEntries` — no contract
invocation, no fees. The TTL itself comes from the `liveUntilLedgerSeq`
field on the returned entry (RPC rejects direct `LedgerKey::Ttl` queries).
The same signal powers the scheduled CI, via `scripts/read-entry-ttl.py`
(off-chain by design: contracts cannot read their own TTL).

## What to watch for

The progress line tells you everything: ledger, TTL in ledgers, human time
remaining, and band. When the band flips to `critical`, the entry is within
~1 day of archiving — that is the moment to remediate
([restoring](restoring.md)), or to let it archive and watch the restore
path.