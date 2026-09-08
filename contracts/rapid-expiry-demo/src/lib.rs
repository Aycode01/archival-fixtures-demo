#![no_std]

//! rapid-expiry-demo — a deliberately short-lived Soroban contract.
//!
//! This contract exists to give [`soroban-state-sentinel`](https://github.com/Aycode01/soroban-state-sentinel)
//! and [`action-state-watch`](https://github.com/Aycode01/action-state-watch) a
//! **real**, decaying, archivable testnet entry to watch — not a synthetic mock.
//!
//! It deliberately maintains exactly **one persistent entry** and never extends
//! that entry's TTL, so the entry decays on a predictable timeline until it is
//! archived and must be restored. That is the whole point: production contracts
//! silently lose access to persistent data when nobody watches the TTL, and this
//! contract makes that failure observable end-to-end on testnet.
//!
//! ## Why "short TTL"
//!
//! The shortest TTL an entry can have is the network's `minPersistentTTL`
//! parameter. The protocol enforces this minimum when an entry is created or
//! restored, and `extend_ttl` can only ever *raise* a TTL, never lower it — so
//! there is no way for a contract to create a persistent entry with a shorter
//! TTL than the network allows.
//!
//! On testnet (protocol 28, checked 2026-09-08 via `getLedgerEntries` on the
//! `CONFIG_SETTING` / `STATE_ARCHIVAL` ledger key) that minimum is
//! **120,960 ledgers ≈ 7 days** at the ~5 s ledger cadence. We deliberately
//! write our entry and then never touch its TTL, so the demo timeline is:
//!
//! | stage | when | entry TTL |
//! |---|---|---|
//! | deploy + `initialize()` | ledger L | 120,959 ledgers (~7 days) |
//! | users keep transacting, nobody extends | each ledger | −1 ledger (~5 s each) |
//! | archived | ≈ L + 120,960 | 0 — reads/writes fail until restored |
//!
//! Verify the current network parameters before trusting these numbers — they
//! are set by validators and can change. See `docs/surviving-soroban-state-archival.md`.

use soroban_sdk::{contract, contractimpl, symbol_short, Env, Symbol};

/// Storage key of the single persistent entry this contract maintains.
pub(crate) const VALUE_KEY: Symbol = symbol_short!("VALUE");

/// Testnet `minPersistentTTL` (a network parameter), in ledgers, as of
/// 2026-09-08 (protocol 28). New persistent entries are created at this TTL,
/// and restored entries come back at it too. 120,960 ledgers ≈ 7 days at the
/// ~5 s testnet ledger cadence.
///
/// NOTE: this is a *documentation* constant for humans and scripts — the
/// network enforces the minimum, the contract does not.
pub const MIN_PERSISTENT_TTL_LEDGERS: u32 = 120_960;

/// Testnet `minTemporaryTTL` (a network parameter), in ledgers, as of
/// 2026-09-08. Included for reference only: this contract uses persistent
/// storage (temporary entries are deleted, never archived, so they cannot be
/// restored and do not exercise the restore path this demo exists to prove).
pub const MIN_TEMP_TTL_LEDGERS: u32 = 720;

/// Testnet `maxEntryTTL` (a network parameter), in ledgers, as of 2026-09-08.
/// An entry's TTL can be extended up to `current_ledger + maxEntryTTL`.
pub const MAX_ENTRY_TTL_LEDGERS: u32 = 3_110_400;

#[contract]
pub struct RapidExpiryDemo;

#[contractimpl]
impl RapidExpiryDemo {
    /// Writes the single persistent entry. The entry is created at the
    /// network-minimum TTL (see [`MIN_PERSISTENT_TTL_LEDGERS`]) and then left
    /// to decay — this contract never extends it on its own.
    ///
    /// Panics if the entry already exists, so deploy scripts can treat the
    /// panic as "already initialized" and move on.
    ///
    /// Returns the initial stored value (1).
    pub fn initialize(env: Env) -> u32 {
        if env.storage().persistent().has(&VALUE_KEY) {
            panic!("already initialized");
        }
        let value: u32 = 1;
        env.storage().persistent().set(&VALUE_KEY, &value);
        value
    }

    /// Returns the stored value. A read does **not** extend the TTL.
    pub fn read(env: Env) -> u32 {
        env.storage().persistent().get(&VALUE_KEY).unwrap_or(0)
    }

    /// Overwrites the stored value with `value + 1` and returns the new value.
    ///
    /// Writing also does **not** extend the TTL: in production this is exactly
    /// how entries archive while users keep transacting — activity without TTL
    /// maintenance.
    pub fn touch(env: Env) -> u32 {
        let next = env
            .storage()
            .persistent()
            .get::<_, u32>(&VALUE_KEY)
            .unwrap_or(0)
            .saturating_add(1);
        env.storage().persistent().set(&VALUE_KEY, &next);
        next
    }

    /// Explicitly extends the entry so it lives at least `ledgers` more
    /// ledgers, using the SDK's `extend_ttl(key, threshold, extend_to)`
    /// semantics: if the current TTL is at or below the threshold the TTL is
    /// raised to `extend_to`; otherwise the call is a no-op. Passing the same
    /// value for both means "ensure the TTL is at least `ledgers`".
    ///
    /// Returns the new TTL in ledgers. This is the remediation path that
    /// `soroban-state-sentinel restore` and `action-state-watch` automate
    /// against the *other* side of the pipeline (`ExtendFootprintTTLOp` /
    /// `RestoreFootprintOp`).
    pub fn extend(env: Env, ledgers: u32) -> u32 {
        env.storage()
            .persistent()
            .extend_ttl(&VALUE_KEY, ledgers, ledgers);
        env.storage().persistent().get_ttl(&VALUE_KEY)
    }

    /// Current TTL of the entry, in ledgers, from the current ledger.
    /// Convenience for scripts and health checks; the sentinel reads the same
    /// value off-chain from `getLedgerEntries` without invoking this contract.
    pub fn ttl(env: Env) -> u32 {
        env.storage().persistent().get_ttl(&VALUE_KEY)
    }
}

mod test;