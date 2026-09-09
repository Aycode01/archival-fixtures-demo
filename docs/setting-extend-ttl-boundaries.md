# Setting TTL Extend Boundaries

*How to choose `extend_to` / `threshold` (and the health-band thresholds the
watchers scan with) so your contract's persistent data outlives its users'
activity — and why the boundary values matter.*

## The three numbers the network gives you

Every Soroban entry has a TTL in ledgers. The protocol fixes three
boundaries around it, all read from the ledger (see
[surviving-soroban-state-archival.md](surviving-soroban-state-archival.md)
for the exact `getLedgerEntries` incantation):

| Parameter | Testnet value (protocol 28, verified 2026-09-09) | Meaning |
|---|---|---|
| `minPersistentTTL` | **120,960 ledgers ≈ 7 days** | floor for a new or restored persistent entry — you cannot create a shorter-lived one |
| `minTemporaryTTL` | 720 ledgers ≈ 1 hour | floor for temporary entries (deleted, never archived) |
| `maxEntryTTL` | 3,110,400 ledgers ≈ 180 days | ceiling: an extension cannot take the entry past `current_ledger + maxEntryTTL` |

The demo contract hard-codes these as documentation constants
(`MIN_PERSISTENT_TTL_LEDGERS`, `MIN_TEMP_TTL_LEDGERS`, `MAX_ENTRY_TTL_LEDGERS`)
and the demo scripts default their remediation target to
`MIN_PERSISTENT_TTL_LEDGERS`.

## How an extension is decided

The host function (and the `ExtendFootprintTTLOp` operation) takes two
numbers:

```
extend_ttl(key, threshold, extend_to)
```

- If the entry's **current TTL ≤ threshold**, its TTL is raised to
  **`extend_to`** ledgers from the current ledger (so `extend_to` is a
  duration, not an absolute ledger sequence), and rent is charged for the
  raised portion.
- If the current TTL is already **above** `threshold`, nothing happens and
  nothing is charged — the call is a no-op.
- Extensions only ever *raise* a TTL, are capped at `maxEntryTTL - 1` from
  the current ledger, and are conditional (thread-safe: two racing extends
  both end at the same state).

So `threshold` is your **trigger** and `extend_to` is your **target**:

- `threshold` should sit at your *alerting floor*: the TTL at which you want
  an extension to actually fire. Set it low enough that routine traffic
  never crosses it (so healthy entries never pay), and high enough that an
  operator can react before archival. The demo repo watches with a 1-day
  floor (`--critical-days 1`); a production operator might use 7 days.
- `extend_to` should sit at your *planning horizon*: comfortably above the
  threshold and above your longest expected ops window, and **at or below
  `maxEntryTTL - 1`**. Extending by 30 days (`518,400` ledgers) is a common
  default; extending all the way to the cap is usually wasteful because rent
  is paid up front for the whole extension.

The demo contract exposes this directly as
`extend(ledgers)` = `extend_ttl(key, ledgers, ledgers)` — "ensure the TTL is
at least `ledgers`" — and the pipeline drives it with
`--extend-to <ledgers>`.

## What it costs

Rent is charged per entry, per ledger, and grows with the entry size and the
live Soroban state size (bigger state ⇒ faster eviction ⇒ higher rent):

```
rent_fee = fee_per_rent_1kb(size) * entry_size_kb / rent_denominator * ledgers
          + write_fee(TTL entry)
```

Read from the live testnet ledger (protocol 28, 2026-09-09):

| Parameter | Value | Where it lives |
|---|---|---|
| `persistentRentRateDenominator` | 1,215 | `STATE_ARCHIVAL` config setting |
| `tempRentRateDenominator` | 2,430 | `STATE_ARCHIVAL` config setting |
| `rentFee1KBSorobanStateSizeLow` | −17,000 stroops | `CONTRACT_LEDGER_COST_V0` |
| `rentFee1KBSorobanStateSizeHigh` | 10,000 stroops | `CONTRACT_LEDGER_COST_V0` |
| `sorobanStateTargetSizeBytes` | 4,000,000,000 (4 GB) | `CONTRACT_LEDGER_COST_V0` |
| `feeWriteLedgerEntry` | 2,500 stroops | `CONTRACT_LEDGER_COST_V0` |

`fee_per_rent_1kb` is interpolated linearly between low and high as the
live average Soroban state size grows 0 → 4 GB (it can even be negative —
rent-subsidized — while state is small), and grows past the high plateau
once state exceeds the target. It changes over time, so **do not hard-code
it**: the sentinel fetches the config settings and reports the exact
per-entry `extend_to_healthy_cost_stroops` / `restore_cost_stroops` in
`scan --json`.

Worked example, clearly labeled as an estimate (run the sentinel for exact
stroops): for a ~100-byte persistent entry at the state-size-high plateau
(`fee_per_rent_1kb` = 10,000 stroops, denominator 1,215), extending
518,400 ledgers (30 days) costs roughly

```
10,000 * (100 + 48 TTL entry) / 1024 / 1,215 * 518,400 ≈ 6,500 stroops ≈ 0.00065 XLM
```

per extension. Restoring an archived entry is *more* expensive than
extending a live one and every read/write of the entry fails until the
restore lands — which is the whole argument for watching the TTL instead of
discovering it.

## Choosing boundaries in practice

1. **Pick a planning horizon first** — `extend_to`, e.g. 30 days. It must
   be ≤ `maxEntryTTL - 1` (3,110,399 on testnet); the sentinel validates
   this when it builds `ExtendFootprintTTLOp` XDR.
2. **Pick the trigger floor second** — `threshold`, e.g. 7 days. Below
   that, the watcher's band goes Critical and a remediation runs.
3. **Make extensions idempotent.** Because they're conditional, running the
   same extension twice never double-charges and never overshoots. Your
   remediation job can run on every schedule safely; it just no-ops while
   the TTL is healthy.
4. **Decide who pays.** The contract can extend on behalf of its users
   (absorbing the rent into the contract's own cost), or users can be
   charged as they transact. Either way the cost is recurring and should be
   budgeted for — not discovered when something archives.
5. **Watch, then extend before Critical.** Extending a live entry is cheap;
   restoring an archived one is expensive and the entry is unavailable in
   between. The demo's `run-full-pipeline.sh --wait-for critical` is the
   happy path; `--wait-for archived` shows the restore path.
6. **Don't shorten.** There is no way to reduce a TTL. If you extend to a
   long horizon and later want the entry gone, you still pay the rent
   already committed — extensions are not refundable.

## Where the demo encodes this

| Concern | Location |
|---|---|
| network minimum TTL | `contracts/rapid-expiry-demo/src/lib.rs` (`MIN_PERSISTENT_TTL_LEDGERS`) |
| default remediation target | `scripts/lib.sh` (`MIN_PERSISTENT_TTL_LEDGERS`) |
| watcher thresholds (Critical = ≤ 1 day) | `scripts/lib.sh` (`--healthy-days 1 --critical-days 1`) and `.github/workflows/demo-scan.yml` (17,280-ledger floor) |
| extension mechanics | contract `extend(ledgers)`, driven by `run-full-pipeline.sh --extend-to` |
| restore mechanics | `stellar contract restore` (RestoreFootprintOp) in `run-full-pipeline.sh` and `.github/workflows/demo-restore.yml` |