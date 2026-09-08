#!/usr/bin/env bash
#
# run-full-pipeline.sh — walk the demo entry through the entire archival
# lifecycle on TESTNET:
#
#   1. deploy (or reuse) the rapid-expiry-demo contract and initialize the
#      entry at the network-minimum TTL    (deploy-and-shrink-ttl.sh)
#   2. watch the TTL decay to the target band (trigger-eviction-wait.sh)
#   3. remediate: raise the TTL back to a healthy value
#      - entry still live  -> the contract's `extend` (extend_ttl)
#      - entry archived    -> `stellar contract restore` (RestoreFootprintOp),
#                             then `extend` for good measure
#   4. verify with soroban-state-sentinel and print the before/after
#
# ⚠️  TESTNET ONLY. Same posture as every script in this repo — a TESTNET-ONLY
# throwaway key, testnet RPC, and nothing else. See scripts/lib.sh.
#
# Timeline reality check: testnet produces a ledger every ~5 s and the entry
# starts at ~120,959 ledgers (~7 days), so phase 2 is real time. Use
# --max-wait-seconds to bound it, or run this on a local standalone network
# (see README.md) where you control ledger time.
#
# Usage:
#   ./scripts/run-full-pipeline.sh [--wait-for critical|archived] \
#       [--extend-to LEDGERS] [--poll-seconds N] [--max-wait-seconds N]
#
#   --wait-for critical   remediate while the entry is still live, as soon as
#                         the sentinel flags it Critical (default). This is
#                         the "watch the TTL, extend before it archives" path
#                         production operators are supposed to run.
#   --wait-for archived   let the entry archive first, then restore it with
#                         RestoreFootprintOp. Demonstrates the full
#                         eviction/restore cycle.
#   --extend-to LEDGERS   TTL to raise the entry to during remediation.
#                         Default: the testnet minimum, MIN_PERSISTENT_TTL_LEDGERS
#                         (120,960 ledgers ≈ 7 days). After an archival
#                         restore the entry is already at that minimum, so
#                         extend only acts as a floor.
#   --poll-seconds N      passed through to trigger-eviction-wait.sh (default 300).
#   --max-wait-seconds N  passed through; give up after N seconds (0 = forever).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

WAIT_FOR="critical"
EXTEND_TO="$MIN_PERSISTENT_TTL_LEDGERS"
POLL_SECONDS=300
MAX_WAIT_SECONDS=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --wait-for) WAIT_FOR="$2"; shift 2 ;;
        --extend-to) EXTEND_TO="$2"; shift 2 ;;
        --poll-seconds) POLL_SECONDS="$2"; shift 2 ;;
        --max-wait-seconds) MAX_WAIT_SECONDS="$2"; shift 2 ;;
        -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
        *) die "unknown argument: $1 (see --help)" ;;
    esac
done

[[ "$WAIT_FOR" == "critical" || "$WAIT_FOR" == "archived" ]] \
    || die "--wait-for must be 'critical' or 'archived'"
(( EXTEND_TO > 0 )) || die "--extend-to must be a positive number of ledgers"

testnet_only_banner "This script runs the FULL archival lifecycle demo on TESTNET."
require_testnet_env
require_stellar_cli
require_sentinel
require_jq

info "pipeline: deploy -> decay to '$WAIT_FOR' -> remediate to ${EXTEND_TO} ledgers -> verify"

# ---------------------------------------------------------------------------
# Phase 1: deploy (idempotent — reuses an existing deployment and, if present,
# the previously generated TESTNET-ONLY throwaway key)
# ---------------------------------------------------------------------------
info "phase 1/4: deploy (or reuse) the contract and initialize the entry at the minimum TTL"
"$SCRIPT_DIR/deploy-and-shrink-ttl.sh"
CONTRACT_ID="$(load_contract_id)"

# The deploy script may have just generated and funded the throwaway key for
# us; pick it up so the remediation steps below can sign.
if [[ -z "$TESTNET_THROWAWAY_SECRET_KEY" && -f "$DEPLOY_DIR/testnet-throwaway.secret" ]]; then
    TESTNET_THROWAWAY_SECRET_KEY="$(tr -d '[:space:]' < "$DEPLOY_DIR/testnet-throwaway.secret")"
    info "using TESTNET-ONLY throwaway key from $DEPLOY_DIR/testnet-throwaway.secret"
fi
require_testnet_key

# ---------------------------------------------------------------------------
# Phase 2: watch the TTL decay to the target band
# ---------------------------------------------------------------------------
info "phase 2/4: watching the entry decay until it is '$WAIT_FOR' (this is real time on testnet) ..."
"$SCRIPT_DIR/trigger-eviction-wait.sh" \
    --until "$WAIT_FOR" \
    --poll-seconds "$POLL_SECONDS" \
    --max-wait-seconds "$MAX_WAIT_SECONDS"

# ---------------------------------------------------------------------------
# Phase 3: remediate
# ---------------------------------------------------------------------------
info "phase 3/4: remediating the entry ..."
SCAN_BEFORE="$(sentinel_scan_json "$CONTRACT_ID")"
TTL_BEFORE="$(scan_ttl "$SCAN_BEFORE")"
printf '  ttl at remediation start: %s ledgers (%s)\n' "$TTL_BEFORE" "$(format_duration "${TTL_BEFORE:-0}")"

if [[ "$WAIT_FOR" == "archived" ]]; then
    info "entry is archived — restoring with RestoreFootprintOp via 'stellar contract restore' ..."
    "$STELLAR_CLI_BIN" contract restore \
        --id "$CONTRACT_ID" --source "$TESTNET_THROWAWAY_SECRET_KEY" \
        --rpc-url "$SOROBAN_RPC_URL" --network-passphrase "$SOROBAN_NETWORK_PASSPHRASE" \
        --key "$DEMO_ENTRY_KEY" --durability persistent
    ok "restore submitted — the entry is live again, back at the network-minimum TTL"
fi

info "ensuring the entry lives at least ${EXTEND_TO} ledgers (contract 'extend'; a no-op if already higher) ..."
"$STELLAR_CLI_BIN" contract invoke \
    --id "$CONTRACT_ID" --source "$TESTNET_THROWAWAY_SECRET_KEY" \
    --rpc-url "$SOROBAN_RPC_URL" --network-passphrase "$SOROBAN_NETWORK_PASSPHRASE" \
    -- extend --ledgers "$EXTEND_TO"
ok "extend submitted"

# ---------------------------------------------------------------------------
# Phase 4: verify
# ---------------------------------------------------------------------------
info "phase 4/4: verifying with soroban-state-sentinel ..."
SCAN_AFTER="$(sentinel_scan_json "$CONTRACT_ID")"
STATUS_AFTER="$(scan_status "$SCAN_AFTER")"
TTL_AFTER="$(scan_ttl "$SCAN_AFTER")"

printf '\n'
printf '  contract id : %s\n' "$CONTRACT_ID"
printf '  wait-for    : %s\n' "$WAIT_FOR"
printf '  ttl before  : %s ledgers (%s)\n' "$TTL_BEFORE" "$(format_duration "${TTL_BEFORE:-0}")"
printf '  ttl after   : %s ledgers (~%s)\n' "$TTL_AFTER" "$(format_duration "${TTL_AFTER:-0}")"
printf '  health band : %s\n' "$STATUS_AFTER"
printf '\n'

if [[ "$STATUS_AFTER" == "Archived" || "$STATUS_AFTER" == "Critical" ]]; then
    die "remediation did not take effect — the entry is still '$STATUS_AFTER' (ttl=$TTL_AFTER). Check the sentinel scan above."
fi
ok "pipeline complete: the entry decayed to '$WAIT_FOR', was remediated, and is now '$STATUS_AFTER' again."
info "next steps:"
info "  - watch it decay again:        ./scripts/trigger-eviction-wait.sh --check"
info "  - full eviction rehearsal:     ./scripts/run-full-pipeline.sh --wait-for archived"
info "  - the long read:               docs/surviving-soroban-state-archival.md"
printf '\n'