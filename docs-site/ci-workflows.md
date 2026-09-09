# CI workflows

Three workflows live in `.github/workflows/`. All are self-contained — they
need no sentinel binary, only the public stellar CLI (and for `demo-scan`,
not even that).

## demo-scan.yml — scheduled, read-only

| | |
|---|---|
| Triggers | `schedule` every 6 h (`0 */6 * * *`) + `workflow_dispatch` |
| Job name | `scan` |
| What it does | Reads the entry TTL **off-chain** via RPC `getLedgerEntries` (`scripts/read-entry-ttl.py`, stdlib python), classifies the band, prints it, and **fails the run** when the entry is Critical or Archived — so a decaying entry turns the schedule red |
| Key used | none — read-only |

Setup (documented in the workflow header): set the `CONTRACT_ID` repository
variable and the `TESTNET_THROWAWAY_SECRET_KEY` secret, then trigger once
with the "Run workflow" button.

## demo-restore.yml — manual remediation

| | |
|---|---|
| Triggers | `workflow_dispatch` only (with optional `contract_id` / `entry_key` / `extend_to` inputs) |
| Job name | `restore` |
| What it does | Detects the entry state off-chain; if archived, submits a `RestoreFootprintOp` via `stellar contract restore`; invokes the contract's `extend` as a floor; re-reads the TTL and fails if it didn't take |
| Key used | `TESTNET_THROWAWAY_SECRET_KEY` — **TESTNET-ONLY** throwaway key; the workflow refuses to run if the key doesn't look like a testnet `S...` key |

## test-contract.yml — build + test

| | |
|---|---|
| Triggers | `push` + `pull_request` to `main` |
| Job name | `contract-tests` |
| What it does | `cargo test` for the contract (needs Rust + the `wasm32v1-none` target) |

## Branch protection: the explicit rule

`demo-restore`'s job must **never** be a required branch-protection check.
It is schedule/manual-only and never runs on PRs, so requiring it would
deadlock every merge. The correct required checks, if branch protection is
configured, are the jobs that actually run on PRs:

- `contract-tests` (test-contract.yml — runs on push + PR)
- `scan` (demo-scan.yml — **only** if its `pull_request` trigger is added;
  today it is schedule/dispatch-only, so it cannot be required either)

Per GitHub's own documentation, cron triggers are best-effort — `schedule`
does not guarantee sub-minute precision and can drift under load. The demo
uses a 6-hour cadence precisely so drift doesn't matter.