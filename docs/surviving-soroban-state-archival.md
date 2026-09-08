# Surviving Soroban State Archival

*The long read behind `rapid-expiry-demo`: how Soroban storage expiry works,
why your data can disappear while your users keep transacting, and what to do
about it.*

## The problem: data you can lose without noticing

Soroban contracts store data in two kinds of ledger entries:

- **temporary** entries — scratch data; deleted (not archived) when their TTL
  expires
- **persistent** entries — long-lived contract data; **archived** when their
  TTL expires, and inaccessible until someone pays to restore them

Every entry has a **TTL** (time-to-live) measured in *ledgers*. Each new
ledger decrements it, and when it hits zero the entry is archived (persistent)
or deleted (temporary). What surprises most people:

1. **Writes do not extend the TTL.** Calling a contract that reads and writes
   its own persistent data every block does not keep that data alive. TTL only
   moves when something explicitly extends it (`extend_ttl` /
   `ExtendFootprintTTLOp`) or restores it (`RestoreFootprintOp`).
2. **You cannot create a short-lived entry.** The network enforces
   `minPersistentTTL` when an entry is created *or restored*. There is no way
   to opt into a shorter TTL.
3. **Extensions only go up.** `extend_ttl` raises a TTL (to
   `current_ledger + maxEntryTTL` at most); it can never lower one.

The failure mode is insidious: activity looks normal right up until a read or
write suddenly fails with an archived-entry error, and any data that wasn't
snapshotted off-chain is gone until someone restores it.

## How the numbers work

TTL is expressed relative to the current ledger:

```
ttl = liveUntilLedger - currentLedger
```

Network parameters live in the ledger itself, under the
`CONFIG_SETTING` / `STATE_ARCHIVAL` key, and are set by validators — they can
change with a protocol upgrade, so *verify, don't memorize*. On testnet as of
**2026-09-08 (protocol 28)** they read:

| Parameter | Value | Meaning |
|---|---|---|
| `minPersistentTTL` | 120,960 ledgers | ≈ 7 days at ~5 s/ledger; a new/restored persistent entry starts here |
| `minTemporaryTTL` | 720 ledgers | ≈ 1 hour; temporary entries start here |
| `maxEntryTTL` | 3,110,400 ledgers | ≈ 180 days; the ceiling for extensions |

The demo contract hard-codes these as documentation constants
(`MIN_PERSISTENT_TTL_LEDGERS`, `MIN_TEMP_TTL_LEDGERS`, `MAX_ENTRY_TTL_LEDGERS`)
and its unit tests configure the test ledger with the real values so tests
exercise production-like numbers.

## The three ways a TTL changes

| Mechanism | When | Effect |
|---|---|---|
| entry creation / restore | contract writes a new persistent entry, or a restore op brings one back | TTL = `minPersistentTTL` (network minimum — cannot be shorter) |
| `extend_ttl` (host fn) / `ExtendFootprintTTLOp` (op) | entry is live and you want it to live longer | raises TTL toward `current_ledger + maxEntryTTL`; only ever up, capped by the max |
| `RestoreFootprintOp` | entry is **archived** | flips it from ARCHIVED back to LIVE at `minPersistentTTL`; requires the archived entry in the transaction's restore list |

The demo contract exposes both remediation paths the scripts can drive:

- `extend(ledgers)` — wraps `env.storage().persistent().extend_ttl(key, ledgers, ledgers)`,
  i.e. "ensure the TTL is at least `ledgers`". Works only while the entry is live.
- After archival, the entry can no longer be read/written until a
  `RestoreFootprintOp` is submitted — driven here by
  `stellar contract restore` (see `scripts/run-full-pipeline.sh`).

## Watching the decay: the sentinel and its bands

`soroban-state-sentinel` scans a contract off-chain via `getLedgerEntries` —
no invocation, no fees — and classifies each entry into a health band:

| Band | Meaning | TTL heuristic used here |
|---|---|---|
| **Healthy** | plenty of runway | TTL above the Critical floor |
| **Critical** | the next extension/restore window is at risk | TTL ≤ ~1 day (17,280 ledgers) |
| **Archived** | the entry is gone; reads/writes fail until restored | TTL ≤ 0 |

Its `scan` output (the schema this repo's scripts consume) looks like:

```json
{
  "status": "Healthy",
  "latestLedger": 1234567,
  "entries": [{ "key": "VALUE", "ttl": 120959, "liveUntilLedger": 1355526 }],
  "scannedAt": "2026-09-08T..."
}
```

`scripts/trigger-eviction-wait.sh` polls that scan on an interval and prints a
progress line per poll; `scripts/run-full-pipeline.sh` automates the whole
cycle.

## The demo, walked through

```
deploy-and-shrink-ttl.sh
        │  writes VALUE at minPersistentTTL (120,959 ledgers)
        ▼
   Healthy ────────────── decays ~1 ledger / ~5 s ──────────────► Critical
                                                                    │
                        run-full-pipeline.sh --wait-for critical ──┤
                                                                    ▼
                                              extend(120,960)  ◄── still live:
                                              TTL back to ~7 days   extend_ttl
        ▲
        │
     Healthy ◄── restore (RestoreFootprintOp) + extend
        ▲
        └── run-full-pipeline.sh --wait-for archived (entry already gone:
            restore brings it back at the minimum, extend is a floor)
```

Commands:

```bash
# deploy + initialize, print starting band
./scripts/deploy-and-shrink-ttl.sh

# watch (progress lines, exit 0 when the band is reached)
./scripts/trigger-eviction-wait.sh --until critical
./scripts/trigger-eviction-wait.sh --until archived

# full lifecycle, remediate before archival (the production-correct path)
./scripts/run-full-pipeline.sh --wait-for critical

# full eviction/restore cycle
./scripts/run-full-pipeline.sh --wait-for archived
```

The whole timeline is real time on testnet (~7 days deploy → archive), which
is the point: archival is slow and quiet, and the tooling's job is to make it
visible. For iterating on the scripts, run against a local standalone network
where you control ledger time and can set a small `minPersistentTTL`
(`SOROBAN_RPC_URL` already accepts localhost/standalone).

## Surviving it in production

1. **Watch.** Scan your contracts' persistent entries on a schedule — the
   sentinel (`scan`) or this repo's `.github/workflows/demo-scan.yml` — and
   alert before entries go Critical.
2. **Extend before it archives.** While the entry is live, raise the TTL with
   `extend_ttl` / `ExtendFootprintTTLOp`. This is the cheap path: no
   restoration required. `run-full-pipeline.sh --wait-for critical` is the
   demo of this path.
3. **Restore after it archives.** If you miss the window, submit a
   `RestoreFootprintOp` (here: `stellar contract restore`) to bring the entry
   back at the minimum TTL, then extend. It costs more (restoring is charged
   per restored entry) and any tooling that reads the entry fails in the
   meantime — which is why step 1 exists.
4. **Budget for it.** TTL maintenance is a real, recurring cost: extensions
   and restores both charge fees, and the entry's rent grows with its size and
   TTL. A production design decides who pays (the contract, or users on their
   way through) instead of discovering the bill when something archives.

## Verifying the network parameters yourself

The constants in this repo were read from the ledger, not guessed:

```bash
# protocol 28+ exposes them under the STATE_ARCHIVAL config setting
stellar contract read \
  --id <CONFIG_SETTING contract id> \
  --key '{"tag":"LedgerKeyContractData",...}' \
  ...
```

or via RPC `getLedgerEntries` on the `CONFIG_SETTING` / `STATE_ARCHIVAL` key —
the exact XDR is in the Soroban protocol docs. If the numbers differ from the
table above, the network parameters changed: update `MIN_PERSISTENT_TTL_LEDGERS`
(and friends) in the contract, the `LEDGER_SECONDS` default in `scripts/lib.sh`,
and the timeline tables in the README and here.