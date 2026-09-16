#!/usr/bin/env bash
set -euo pipefail
REPO="${GITHUB_REPOSITORY:-Aycode01/archival-fixtures-demo}"

mk() {
    gh issue create --repo "$REPO" --title "$1" --body "$2"
}

mk "Capture Critical and Archived pipeline transcripts from the live decay" "$(cat <<'BODY'
## Summary
The deployed demo entry is decaying in real time. The repo's rule is that doc output comes from real runs; the Healthy capture is committed, and the other two bands plus the restore are pending this wait.
## Acceptance Criteria
- Run \`./scripts/trigger-eviction-wait.sh --until critical\` and capture the sentinel scan JSON.
- Run \`./scripts/trigger-eviction-wait.sh --until archived\` and capture the Archived scan JSON.
- Run \`./scripts/run-full-pipeline.sh --wait-for archived\` and capture the restore output.
- Append all captures to \`.transcripts/\`.
## Tech Stack
bash, soroban-state-sentinel, stellar-cli
BODY
)"

mk "Add a standalone-network rehearsal mode for the full pipeline" "$(cat <<'BODY'
## Summary
The honest demo is ~7 days of real time on testnet. For iterating without the wait, support a compressed rehearsal on a local standalone network where ledger time is controllable.
## Acceptance Criteria
- Documented recipe to start a standalone network with a small minPersistentTTL.
- \`run-full-pipeline.sh --wait-for archived\` completes end-to-end on the standalone network.
## Tech Stack
stellar-cli (container/standalone), bash scripts
BODY
)"

mk "Validate contracts.yml against action-state-watch's self-check schema" "$(cat <<'BODY'
## Summary
contracts.yml is a documented proposal for the fixture manifest. That repo is not public yet, so the schema has never been validated against the real consumer.
## Acceptance Criteria
- Confirm the self-check workflow reads contracts.yml.
- Align contracts.yml fields (network, contract_id_env, wasm path) with the consumer.
## Tech Stack
YAML, GitHub Actions, action-state-watch
BODY
)"

mk "Configure Actions variables/secrets and trigger demo-scan live" "$(cat <<'BODY'
## Summary
Blocked on token permissions. A repo-owner admin run is needed to go green and to exercise the restore path for real.
## Acceptance Criteria
- Set repository variable CONTRACT_ID and secret TESTNET_THROWAWAY_SECRET_KEY.
- Trigger demo-scan.yml (workflow_dispatch) and confirm it reports Healthy.
## Tech Stack
GitHub Actions, repo variables/secrets
BODY
)"

mk "Enable branch protection with the real required checks" "$(cat <<'BODY'
## Summary
Branch protection could not be configured from this environment. Protect main with required status checks matching the actual job names.
## Acceptance Criteria
- main is protected; PRs must pass contract-tests and scan.
- Merges are not deadlocked by never-running checks.
## Tech Stack
GitHub branch protection API / gh
BODY
)"

echo "5 backlog issues created on $REPO"
