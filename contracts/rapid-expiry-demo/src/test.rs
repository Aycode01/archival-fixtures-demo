#![cfg(test)]

//! Unit tests for `rapid-expiry-demo`.
//!
//! Mirrors the pattern from SDF's official `ttl` example
//! ([`soroban-examples/ttl`](https://github.com/stellar/soroban-examples/tree/master/ttl))
//! and the ["Test TTL Extensions"](https://developers.stellar.org/docs/build/guides/archival/test-ttl-extension)
//! guide: we configure the test ledger with the **real testnet network
//! parameters** (checked 2026-09-08, protocol 28) so the tests exercise
//! production-like TTL values, and we assert on `get_ttl` — the recommended
//! way to verify TTL behavior in the SDK.

use crate::{RapidExpiryDemo, RapidExpiryDemoClient, VALUE_KEY, MIN_PERSISTENT_TTL_LEDGERS};
use soroban_sdk::testutils::{storage::Persistent, Ledger};
use soroban_sdk::{Address, Env};

extern crate std;

/// Test environment mirroring current testnet network parameters
/// (protocol 28, checked 2026-09-08 via `getLedgerEntries` on the
/// `CONFIG_SETTING`/`STATE_ARCHIVAL` ledger key).
fn create_env() -> Env {
    let env = Env::default();
    env.ledger().with_mut(|li| {
        li.sequence_number = 100_000;
        li.min_persistent_entry_ttl = MIN_PERSISTENT_TTL_LEDGERS;
        li.min_temp_entry_ttl = 720;
        li.max_entry_ttl = 3_110_400;
    });
    env
}

/// Freshly registered, initialized contract plus its address and client.
fn setup() -> (Env, Address, RapidExpiryDemoClient) {
    let env = create_env();
    let contract_id = env.register(RapidExpiryDemo, ());
    let client = RapidExpiryDemoClient::new(&env, &contract_id);
    client.initialize();
    (env, contract_id, client)
}

#[test]
fn entry_starts_at_the_network_minimum_ttl() {
    let (env, contract_id, client) = setup();
    assert_eq!(client.read(), 1);

    // A new persistent entry is created at `minPersistentTTL`; the current
    // ledger counts towards that number, so `get_ttl` reports one less.
    assert_eq!(client.ttl(), MIN_PERSISTENT_TTL_LEDGERS - 1);

    // Same answer when reading the entry directly from host storage.
    env.as_contract(&contract_id, || {
        assert_eq!(
            env.storage().persistent().get_ttl(&VALUE_KEY),
            MIN_PERSISTENT_TTL_LEDGERS - 1
        );
    });
}

#[test]
fn writes_do_not_extend_the_ttl() {
    let (env, _contract_id, client) = setup();
    let ttl_before = client.ttl();

    // Ten minutes of testnet traffic (~120 ledgers at 5s each).
    env.ledger().with_mut(|li| li.sequence_number += 120);

    // A write is not a TTL extension: the TTL keeps decaying.
    assert_eq!(client.touch(), 2);
    assert_eq!(client.read(), 2);
    assert_eq!(client.ttl(), ttl_before - 120);
}

#[test]
fn extend_raises_the_ttl_to_the_requested_value() {
    let (env, _contract_id, client) = setup();

    // Let the entry decay well below the extension target first. With the
    // real testnet minimum (120,960) we simulate ~7 days of decay.
    env.ledger().with_mut(|li| li.sequence_number += 120_000);

    // extend(5000): threshold = extend_to = 5000, so the TTL is raised to
    // 5000 ledgers.
    assert_eq!(client.extend(5_000), 5_000);
    assert_eq!(client.ttl(), 5_000);

    // Extending to a smaller value than the current TTL is a no-op
    // (extend_ttl only ever raises the TTL).
    assert_eq!(client.extend(100), 5_000);
    assert_eq!(client.ttl(), 5_000);
}

#[test]
fn entry_ttl_counts_down_to_zero() {
    let (env, _contract_id, client) = setup();
    let ttl_before = client.ttl();

    // Jump the ledger forward until the entry's liveUntilLedger is reached;
    // get_ttl reports 0 (the entry is no longer live — archived for
    // persistent storage, which is what the sentinel will flag).
    env.ledger().with_mut(|li| li.sequence_number += ttl_before);
    assert_eq!(client.ttl(), 0);
}

#[test]
#[should_panic(expected = "already initialized")]
fn initialize_is_single_use() {
    let (_env, _contract_id, client) = setup();
    client.initialize();
}