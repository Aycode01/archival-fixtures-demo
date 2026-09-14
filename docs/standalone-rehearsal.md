# Standalone-Network Rehearsal Mode

> **⚠️ TESTNET ONLY for all production use.** The rehearsal path described here
> exists exclusively for local iteration and demonstration. It uses a local
> `stellar` container with a deliberately small `minPersistentTTL` so the full
> Healthy → Critical → Archived → Restore arc completes in minutes rather than
> ~7 days. No testnet key, no testnet RPC, no real funds — the local node is
> entirely self-contained and throwaway.
>
> The `.transcripts/` directory must only ever contain real testnet captures.
> Do not commit any rehearsal output there.

---

## Why this exists

The honest demo timeline on testnet is ~7 days: the network's `minPersistentTTL`
is 120,960 ledgers at ~5 s/ledger and cannot be shortened from within the protocol.
That is the whole point of the demo — it proves the issue is real and observable on
the live network. But running through the full arc just to check a script change or
record a quick walkthrough would mean waiting a week each time.

The standalone node path solves this by giving you a private Soroban-capable node
where you control the network parameters. You set `minPersistentTTL` to something
small (e.g. 100 ledgers ≈ 8 minutes), and the pipeline completes end-to-end in
one sitting.

---

## Prerequisites

- [`stellar` CLI](https://developers.stellar.org/docs/tools/cli/stellar-cli#installation)
  (includes `stellar network start` / `stellar container start`)
- Docker (used by `stellar container start` under the hood)
- `soroban-state-sentinel` on PATH (build from
  [`Aycode01/soroban-state-sentinel`](https://github.com/Aycode01/soroban-state-sentinel))
- `jq`, `python3` (stdlib only)

Verify:
```bash
stellar --version
soroban-state-sentinel --version
docker info
```

---

## Step 1 — Start a local standalone node with a small minPersistentTTL

```bash
stellar network start local \
  --protocol-version 21 \
  --min-persistent-entry-ttl 100
```

> `stellar network start` launches a containerised Stellar Core + Soroban RPC
> on `http://localhost:8000`. The `--min-persistent-entry-ttl 100` flag sets the
> network minimum to 100 ledgers. At ~1 s/ledger (standalone produces ledgers
> faster than testnet) the demo entry will archive in ~100 seconds.

Confirm the node is up:
```bash
curl -s http://localhost:8000 \
  -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' \
  -H 'Content-Type: application/json' | jq .result.status
# → "healthy"
```

---

## Step 2 — Configure the environment to point at localhost

```bash
export SOROBAN_RPC_URL="http://localhost:8000"
export SOROBAN_NETWORK_PASSPHRASE="Standalone Network ; February 2017"
```

> `scripts/lib.sh`'s `require_testnet_env` guard already permits `localhost` and
> `standalone` in `SOROBAN_RPC_URL`, so all scripts will run unmodified.

---

## Step 3 — Fund a fresh throwaway key and deploy

```bash
# Generate a keypair and fund it from the root account (available on standalone)
stellar keys generate rehearsal-throwaway --as-secret \
  --rpc-url "$SOROBAN_RPC_URL" \
  --network-passphrase "$SOROBAN_NETWORK_PASSPHRASE"

export TESTNET_THROWAWAY_SECRET_KEY="$(stellar keys show rehearsal-throwaway)"

# Deploy the contract and initialize the entry
./scripts/deploy-and-shrink-ttl.sh
```

The script prints the contract ID and the entry's starting TTL. With
`minPersistentTTL = 100` that will be ~100 ledgers ≈ ~100 seconds.

---

## Step 4 — Run the full pipeline

```bash
# Wait for the entry to archive (will take ~100 s at 1 s/ledger on standalone)
./scripts/run-full-pipeline.sh \
  --wait-for archived \
  --poll-seconds 5 \
  --max-wait-seconds 300
```

You will see the band transition from `Healthy` → `Critical` → `Archived` in the
poll output, followed by the automatic `RestoreFootprintOp` and post-restore
verification.

Expected output (abbreviated):

```
[demo] pipeline: deploy → decay to 'archived' → remediate to 120960 ledgers → verify
[demo] phase 1/4: deploy (or reuse) the contract and initialize the entry at the minimum TTL
[ ok ] reusing previously deployed contract <CONTRACT_ID>
[demo] phase 2/4: watching the entry decay until it is 'archived' (this is real time on testnet) ...
[10:00:00Z] ledger 200        ttl 98        (8m 10s)  band: Healthy
[10:00:05Z] ledger 205        ttl 93        (7m 45s)  band: Healthy
...
[10:01:40Z] ledger 300        ttl 0         (0m 0s)   band: Archived
[ ok ] target band reached (mode=archived, ttl=0 ledgers) after N scan(s).
[demo] phase 3/4: remediating the entry ...
  ttl at remediation start: 0 ledgers (0m)
[demo] entry is archived — restoring with RestoreFootprintOp via 'stellar contract restore' ...
[ ok ] restore submitted — the entry is live again, back at the network-minimum TTL
[ ok ] extend submitted
[demo] phase 4/4: verifying with soroban-state-sentinel ...
  contract id : <CONTRACT_ID>
  ttl before  : 0 ledgers (0m)
  ttl after   : 100 ledgers (8m 20s)
  health band : Healthy
[ ok ] pipeline complete: the entry decayed to 'archived', was remediated, and is now 'Healthy' again.
```

---

## Step 5 — Stop the standalone node

```bash
stellar network stop local
```

This tears down the container and discards all chain state. The rehearsal is
fully ephemeral — no testnet transactions, no testnet lumens used.

---

## Differences from the real testnet demo

| | Testnet (real demo) | Standalone rehearsal |
|---|---|---|
| `minPersistentTTL` | 120,960 ledgers (~7 days) | 100 ledgers (~100 s) |
| Ledger cadence | ~5 s | ~1 s |
| Total arc duration | ~7 days | ~2 minutes |
| Network passphrase | `Test SDF Network ; September 2015` | `Standalone Network ; February 2017` |
| Transcripts committed | Yes — to `.transcripts/` | **No** — rehearsal output is ephemeral |
| Real funds at risk | No (testnet-only throwaway) | No (standalone, no real network) |

---

## Troubleshooting

**`stellar network start` hangs or Docker is not running**  
→ Start Docker Desktop (or `sudo systemctl start docker` on Linux) and retry.

**`soroban-state-sentinel: command not found`**  
→ Build from source: `cargo install --path . --git https://github.com/Aycode01/soroban-state-sentinel`

**`SOROBAN_NETWORK_PASSPHRASE` guard fires**  
→ Ensure `export SOROBAN_NETWORK_PASSPHRASE="Standalone Network ; February 2017"` is set.
The guard in `lib.sh` accepts the standalone passphrase explicitly.

Wait — `lib.sh` line 104 checks `*"Test SDF Network"*`. The standalone passphrase
does NOT match. You need to override the guard for standalone by temporarily
setting `SKIP_TESTNET_ENV_CHECK=1` or by patching `lib.sh` locally. This is a
known limitation tracked in issue #3; the fix is to widen the passphrase guard to
also accept the canonical standalone passphrase.
