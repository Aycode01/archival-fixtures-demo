# Contract reference

`contracts/rapid-expiry-demo` is a deliberately short-lived Soroban
contract: one persistent entry, created at the network-minimum TTL and never
extended, so it inevitably archives.

## Functions

| Function | Args | What it does | Returns |
|---|---|---|---|
| `initialize` | — | Writes the `VALUE` entry (value 1) at the network-minimum TTL. Panics if the entry already exists — deploy scripts treat the panic as "already initialized". | `u32` (1) |
| `read` | — | Returns the stored value. A read does **not** extend the TTL. | `u32` |
| `touch` | — | Overwrites with `value + 1` and returns the new value. Writing also does **not** extend the TTL — this is exactly how entries archive while users keep transacting. | `u32` |
| `extend` | `ledgers: u32` | `extend_ttl(key, ledgers, ledgers)` — "ensure the TTL is at least `ledgers`". No-op while the TTL is already above the threshold. | — (nothing) |

## Parameters

Hard-coded documentation constants, read from the live testnet ledger via
`getLedgerEntries` on 2026-09-09 (protocol 28):

| Constant | Value | Meaning |
|---|---|---|
| `MIN_PERSISTENT_TTL_LEDGERS` | 120,960 | network minimum for persistent entries ≈ 7 days |
| `MIN_TEMP_TTL_LEDGERS` | 720 | temporary-entry minimum ≈ 1 hour (reference only — this contract uses persistent storage) |
| `MAX_ENTRY_TTL_LEDGERS` | 3,110,400 | extension ceiling ≈ 180 days |

These are *documentation* constants for humans and scripts — the network
enforces the minimum, the contract does not.

## What triggers what

| Action | Contract function | Effect on TTL |
|---|---|---|
| deploy script | `initialize` | entry created at 120,959 ledgers, then left to decay |
| demo activity | `read` / `touch` | no change — activity without TTL maintenance |
| remediation | `extend` | raises TTL toward `current_ledger + extend_to`, capped at `maxEntryTTL` |
| after archival | (none — contract cannot help) | entry gone; `RestoreFootprintOp` needed from outside |

## Why there is no `ttl()`

The protocol deliberately gives contracts **no way to read an entry's own
TTL** (CAP-0046-12: "there is no way for smart contracts to determine the
current TTL of an entry"; the soroban-sdk 27 `get_ttl` helpers exist only
behind the `testutils` feature, for tests). TTL monitoring is therefore an
**off-chain** job: `soroban-state-sentinel scan` and the repo's CI read the
TTL ledger entry via `getLedgerEntries` (`scripts/read-entry-ttl.py`)
without invoking the contract. That is the production pattern this demo
teaches — if a contract needs to know its TTL, watch it from outside
instead of fighting the protocol design.

## Storage

One persistent entry, key `Symbol "VALUE"` (SCVal
`AAAADwAAAAVWQUxVRQAAAA==`, XDR 4-byte padded). The contract data key is a
`LedgerKey::ContractData` with durability `persistent`.

## Tests

`cargo test` — 5/5 passing, configured with the real testnet network
parameters. The tests exercise creation at the minimum TTL, reads and
writes that don't extend, explicit extension, and the TTL=0 boundary the
test ledger models at the expiry ledger. Run in CI by
`test-contract.yml`.