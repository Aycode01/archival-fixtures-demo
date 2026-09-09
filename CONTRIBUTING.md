# Contributing to archival-fixtures-demo

Thanks for helping. This repo is the fixtures/demo side of the
`soroban-state-sentinel` suite: it provides a real, decaying testnet
contract plus the scripts and CI that make Soroban state archival
observable end-to-end. Keep that purpose in mind — everything here is a
demonstration of real network behavior, not a mock.

## The TESTNET-ONLY posture (read first)

Every script and workflow in this repo operates on **Stellar testnet** with
a **TESTNET-ONLY throwaway key** (`.deploy/testnet-throwaway.secret`, mode
600, funded with testnet lumens). The guardrail is enforced in
`scripts/lib.sh` (`require_testnet_env` / `require_testnet_key`) and
refused loudly. Never:

- put a mainnet key in `TESTNET_THROWAWAY_SECRET_KEY` or the repo secrets,
- point `SOROBAN_RPC_URL` (or the workflows' hard-coded RPC URL) at mainnet,
- commit anything under `.deploy/` — it contains a secret key and is
  gitignored.

## Setting up

```bash
# contract tests (needs Rust + wasm32 target)
rustup target add wasm32v1-none
cargo test --manifest-path contracts/rapid-expiry-demo/Cargo.toml

# tooling the scripts need
#   bash >= 4, curl, jq, the stellar CLI, and soroban-state-sentinel on PATH
./scripts/deploy-and-shrink-ttl.sh      # deploy + initialize + starting scan
./scripts/trigger-eviction-wait.sh --check
```

The full end-to-end walkthrough is in the README; the timeline math and
health bands are documented in `docs/`.

## Making changes

- **One commit per logical unit**, conventional commit format
  (`feat:`, `fix:`, `ci:`, `docs:`, `chore:`, `refactor:`), message
  explaining the *why*.
- **Never `git add .`** — stage exactly the files that belong to the
  change.
- Push immediately after each commit (`git push origin main`).
- Do not fabricate demo output: if a doc or PR description shows scan
  output, a TTL value, or a cost, it must come from an actual run against
  actual testnet state (the ledger parameters are readable via
  `getLedgerEntries` — see `docs/surviving-soroban-state-archival.md`).
- If the network parameters changed (they can, with a protocol upgrade),
  update `MIN_PERSISTENT_TTL_LEDGERS` / `MIN_TEMP_TTL_LEDGERS` /
  `MAX_ENTRY_TTL_LEDGERS` in the contract, the `LEDGER_SECONDS` and TTL
  defaults in `scripts/lib.sh`, and the timeline tables in the README and
  docs — in the same commit, since they must stay in lockstep.

## Scripts and the sentinel contract

`scripts/lib.sh` shells out to `soroban-state-sentinel` and parses its JSON
output. That output is a **locked contract** (the sentinel's `SCHEMA.md`);
if you change which fields the scripts read, confirm the field names
against the sentinel's schema first, and test the `jq` expressions against
a schema-accurate fixture (the repo's tests do this for the contract; for
scripts, a one-off `bash -n` + a fake `SENTINEL_BIN` that echoes a
schema-shaped JSON works).

## CI workflows

- `.github/workflows/demo-scan.yml` — scheduled read-only scan, self-contained.
- `.github/workflows/demo-restore.yml` — manual restore, self-contained.

Both need the `CONTRACT_ID` repository variable and the
`TESTNET_THROWAWAY_SECRET_KEY` secret (see the workflow headers). Changes to
workflow behavior should keep them self-contained: they must not require
the sentinel binary, because CI builds neither this repo's contract nor the
sentinel.

## Reviewing

Prefer small, reviewable commits. When in doubt, ask in the PR — the
network-parameter constants and the TESTNET-ONLY guardrails are the two
things reviewers should scrutinize hardest.