# Introduction

`archival-fixtures-demo` is a fixture suite: a real Soroban contract
deployed on Stellar **testnet**, deliberately set to decay and archive, plus
the scripts and CI workflows that make the decay observable end to end.

## What this repo demonstrates

Soroban persistent ledger entries have a time-to-live (TTL). When it hits
zero, the entry is archived: reads and writes fail until someone submits a
`RestoreFootprintOp`. The failure is easy to miss — activity looks normal
right up until a transaction reverts — and production contracts can silently
lose access to persistent data when nobody watches the TTL.

This repo builds the smallest contract that will inevitably archive, and
pairs it with the tooling to watch the decay, get alerted, and remediate:

- one persistent entry, created at the network-minimum TTL and never extended
- a sentinel-based watcher that classifies the entry into health bands
- scheduled CI that goes red when the entry is at risk
- a manual restore workflow (`RestoreFootprintOp`)

## Why it exists

The sibling repos
[`soroban-state-sentinel`](https://github.com/Aycode01/soroban-state-sentinel)
and `action-state-watch` scan and remediate contract state. They need a real,
live, decaying testnet entry to test against — not a synthetic mock. This
repo provides it, with real transcripts of every step.

## TESTNET ONLY

Everything in this repo signs, funds, and deploys with TESTNET-ONLY
throwaway keys and talks to the testnet RPC. Never set a mainnet key or
point `SOROBAN_RPC_URL` at mainnet. `scripts/lib.sh` enforces this posture
and refuses to run otherwise.

## What's real here

All numbers in these docs come from actual runs against testnet state:

- Network parameters (TTL minimums, rent rates) read from the live ledger
  via `getLedgerEntries` on 2026-09-09 — see
  [economics of rent](economics-of-rent.md)
- Deploy + Healthy-band scan transcripts in `.transcripts/`
- The Critical → Archived → restore phases are pending the real-time decay
  (~7 days); those pages say so explicitly rather than inventing output.

## Start here

- [The archival lifecycle](the-archival-lifecycle.md) — how the demo decays
- [Running the demo](running-the-demo/deploy.md) — deploy and watch
- [Contract reference](contract-reference.md) — what the contract does