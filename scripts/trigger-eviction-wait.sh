#!/usr/bin/env bash
#
# trigger-eviction-wait.sh — wait for (or just observe) the demo entry's TTL
# to decay to Critical / Archive on TESTNET.
#
# ⚠️  TESTNET ONLY. Read-only: never signs or submits, never holds a key.
#
# The documented way to "advance ledgers/time on testnet": wait. Testnet
# produces a ledger roughly every 5 seconds, and nothing in the protocol lets
# you accelerate an entry's decay:
#
#   - The network enforces a minimum TTL when an entry is created or
#     restored (`minPersistentTTL` = 120,960 ledgers ≈ 7 days on testnet as
#     of 2026-09-08). You cannot create an entry with a shorter TTL.
#   - `extend_ttl` and `ExtendFootprintTTLOp` only ever RAISE a TTL.
#   - There is no testnet "fast-forward" endpoint.
#
# So the demo timeline is real time: ~7 days from deploy to archival on
# testnet with current network parameters. This script makes the wait
# observable — it polls `soroban-state-sentinel scan` and prints a progress
# line at each poll — and exits 0 when the requested band is reached, which
# makes it safe to run inside CI on a schedule. For a faster (but not
# testnet) rehearsal, point SOROBAN_RPC_URL at a local standalone network
# (e.g. `stellar network start`/`stellar container start`) where you control
# ledger time; see README.md.
#
# Usage:
#   ./scripts/trigger-eviction-wait.sh [--check]
#   ./scripts/trigger-eviction-wait.sh [--until critical|archived] \
#       [--poll-seconds 300] [--max-wait-seconds 0] [--threshold N]
#
#   --check            one-shot: print the current TTL/band and exit
#   --until critical   stop when the entry enters the Critical band
#   --until archived   stop when the entry archives (default)
#   --threshold N      stop when TTL <= N ledgers (overrides --until)
#   --poll-seconds N   seconds between scans (default 300)
#   --max-wait-seconds N  give up after N seconds (0 = wait forever)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

MODE="archived"
POLL_SECONDS=300
MAX_WAIT_SECONDS=0
THRESHOLD=""
ONE_SHOT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) ONE_SHOT=1; shift ;;
        --until) MODE="$2"; shift 2 ;;
        --threshold) THRESHOLD="$2"; shift 2 ;;
        --poll-seconds) POLL_SECONDS="$2"; shift 2 ;;
        --max-wait-seconds) MAX_WAIT_SECONDS="$2"; shift 2 ;;
        -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
        *) die "unknown argument: $1 (see --help)" ;;
    esac
done

testnet_only_banner "Read-only TTL watcher — never signs or submits."
require_testnet_env
require_sentinel
require_jq

CONTRACT_ID="$(load_contract_id)"
info "watching entry '$DEMO_ENTRY_KEY' on $CONTRACT_ID"
info "timeline note: with current testnet parameters the entry starts at ~120,959 ledgers"
info "(~7 days) and decays ~1 ledger every 5s. There is no way to force this faster;"
info "the protocol minimum is enforced at creation and extensions only raise TTL."

if [[ "$MODE" != "critical" && "$MODE" != "archived" ]]; then
    die "--until must be 'critical' or 'archived'"
fi

start_ts="$(date +%s)"
scans=0

scan_once() {
    local scan ttl status latest
    scan="$(sentinel_scan_json "$CONTRACT_ID")"
    ttl="$(scan_ttl "$scan")"
    status="$(scan_status "$scan")"
    latest="$(jq -r '.latestLedger' <<<"$scan")"
    printf '[%s] ledger %-10s ttl %-9s (%s) band: %s\n' \
        "$(date -u +%H:%M:%SZ)" "$latest" "$ttl" "$(format_duration "${ttl:-0}")" "$status"
    printf '%s' "${ttl:-0}" > /tmp/.rapid-expiry-ttl
    printf '%s' "$status" > /tmp/.rapid-expiry-status
}

while true; do
    scans=$(( scans + 1 ))
    if ! scan_once; then
        warn "scan failed (RPC hiccup?) — retrying in ${POLL_SECONDS}s"
    fi
    ttl="$(cat /tmp/.rapid-expiry-ttl 2>/dev/null || echo 0)"
    ttl="${ttl:-0}"

    reached=0
    if [[ -n "$THRESHOLD" ]]; then
        (( ttl <= THRESHOLD )) && reached=1
    else
        status="$(cat /tmp/.rapid-expiry-status 2>/dev/null || echo Healthy)"
        if [[ "$MODE" == "archived" ]]; then
            (( ttl <= 0 )) && reached=1
        else
            # "critical" here means the sentinel already flags it; for the
            # demo entry that happens when the TTL is small enough that the
            # next scheduled extension/restore window is at risk. Fall back
            # to a TTL floor of 1 day so a plain TTL-based wait still works
            # even before the sentinel repo locks its band definitions.
            if [[ "$status" == "Critical" || "$status" == "Archived" ]]; then
                reached=1
            elif (( ttl <= 17280 )); then  # 1 day
                reached=1
            fi
        fi
    fi

    if [[ "$reached" -eq 1 ]]; then
        printf '\n'
        ok "target band reached (mode=$MODE, ttl=$ttl ledgers) after $scans scan(s)."
        exit 0
    fi

    if [[ "$ONE_SHOT" -eq 1 ]]; then
        exit 0
    fi

    if [[ "$MAX_WAIT_SECONDS" -gt 0 ]]; then
        now_ts="$(date +%s)"
        if (( now_ts - start_ts >= MAX_WAIT_SECONDS )); then
            die "timed out after ${MAX_WAIT_SECONDS}s without reaching mode=$MODE (last ttl=$ttl)"
        fi
    fi

    sleep "$POLL_SECONDS"
done