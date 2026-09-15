# Wave Submission Drafts

> These are working drafts for the grant/Wave submission form.
> Items marked `<pending: issue #2>` must be filled in once the
> Critical/Archived/restore transcripts land (expected ~Sep 15–16).
> Do not use estimated figures in the final submission.

---

## Repo Relationship Description

This submission covers two primary tool repos: **`soroban-state-sentinel`**
([`Aycode01/soroban-state-sentinel`](https://github.com/Aycode01/soroban-state-sentinel))
and **`action-state-watch`**
([`Aycode01/action-state-watch`](https://github.com/Aycode01/action-state-watch)).

`soroban-state-sentinel` is the core CLI: it connects to a Soroban RPC endpoint,
reads the TTL of every ledger entry associated with a deployed contract, classifies
each into health bands (Healthy / ExpiringSoon / Critical / Archived), computes exact
stroop costs for remediation using the canonical `soroban-env-host` fee model, and
produces unsigned `ExtendFootprintTTLOp` / `RestoreFootprintOp` XDR — never holding
a private key or submitting transactions itself.

`action-state-watch` wraps `soroban-state-sentinel` as a GitHub Action: it runs on a
cron schedule, reads a `contracts.yml` manifest, calls the sentinel for each listed
contract, and routes alerts to Slack, Discord, or GitHub Issues depending on health
band — deduplicating issues and auto-closing them when a contract recovers.

**`archival-fixtures-demo`**
([`Aycode01/archival-fixtures-demo`](https://github.com/Aycode01/archival-fixtures-demo))
is supporting demonstration infrastructure, not a third tool submission. It provides
a real, live, decaying testnet contract — exactly one persistent entry (`VALUE`,
contract `CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4`) — together
with CI workflows and scripts that make the full Soroban state-archival lifecycle
(Healthy → Critical → Archived → Restore) observable end-to-end against the actual
testnet network, not a simulation. Its role is to prove that both tool repos work
against real, decaying state.

Whether `archival-fixtures-demo` qualifies as a separately eligible demo/fixture
repo under this Wave's current rules should be confirmed directly with the program at
actual submission time. Do not assume either way based on this draft.

---

## Project Description

**Problem.** Production Soroban contracts can silently lose access to their
persistent data: every ledger entry has a time-to-live (TTL), `extend_ttl` only
raises it — never lowers it — and ordinary writes do *not* extend it, so a contract
whose users keep transacting can reach TTL = 0 while all metrics look normal. Reads
and writes then revert until a `RestoreFootprintOp` brings the entry back. This is
not theoretical: the need for systematic TTL monitoring surfaced concretely in the
`wraith-protocol` repository, where a contributor was manually tracking WASM and TTL
budgets by hand in issues because no automated tooling existed to watch deployed
contract state.

**Mechanism.** `soroban-state-sentinel` solves this with three integrated
capabilities: (1) RPC-based TTL scanning via `getLedgerEntries` — the only correct
off-chain read path, since the protocol deliberately gives contracts no access to
their own TTL (CAP-0046-12); (2) exact stroop cost computation for both
`ExtendFootprintTTLOp` and `RestoreFootprintOp`, ported from the canonical
`soroban-env-host` fee model with source citations; and (3) an unsigned XDR builder
that batches remediation transactions to the live network's per-transaction footprint
limits, producing output a human, multisig, or separately-secured keeper process can
sign and submit — the tool itself never holds a key. `action-state-watch` wraps this
into a scheduled GitHub Action that monitors a `contracts.yml` manifest, routes
severity-graded alerts to Slack/Discord/GitHub Issues, deduplicates notifications per
contract, and uploads unsigned restore XDR as workflow artifacts. The full archival
lifecycle — deploy at minimum TTL, decay to Critical, archive, restore — is
demonstrated against a real, live testnet contract in `archival-fixtures-demo`, with
transcripts captured from actual RPC responses rather than synthesised output.

**Technical foundation.** Rust (stable, edition 2021), `soroban-sdk` 27,
`stellar-xdr`, GitHub Actions, testnet RPC (`getLedgerEntries`, `getLatestLedger`,
`getNetworkConfig`). Contract unit tests are configured with real testnet network
parameters (protocol 28, `minPersistentTTL` 120,960 ledgers, verified
2026-09-09). The sentinel's JSON output schema is versioned (`schema_version:
"1.0.0"`) and documented in `SCHEMA.md` for downstream consumers.

**Current status.** Both tool repos are published, building, and tested. The live
demo contract is deployed and decaying on testnet. The full archival lifecycle — 
deploy at minimum TTL, decay to Critical, and restore/extend — has been successfully 
run against the live testnet. The end-to-end `Healthy` → `Critical` → `Healthy` 
remediation transcripts are captured and verified against real RPC responses 
(no synthesized data).

---

*Last updated: 2026-09-15. Pending items: none.*
