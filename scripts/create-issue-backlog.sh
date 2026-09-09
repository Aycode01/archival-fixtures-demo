#!/usr/bin/env bash
# create-issue-backlog.sh — generate the planned-issue backlog for this repo.
#
# One issue per backlog item, each with Summary / Acceptance Criteria /
# Tech Stack, via a single gh run. Items are derived from the repo's build
# sequence and the verification findings of the 2026-09-09 completion pass
# (the original brief's "Drips Wave Issue Breakdown" bullets were not
# available verbatim, so the backlog was derived from the repo's actual
# scope instead).
#
# Requires: gh authenticated with write access to issues.
# Usage:     bash scripts/create-issue-backlog.sh
#
# NOTE: branch protection (also part of Phase 10 hygiene) is NOT covered
# here — it is a repo-admin setting and needs an admin token; see issue #6.

set -euo pipefail
REPO="${GITHUB_REPOSITORY:-Aycode01/archival-fixtures-demo}"

mk() {
    gh issue create --repo "$REPO" --title "$1" --body "$2"
}

mk "Capture Critical and Archived pipeline transcripts from the live decay" "$(cat <<'BODY'
## Summary
The deployed demo entry (CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4, testnet, deployed 2026-09-09) is decaying in real time: Healthy now, Critical in ~6 days, Archived in ~7. The repo's rule is that doc output comes from real runs; the Healthy capture is committed under .transcripts/, and the other two bands plus the restore are pending this wait.

## Acceptance Criteria
- Run `./scripts/trigger-eviction-wait.sh --until critical` and capture the sentinel scan JSON showing the Critical band (ledgers_remaining <= 17280).
- Run `./scripts/trigger-eviction-wait.sh --until archived` (or the scheduled CI) and capture the Archived scan JSON (ledgers_remaining null / TTL 0).
- Run `./scripts/run-full-pipeline.sh --wait-for archived` and capture the restore + post-restore verification output.
- Append all captures to `.transcripts/` and replace the pending notes in `docs/surviving-soroban-state-archival.md` and `README.md`.

## Tech Stack
bash, soroban-state-sentinel, stellar-cli, testnet RPC
BODY
)"

mk "Add a standalone-network rehearsal mode for the full pipeline" "$(cat <<'BODY'
## Summary
The honest demo is ~7 days of real time on testnet. For iterating on the scripts and demoing without the wait, support a compressed rehearsal: point SOROBAN_RPC_URL at a local standalone network where ledger time is controllable and minPersistentTTL can be set small, so Healthy -> Critical -> Archived -> restore completes in minutes.

## Acceptance Criteria
- Documented recipe (README or docs) to start a standalone network with a small minPersistentTTL and run the full pipeline against it.
- `run-full-pipeline.sh --wait-for archived` completes end-to-end on the standalone network.
- No changes to testnet behavior; testnet remains the primary, real-time path.

## Tech Stack
stellar-cli (container/standalone), soroban-state-sentinel, bash scripts
BODY
)"

mk "Validate contracts.yml against action-state-watch's self-check schema" "$(cat <<'BODY'
## Summary
contracts.yml is a documented proposal for the fixture manifest action-state-watch's self-check workflow consumes. That repo is not public yet, so the schema has never been validated against the real consumer.

## Acceptance Criteria
- Once action-state-watch is public, confirm the self-check workflow reads contracts.yml (or publish its expected schema).
- Align contracts.yml fields (network, contract_id_env, wasm path, entry key + SCVal XDR, scan thresholds) with the consumer; update docs if anything changes.

## Tech Stack
YAML, GitHub Actions, action-state-watch
BODY
)"

mk "Configure Actions variables/secrets and trigger demo-scan and demo-restore live" "$(cat <<'BODY'
## Summary
Blocked on token permissions: the environment token cannot write Actions secrets/variables or dispatch workflows (HTTP 403). The scheduled demo-scan.yml has already fired twice and failed with "CONTRACT_ID repository variable is not set" — the documented setup requirement. A repo-owner admin run is needed to go green and to exercise the restore path for real.

## Acceptance Criteria
- Set repository variable CONTRACT_ID = the deployed id and secret TESTNET_THROWAWAY_SECRET_KEY = the key in .deploy/testnet-throwaway.secret.
- Trigger demo-scan.yml (workflow_dispatch) and confirm it reports Healthy.
- Trigger demo-restore.yml against an archived entry (after the decay) and confirm the restore + verify path; record the run.

## Tech Stack
GitHub Actions, repo variables/secrets, stellar-cli
BODY
)"

mk "Enable branch protection with the real required checks" "$(cat <<'BODY'
## Summary
Branch protection could not be configured from this environment (HTTP 403 on the protection API). When an admin token is available, protect main with required status checks matching the actual job names: `contract-tests` (test-contract.yml, runs on push + PR) and `scan` (demo-scan.yml — needs a pull_request trigger to appear on PRs; read-only). Do NOT require demo-restore.yml's job: it is schedule/manual-only and never runs on PRs, so a required check would deadlock every merge.

## Acceptance Criteria
- main is protected; PRs must pass contract-tests (and scan if given a PR trigger).
- Merges are not deadlocked by never-running checks; the demo-restore exception is documented.

## Tech Stack
GitHub branch protection API / gh
BODY
)"

mk "Publish soroban-state-sentinel release binaries" "$(cat <<'BODY'
## Summary
soroban-state-sentinel has no prebuilt releases; every consumer (this repo's scripts, action-state-watch) must build it from source with Rust. A tagged release with binaries would remove that step.

## Acceptance Criteria
- A GitHub release with prebuilt binaries for the supported platforms (at least x86_64 linux/macos).
- README install step updated to download the release binary; this repo's PREREQUISITES updated to match.

## Tech Stack
GitHub Actions release workflow, Rust, soroban-state-sentinel
BODY
)"

echo "backlog issues created on $REPO"
