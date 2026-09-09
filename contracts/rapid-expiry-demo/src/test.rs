#![cfg(test)]

//! Unit tests for `rapid-expiry-demo`.
//!
//! Mirrors the pattern from SDF's official `ttl` example
//! ([`soroban-examples/ttl`](https://github.com/stellar/soroban-examples/tree/master/ttl))
//! and the ["Test TTL Extensions"](https://developers.stellar.org/docs/build/guides/archival/test-ttl-extension)
//! guide: we configure the test ledger with the **real testnet network
//! parameters** (verified 2026-09-09, protocol 28) so the tests exercise
//! production-like TTL values, and we assert on the `testutils` `get_ttl`
//! trait — the SDK's TTL-reading API, which is test-only by design (the
//! protocol gives production contracts no way to read their own TTL, so the
//! contract itself exposes no `ttl()` function; see `lib.rs`).

use crate::{RapidExpiryDemo, RapidExpiryDemoClient, VALUE_KEY, MIN_PERSISTENT_TTL_LEDGERS};
use soroban_sdk::testutils::{storage::Persistent, EnvTestConfig, Ledger};
use soroban_sdk::{Address, Env};

extern crate std;

/// Test environment mirroring current testnet network parameters
/// (protocol 28, verified 2026-09-09 via `getLedgerEntries` on the
/// `CONFIG_SETTING`/`STATE_ARCHIVAL` config setting).
fn create_env() -> Env {
    let mut env = Env::default();
    // Don't write SDK 27's test snapshot JSON files (capture_snapshot_at_drop
    // defaults to true) — this repo's tests assert behavior, not snapshots.
    env.set_config(EnvTestConfig {
        capture_snapshot_at_drop: false,
    });
    env.ledger().with_mut(|li| {
        li.sequence_number = 100_000;
        li.min_persistent_entry_ttl = MIN_PERSISTENT_TTL_LEDGERS;
        li.min_temp_entry_ttl = 720;
        li.max_entry_ttl = 3_110_400;
    });
    env
}

/// Freshly registered, initialized contract plus its address.
///
/// Clients are constructed inside each test: the generated client borrows the
/// `Env`, so it cannot be returned alongside it.
fn setup() -> (Env, Address) {
    let env = create_env();
    let contract_id = env.register(RapidExpiryDemo, ());
    let client = RapidExpiryDemoClient::new(&env, &contract_id);
    client.initialize();
    (env, contract_id)
}

/// TTL of the demo entry via the testutils trait (panics if expired).
fn entry_ttl(env: &Env, contract_id: &Address) -> u32 {
    env.as_contract(contract_id, || {
        env.storage().persistent().get_ttl(&VALUE_KEY)
    })
}

#[test]
fn entry_starts_at_the_network_minimum_ttl() {
    let (env, contract_id) = setup();
    let client = RapidExpiryDemoClient::new(&env, &contract_id);
    assert_eq!(client.read(), 1);

    // A new persistent entry is created at `minPersistentTTL`; the current
    // ledger counts towards that number, so `get_ttl` reports one less.
    assert_eq!(entry_ttl(&env, &contract_id), MIN_PERSISTENT_TTL_LEDGERS - 1);
}

#[test]
fn writes_do_not_extend_the_ttl() {
    let (env, contract_id) = setup();
    let client = RapidExpiryDemoClient::new(&env, &contract_id);
    let ttl_before = entry_ttl(&env, &contract_id);

    // Ten minutes of testnet traffic (~120 ledgers at 5s each).
    env.ledger().with_mut(|li| li.sequence_number += 120);

    // A write is not a TTL extension: the TTL keeps decaying.
    assert_eq!(client.touch(), 2);
    assert_eq!(client.read(), 2);
    assert_eq!(entry_ttl(&env, &contract_id), ttl_before - 120);
}

#[test]
fn extend_raises_the_ttl_to_the_requested_value() {
    let (env, contract_id) = setup();
    let client = RapidExpiryDemoClient::new(&env, &contract_id);

    // Let the entry decay well below the extension target first. With the
    // real testnet minimum (120,960) we simulate ~7 days of decay.
    env.ledger().with_mut(|li| li.sequence_number += 120_000);

    // extend(5000): threshold = extend_to = 5000, so the TTL is raised to
    // 5000 ledgers. The function itself returns nothing; the TTL is read
    // back through the testutils trait (off-chain reads in production).
    client.extend(&5_000);
    assert_eq!(entry_ttl(&env, &contract_id), 5_000);

    // Extending to a smaller value than the current TTL is a no-op
    // (extend_ttl only ever raises the TTL).
    client.extend(&100);
    assert_eq!(entry_ttl(&env, &contract_id), 5_000);
}

#[test]
fn entry_ttl_counts_down_to_zero() {
    let (env, contract_id) = setup();
    let ttl_before = entry_ttl(&env, &contract_id);

    // Jump the ledger forward exactly to the entry's liveUntilLedger: the
    // TTL reads 0 — the moment a persistent entry archives on the real
    // network (reads/writes fail until a RestoreFootprintOp brings it back).
    //
    // NOTE: the SDK test ledger does NOT model archival — one ledger past
    // expiry it silently re-creates the entry at the minimum TTL (a
    // test-ledger artifact; real archived entries stay archived). The true
    // Healthy -> Critical -> Archived arc is exercised end-to-end by the
    // repo's scripts against testnet, where the sentinel reads the TTL
    // off-chain via getLedgerEntries.
    env.ledger().with_mut(|li| li.sequence_number += ttl_before);
    assert_eq!(entry_ttl(&env, &contract_id), 0);
}

#[test]
#[should_panic(expected = "already initialized")]
fn initialize_is_single_use() {
    let (_env, contract_id) = setup();
    let client = RapidExpiryDemoClient::new(&_env, &contract_id);
    client.initialize();
}