# The economics of rent

Persistent state on Soroban costs money: rent, charged per entry per ledger.
This page collects the real numbers, read from the live testnet ledger on
2026-09-09 (protocol 28), and the worked example. It is a condensed version
of `docs/setting-extend-ttl-boundaries.md` and
`docs/surviving-soroban-state-archival.md` — the long reads stay canonical;
this page is a reference.

## The three TTL boundaries

| Parameter | Testnet value (2026-09-09) | Meaning |
|---|---|---|
| `minPersistentTTL` | 120,960 ledgers ≈ 7 days | floor for a new or restored persistent entry — you cannot create a shorter one |
| `minTemporaryTTL` | 720 ledgers ≈ 1 hour | floor for temporary entries (deleted, never archived) |
| `maxEntryTTL` | 3,110,400 ledgers ≈ 180 days | ceiling: an extension cannot pass `current_ledger + maxEntryTTL` |

These live in the ledger under `CONFIG_SETTING` / `STATE_ARCHIVAL` and are
set by validators — they can change with a protocol upgrade. The exact
`getLedgerEntries` recipe to read them is in
`docs/surviving-soroban-state-archival.md`.

## Rent rates (read from the ledger)

| Parameter | Value | Where it lives |
|---|---|---|
| `persistentRentRateDenominator` | 1,215 | `STATE_ARCHIVAL` |
| `tempRentRateDenominator` | 2,430 | `STATE_ARCHIVAL` |
| `rentFee1KBSorobanStateSizeLow` | −17,000 stroops | `CONTRACT_LEDGER_COST_V0` (id 2) |
| `rentFee1KBSorobanStateSizeHigh` | 10,000 stroops | `CONTRACT_LEDGER_COST_V0` |
| `sorobanStateTargetSizeBytes` | 4,000,000,000 (4 GB) | `CONTRACT_LEDGER_COST_V0` |
| `feeWriteLedgerEntry` | 2,500 stroops | `CONTRACT_LEDGER_COST_V0` |

`fee_per_rent_1kb` interpolates linearly between low and high as the live
average Soroban state size grows 0 → 4 GB (it can be negative — rent-
subsidized — while state is small). It changes over time; don't hard-code
it. The sentinel fetches the config settings and reports exact per-entry
`extend_to_healthy_cost_stroops` / `restore_cost_stroops` in `scan --json`.

## The formula

```
rent_fee = fee_per_rent_1kb(size) * entry_size_kb / rent_denominator * ledgers
          + write_fee(TTL entry)
```

## Worked example

Estimate, clearly labeled — run the sentinel for exact stroops. For a
~100-byte persistent entry at the state-size-high plateau
(`fee_per_rent_1kb` = 10,000 stroops, denominator 1,215), extending
518,400 ledgers (30 days) costs roughly:

```
10,000 * (100 + 48 TTL entry) / 1024 / 1,215 * 518,400 ≈ 6,500 stroops ≈ 0.00065 XLM
```

Restoring an archived entry is *more* expensive than extending a live one,
and every read/write fails until the restore lands — the whole argument for
watching the TTL.

## Choosing boundaries

1. Pick the planning horizon first — `extend_to`, e.g. 30 days
   (518,400 ledgers), capped at `maxEntryTTL - 1` (3,110,399 on testnet).
2. Pick the trigger floor second — `threshold`, e.g. 7 days; below it the
   watcher's band goes Critical and a remediation runs.
3. Extensions are conditional and idempotent: running the same extension
   twice never double-charges. A remediation job can run on every schedule
   safely.
4. Decide who pays (contract or users) — the cost is recurring.
5. Extend before Critical. Extending a live entry is cheap; restoring an
   archived one is expensive and the entry is unavailable in between.
6. You cannot shorten a TTL. Extensions are not refundable.

The demo encodes this: the contract's `extend(ledgers)` =
`extend_ttl(key, ledgers, ledgers)` — "ensure the TTL is at least
`ledgers`" — and the pipeline drives it with `--extend-to <ledgers>`.