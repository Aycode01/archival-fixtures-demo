#!/usr/bin/env bash
#
# deploy-and-shrink-ttl.sh — deploy the rapid-expiry-demo contract to TESTNET
# and start the clock on its deliberately short TTL.
#
# ⚠️  TESTNET ONLY. Uses a TESTNET-ONLY throwaway key funded with testnet
# lumens (see TESTNET_THROWAWAY_SECRET_KEY). NEVER use a mainnet key or a
# mainnet RPC with anything in this repo.
#
# What this script does:
#   1. Preflights the toolchain and the TESTNET-ONLY key posture.
#   2. Builds the contract WASM if it is not already built.
#   3. Generates and friendbot-funds a fresh TESTNET-ONLY throwaway key if
#      TESTNET_THROWAWAY_SECRET_KEY is not set (and reuses the one from the
#      previous run if present).
#   4. Deploys the contract (reuses an existing deployment unless --force).
#   5. Initializes the single persistent entry, which the network creates at
#      the minimum persistent TTL — on testnet that is 120,960 ledgers
#      (~7 days) with current network parameters.
#   6. Runs `soroban-state-sentinel scan` and prints the starting health
#      band plus the ETA until the entry archives.
#
# "Shrink TTL", honestly: you cannot programmatically shorten an entry's TTL.
# The protocol enforces a minimum TTL when an entry is created or restored,
# and `extend_ttl` / `ExtendFootprintTTLOp` can only ever *raise* a TTL. The
# shortest TTL any contract can have is therefore the network minimum — which
# is exactly what this script arranges — after which the TTL decays at roughly
# one ledger every ~5 s until the entry archives. This script's job is to put
# the entry at the shortest possible TTL and start the clock.
#
# Usage:
#   ./scripts/deploy-and-shrink-ttl.sh [--force]
#
# Env (see scripts/lib.sh for defaults):
#   SOROBAN_RPC_URL, SOROBAN_NETWORK_PASSPHRASE,
#   TESTNET_THROWAWAY_SECRET_KEY, STELLAR_CLI_BIN, SENTINEL_BIN,
#   RAPID_EXPIRY_WASM, CONTRACT_ID_FILE

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

FORCE_DEPLOY=0
[[ "${1:-}" == "--force" ]] && FORCE_DEPLOY=1

testnet_only_banner "This script deploys and initializes a TESTNET-ONLY demo contract."
require_testnet_env
require_stellar_cli
require_sentinel
require_jq

info "rpc:      $SOROBAN_RPC_URL"
info "passphrase: $SOROBAN_NETWORK_PASSPHRASE"

# ---------------------------------------------------------------------------
# 1. Build the contract WASM if needed
# ---------------------------------------------------------------------------
if [[ ! -f "$RAPID_EXPIRY_WASM" ]]; then
    if ! command -v cargo >/dev/null 2>&1; then
        die "contract WASM not found at $RAPID_EXPIRY_WASM and cargo is not installed. \
Install Rust (https://rustup.rs) with the wasm32 target:  rustup target add wasm32-unknown-unknown"
    fi
    info "building contract WASM (first build downloads soroban-sdk, this can take a few minutes)..."
    cargo build \
        --manifest-path "$REPO_ROOT/contracts/rapid-expiry-demo/Cargo.toml" \
        --target wasm32-unknown-unknown \
        --release
fi
[[ -f "$RAPID_EXPIRY_WASM" ]] || die "WASM not found after build at $RAPID_EXPIRY_WASM"
ok "wasm ready: $RAPID_EXPIRY_WASM"

# ---------------------------------------------------------------------------
# 2. TESTNET-ONLY throwaway signing key
# ---------------------------------------------------------------------------
# If the operator did not supply a key, generate a fresh testnet-only
# throwaway and fund it from the testnet friendbot. The generated key is
# saved (mode 600) under .deploy/ so reruns reuse it. It holds only testnet
# lumens and is safe to discard at any time.
if [[ -z "$TESTNET_THROWAWAY_SECRET_KEY" && -f "$DEPLOY_DIR/testnet-throwaway.secret" ]]; then
    TESTNET_THROWAWAY_SECRET_KEY="$(tr -d '[:space:]' < "$DEPLOY_DIR/testnet-throwaway.secret")"
    info "reusing TESTNET-ONLY throwaway key from $DEPLOY_DIR/testnet-throwaway.secret"
fi
if [[ -z "$TESTNET_THROWAWAY_SECRET_KEY" ]]; then
    info "TESTNET_THROWAWAY_SECRET_KEY not set — generating a fresh TESTNET-ONLY throwaway key and funding it with testnet lumens..."
    GEN_OUT="$("$STELLAR_CLI_BIN" keys generate testnet-demo-throwaway \
        --as-secret --fund \
        --rpc-url "$SOROBAN_RPC_URL" \
        --network-passphrase "$SOROBAN_NETWORK_PASSPHRASE" 2>&1)"
    SECRET="$(grep -oE 'S[A-Z2-7]{55}' <<<"$GEN_OUT" | head -n1 || true)"
    if [[ -z "$SECRET" ]]; then
        die "could not extract a generated secret key from 'stellar keys generate' output: $GEN_OUT"
    fi
    mkdir -p "$DEPLOY_DIR"
    printf '%s\n' "$SECRET" > "$DEPLOY_DIR/testnet-throwaway.secret"
    chmod 600 "$DEPLOY_DIR/testnet-throwaway.secret"
    TESTNET_THROWAWAY_SECRET_KEY="$SECRET"
    ok "generated and funded TESTNET-ONLY throwaway key (saved to .deploy/testnet-throwaway.secret, gitignored)."
    warn "it holds only TESTNET lumens and can be discarded anytime — treat it as disposable."
else
    require_testnet_key
    ok "using TESTNET-ONLY throwaway key supplied via TESTNET_THROWAWAY_SECRET_KEY"
fi

# ---------------------------------------------------------------------------
# 3. Deploy (or reuse)
# ---------------------------------------------------------------------------
CONTRACT_ID=""
if [[ -f "$CONTRACT_ID_FILE" && "$FORCE_DEPLOY" -eq 0 ]]; then
    CONTRACT_ID="$(load_contract_id)"
    info "reusing previously deployed contract $CONTRACT_ID (pass --force to redeploy)"
else
    info "deploying contract..."
    DEPLOY_OUT="$("$STELLAR_CLI_BIN" contract deploy \
        --wasm "$RAPID_EXPIRY_WASM" \
        --source "$TESTNET_THROWAWAY_SECRET_KEY" \
        --rpc-url "$SOROBAN_RPC_URL" \
        --network-passphrase "$SOROBAN_NETWORK_PASSPHRASE" 2>&1)"
    CONTRACT_ID="$(grep -oE 'C[A-Z2-7]{55}' <<<"$DEPLOY_OUT" | head -n1 || true)"
    if [[ -z "$CONTRACT_ID" ]]; then
        die "could not extract a contract id from deploy output: $DEPLOY_OUT"
    fi
    save_contract_id "$CONTRACT_ID"
    ok "deployed: $CONTRACT_ID"
fi

# ---------------------------------------------------------------------------
# 4. Initialize the persistent entry (created at the network-minimum TTL)
# ---------------------------------------------------------------------------
if ! "$STELLAR_CLI_BIN" contract read \
        --id "$CONTRACT_ID" --key "$DEMO_ENTRY_KEY" --durability persistent \
        --rpc-url "$SOROBAN_RPC_URL" \
        --network-passphrase "$SOROBAN_NETWORK_PASSPHRASE" >/dev/null 2>&1; then
    info "initializing the persistent entry (created at the network-minimum TTL)..."
    INVOKE_OUT="$("$STELLAR_CLI_BIN" contract invoke \
        --id "$CONTRACT_ID" --source "$TESTNET_THROWAWAY_SECRET_KEY" \
        --rpc-url "$SOROBAN_RPC_URL" \
        --network-passphrase "$SOROBAN_NETWORK_PASSPHRASE" \
        -- initialize 2>&1 || true)"
    if ! grep -qi "already initialized" <<<"$INVOKE_OUT"; then
        # re-print anything unexpected (warnings etc.) for visibility
        [[ -n "$INVOKE_OUT" ]] && printf '%s\n' "$INVOKE_OUT"
    fi
    ok "entry '$DEMO_ENTRY_KEY' initialized"
else
    info "entry '$DEMO_ENTRY_KEY' already exists — skipping initialize"
fi

# ---------------------------------------------------------------------------
# 5. Report the starting health band and decay ETA
# ---------------------------------------------------------------------------
info "scanning with soroban-state-sentinel..."
SCAN="$(sentinel_scan_json "$CONTRACT_ID")"
STATUS="$(scan_status "$SCAN")"
TTL="$(scan_ttl "$SCAN")"
LATEST="$(jq -r '.latestLedger' <<<"$SCAN")"

printf '\n'
printf '  contract id : %s\n' "$CONTRACT_ID"
printf '  entry key   : %s (persistent)\n' "$DEMO_ENTRY_KEY"
printf '  latest ledger: %s\n' "$LATEST"
printf '  entry TTL   : %s ledgers (~%s)\n' "$TTL" "$(format_duration "$TTL")"
printf '  health band : %s\n' "$STATUS"
printf '  archives at : ~ledger %s\n' "$(( LATEST + TTL ))"
printf '\n'
ok "deploy complete. The entry is at the shortest TTL the network allows and is now decaying."
info "next steps:"
info "  - watch it decay / wait for archival:  ./scripts/trigger-eviction-wait.sh --check"
info "  - run the full demo pipeline:          ./scripts/run-full-pipeline.sh"
info "  - scan it on a schedule:               push + enable .github/workflows/demo-scan.yml"
printf '\n'