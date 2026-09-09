#!/usr/bin/env bash
# scripts/lib.sh — shared helpers for the archival-fixtures-demo scripts.
#
# ⚠️  TESTNET ONLY. Every script in this repo operates on Stellar testnet with
# testnet-only throwaway keys. Never set these variables to a mainnet key or
# point them at a mainnet RPC. This is enforced loudly by
# `require_testnet_env` below — treat any deviation as a bug.
#
# Configuration is read from environment variables (defaults shown):
#
#   SOROBAN_RPC_URL            https://soroban-testnet.stellar.org
#   SOROBAN_NETWORK_PASSPHRASE "Test SDF Network ; September 2015"
#   STELLAR_CLI_BIN            stellar
#   SENTINEL_BIN               soroban-state-sentinel
#   TESTNET_THROWAWAY_SECRET_KEY  (no default — required to deploy/submit)
#   RAPID_EXPIRY_WASM          contracts/rapid-expiry-demo/target/.../rapid_expiry_demo.wasm
#   CONTRACT_ID_FILE           .deploy/contract-id.txt
#   LEDGER_SECONDS             5  (testnet ledger cadence, for ETA math)
#
# Requires: bash >= 4, curl, jq, and the `stellar` CLI
# (https://github.com/stellar/stellar-cli).

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
: "${SOROBAN_RPC_URL:=https://soroban-testnet.stellar.org}"
: "${SOROBAN_NETWORK_PASSPHRASE:=Test SDF Network ; September 2015}"
: "${STELLAR_CLI_BIN:=stellar}"
: "${SENTINEL_BIN:=soroban-state-sentinel}"
: "${TESTNET_THROWAWAY_SECRET_KEY:=}"
: "${RAPID_EXPIRY_WASM:=contracts/rapid-expiry-demo/target/wasm32-unknown-unknown/release/rapid_expiry_demo.wasm}"
: "${CONTRACT_ID_FILE:=.deploy/contract-id.txt}"
: "${LEDGER_SECONDS:=5}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_DIR="$REPO_ROOT/.deploy"

# The single persistent entry key used by the demo contract.
DEMO_ENTRY_KEY="VALUE"

# The same key as a base64-XDR SCVal (Symbol "VALUE"), which is what
# soroban-state-sentinel expects in its --keys flag. Derived from the XDR
# encoding of SCV_SYMBOL (15) + length 5 + "VALUE":
#   python3 -c "import struct,base64; print(base64.b64encode(struct.pack('>II',15,5)+b'VALUE').decode())"
DEMO_ENTRY_SCVAL_XDR="AAAADwAAAAVWQUxVRQ=="

# Mirror of the contract's MIN_PERSISTENT_TTL_LEDGERS
# (contracts/rapid-expiry-demo/src/lib.rs): the testnet network minimum for a
# new or restored persistent entry, in ledgers, as of 2026-09-08 (protocol 28).
# Scripts use it as the default "remediate back to" target. The network
# enforces the minimum; this constant is only a convenience default.
MIN_PERSISTENT_TTL_LEDGERS="${MIN_PERSISTENT_TTL_LEDGERS:-120960}"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_BOLD=""; C_RESET=""
fi

info()  { printf '%s\n' "${C_BOLD}[demo]${C_RESET} $*"; }
ok()    { printf '%s\n' "${C_GREEN}[ ok ]${C_RESET} $*"; }
warn()  { printf '%s\n' "${C_YELLOW}[warn]${C_RESET} $*" >&2; }
die()   { printf '%s\n' "${C_RED}[fail]${C_RESET} $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command '$1'. $2"
}

require_jq() {
    require_cmd jq "install jq (e.g. 'sudo apt-get install -y jq' or 'brew install jq')"
}

require_stellar_cli() {
    require_cmd "$STELLAR_CLI_BIN" \
        "install the Stellar CLI (https://developers.stellar.org/docs/tools/cli/stellar-cli#installation) or set STELLAR_CLI_BIN"
}

require_sentinel() {
    require_cmd "$SENTINEL_BIN" \
        "soroban-state-sentinel is not installed. It is the sibling repo in this suite; build it first \
(https://github.com/Aycode01/soroban-state-sentinel) and install the binary on PATH, or set SENTINEL_BIN."
}

# Asserts this repo's TESTNET-ONLY posture. Call from every script.
require_testnet_env() {
    require_cmd curl "install curl"
    require_jq
    if [[ "$SOROBAN_NETWORK_PASSPHRASE" != *"Test SDF Network"* ]]; then
        die "SOROBAN_NETWORK_PASSPHRASE is set to something that is not the testnet passphrase \
('$SOROBAN_NETWORK_PASSPHRASE'). This repo is TESTNET-ONLY. Refusing to continue."
    fi
    case "$SOROBAN_RPC_URL" in
        *testnet*|*localhost*|*127.0.0.1*|*standalone*) ;;
        *) die "SOROBAN_RPC_URL ('$SOROBAN_RPC_URL') does not look like testnet/standalone. \
This repo is TESTNET-ONLY. Refusing to continue." ;;
    esac
}

# TESTNET-ONLY throwaway key required for anything that signs/submits.
require_testnet_key() {
    require_testnet_env
    if [[ -z "$TESTNET_THROWAWAY_SECRET_KEY" ]]; then
        die "TESTNET_THROWAWAY_SECRET_KEY is not set. It must be a TESTNET-ONLY throwaway key funded \
with testnet lumens (never a mainnet key). Generate one with:

    stellar keys generate testnet-demo --as-secret --fund --rpc-url $SOROBAN_RPC_URL

then export the printed S... secret key as TESTNET_THROWAWAY_SECRET_KEY. See README.md."
    fi
    if [[ "$TESTNET_THROWAWAY_SECRET_KEY" != S* ]]; then
        die "TESTNET_THROWAWAY_SECRET_KEY does not look like a Stellar secret key (S...). \
This repo is TESTNET-ONLY — double check you are not holding a mainnet key."
    fi
}

# ---------------------------------------------------------------------------
# Contract identity
# ---------------------------------------------------------------------------
load_contract_id() {
    [[ -f "$CONTRACT_ID_FILE" ]] || die "no deployed contract found at $CONTRACT_ID_FILE — run scripts/deploy-and-shrink-ttl.sh first"
    tr -d '[:space:]' < "$CONTRACT_ID_FILE"
}

save_contract_id() {
    mkdir -p "$DEPLOY_DIR"
    printf '%s\n' "$1" > "$CONTRACT_ID_FILE"
    info "contract id saved to $CONTRACT_ID_FILE"
}

# ---------------------------------------------------------------------------
# RPC / sentinel helpers
# ---------------------------------------------------------------------------
# Latest closed ledger sequence via getLatestLedger.
rpc_latest_ledger() {
    curl -sS --max-time 20 -X POST "$SOROBAN_RPC_URL" \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","id":1,"method":"getLatestLedger"}' \
    | jq -r '.result.sequence'
}

# One sentinel scan of the demo contract, as JSON on stdout.
#
# The sentinel defines the canonical CLI/JSON contract (see its SCHEMA.md,
# currently schema 1.1.0); scripts in this repo consume:
#   network.latest_ledger
#   entries[]: { id, kind, band, ledgers_remaining, live_until_ledger_seq }
#   bands: healthy | expiring_soon | critical | archived
#
# Flags we pass and why:
#   <contract-id>            positional — the sentinel's clap arg is a
#                            positional, there is no --contract-id flag
#   --keys <SCVAL>           scan the demo VALUE entry explicitly; without
#                            --keys the sentinel only covers the contract
#                            instance and its code
#   --durability persistent  the VALUE entry is persistent
#   --healthy-days 1 --critical-days 1
#                            collapse the band boundaries so a freshly
#                            deployed entry (~7 days) is Healthy and flips to
#                            Critical at <= 1 day, which is this repo's
#                            documented Critical floor. With the sentinel's
#                            defaults (healthy 30d / critical 7d) a fresh
#                            demo entry would be flagged Critical immediately
#                            and the Healthy -> Critical -> Archived arc would
#                            never be observable.
#   --ledger-close-seconds   keep the sentinel's ledgers<->days math on the
#                            same cadence the rest of the repo assumes
sentinel_scan_json() {
    local contract_id="$1"
    "$SENTINEL_BIN" scan "$contract_id" \
        --rpc-url "$SOROBAN_RPC_URL" \
        --keys "$DEMO_ENTRY_SCVAL_XDR" \
        --durability persistent \
        --healthy-days 1 \
        --critical-days 1 \
        --ledger-close-seconds "$LEDGER_SECONDS" \
        --json
}

# Extract the demo entry's TTL (ledgers) from a sentinel scan JSON blob.
# `ledgers_remaining` is null once the entry is archived; treat that as 0.
scan_ttl() { jq -r '(.entries[] | select(.kind == "contract_data") | .ledgers_remaining) // 0' <<<"$1"; }

# Extract the demo entry's health band from a sentinel scan JSON blob and map
# it to the friendly names the docs use (the sentinel emits lowercase bands).
scan_status() {
    local band
    band="$(jq -r '.entries[] | select(.kind == "contract_data") | .band' <<<"$1")"
    case "$band" in
        healthy)       echo Healthy ;;
        expiring_soon) echo Expiring ;;
        critical)      echo Critical ;;
        archived)      echo Archived ;;
        *)             echo "$band" ;;
    esac
}

# Human-readable duration for `ledgers` at LEDGER_SECONDS seconds each.
format_duration() {
    local seconds=$(( $1 * LEDGER_SECONDS ))
    local d=$(( seconds / 86400 )) h=$(( (seconds % 86400) / 3600 )) m=$(( (seconds % 3600) / 60 ))
    if (( d > 0 )); then printf '%dd %dh %dm' "$d" "$h" "$m"
    elif (( h > 0 )); then printf '%dh %dm' "$h" "$m"
    else printf '%dm' "$m"; fi
}

# Print the testnet-only banner every script starts with.
testnet_only_banner() {
    printf '\n%s\n' "${C_BOLD}${C_RED}======================================================================${C_RESET}"
    printf '%s\n'  "${C_BOLD}${C_RED}  TESTNET ONLY — no mainnet keys, no mainnet contracts, ever.${C_RESET}"
    printf '%s\n'  "${C_BOLD}${C_RED}  $1${C_RESET}"
    printf '%s\n'  "${C_BOLD}${C_RED}======================================================================${C_RESET}"
    printf '\n'
}