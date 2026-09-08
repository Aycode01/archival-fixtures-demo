# rapid-expiry-demo

A deliberately short-lived Soroban contract (plus the scripts around it) that
makes **Soroban state archival** observable end-to-end on Stellar **testnet**:
deploy a contract holding one persistent entry, watch its TTL decay over
~7 days, see the entry get archived, and restore it.

> ⚠️ **TESTNET ONLY.** Everything in this repo signs, funds, and deploys with
> TESTNET-ONLY throwaway keys and talks to the testnet RPC. Never set a
> mainnet key or point `SOROBAN_RPC_URL` at mainnet. `scripts/lib.sh` enforces
> this posture loudly and refuses to run otherwise.

## The idea in one paragraph

Soroban ledger entries don't live forever: each one has a time-to-live (TTL)
measured in ledgers, and the network archives persistent entries once their
TTL hits zero. The protocol enforces a **minimum** TTL when an entry is
created or restored, `extend_ttl` can only ever *raise* a TTL, and ordinary
writes **do not** extend it — so a contract whose users keep transacting can
still silently lose its persistent data when nothing watches the TTL. This
repo builds the smallest possible contract that will inevitably archive —
exactly one persistent entry, created at the network-minimum TTL and never
extended — and pairs it with the tooling to watch the decay, get alerted, and
remediate. It exists to give
[`soroban-state-sentinel`](https://github.com/Aycode01/soroban-state-sentinel)
and `action-state-watch` a real, decaying, archivable testnet entry to watch.

## Repo layout

```
contracts/rapid-expiry-demo/   the contract: one persistent entry "VALUE",
                               functions initialize / read / touch / extend /
                               ttl, plus unit tests configured with the real
                               testnet network parameters
scripts/lib.sh                 shared env vars, preflight checks, RPC +
                               sentinel helpers (the TESTNET-ONLY guardrail)
scripts/deploy-and-shrink-ttl.sh   deploy (or reuse) + initialize + starting scan
scripts/trigger-eviction-wait.sh   read-only TTL watcher (polls the sentinel)
scripts/run-full-pipeline.sh       deploy -> decay -> remediate -> verify
.github/workflows/demo-scan.yml    scheduled TTL scan (self-contained, uses
                                   the contract's own ttl())
docs/surviving-soroban-state-archival.md   the deep dive
```

## Prerequisites

- `bash` >= 4, `curl`, `jq`
- [`stellar` CLI](https://developers.stellar.org/docs/tools/cli/stellar-cli)
- `soroban-state-sentinel` on PATH — sibling repo in this suite
  ([`Aycode01/soroban-state-sentinel`](https://github.com/Aycode01/soroban-state-sentinel));
  override the binary name with `SENTINEL_BIN`
- Rust toolchain with `wasm32-unknown-unknown` only if you need to build the
  contract WASM or run its tests

## Quick start

```bash
# 1. (optional) build + test the contract
rustup target add wasm32-unknown-unknown
cargo test --manifest-path contracts/rapid-expiry-demo/Cargo.toml

# 2. deploy (generates + friendbot-funds a TESTNET-ONLY throwaway key if
#    TESTNET_THROWAWAY_SECRET_KEY is unset; reuses existing deployment)
./scripts/deploy-and-shrink-ttl.sh

# 3. one-shot TTL / health-band check
./scripts/trigger-eviction-wait.sh --check

# 4. watch it decay (this is real time: ~6 days to Critical, ~7 to Archived)
./scripts/trigger-eviction-wait.sh --until critical

# 5. full lifecycle in one command: deploy -> decay -> remediate -> verify
./scripts/run-full-pipeline.sh --wait-for critical
```

The generated throwaway key is saved (mode 600) to `.deploy/testnet-throwaway.secret`
and reused on later runs; it holds only testnet lumens and can be discarded at
any time.

## Environment variables

All are optional (defaults shown); the only one that is truly required for
anything that signs or submits is `TESTNET_THROWAWAY_SECRET_KEY`.

| Variable | Default | Meaning |
|---|---|---|
| `SOROBAN_RPC_URL` | `https://soroban-testnet.stellar.org` | testnet RPC endpoint (testnet/localhost/standalone only) |
| `SOROBAN_NETWORK_PASSPHRASE` | `Test SDF Network ; September 2015` | must stay testnet — enforced |
| `STELLAR_CLI_BIN` | `stellar` | stellar-cli binary name/path |
| `SENTINEL_BIN` | `soroban-state-sentinel` | sentinel binary name/path |
| `TESTNET_THROWAWAY_SECRET_KEY` | *(none)* | TESTNET-ONLY throwaway `S...` key; if unset, generated + friendbot-funded |
| `RAPID_EXPIRY_WASM` | `contracts/rapid-expiry-demo/target/wasm32-unknown-unknown/release/rapid_expiry_demo.wasm` | wasm to deploy |
| `CONTRACT_ID_FILE` | `.deploy/contract-id.txt` | where the deployed contract id is persisted |
| `LEDGER_SECONDS` | `5` | testnet ledger cadence, used only for ETA math |

## The demo timeline

With current testnet network parameters (protocol 28, checked 2026-09-08) the
minimum persistent TTL is **120,960 ledgers ≈ 7 days** at the ~5 s ledger
cadence:

| stage | when | entry TTL |
|---|---|---|
| deploy + `initialize()` | ledger L | 120,959 ledgers (~7 days) |
| users keep transacting, nobody extends | each ledger | −1 ledger (~5 s each) |
| sentinel flags Critical | ≈ L + ~110,000 | < ~1 day |
| archived | ≈ L + 120,960 | 0 — reads/writes fail until restored |

These numbers are set by network validators and can change — verify before
trusting them (the contract and `docs/surviving-soroban-state-archival.md`
show how to read them from the ledger).

## CI: the scheduled scan

`.github/workflows/demo-scan.yml` runs every 6 hours (and on demand via
workflow dispatch), reads the entry TTL through the contract's own `ttl()`
function with the public stellar CLI, prints the health band, and fails the
run when the entry goes Critical or Archived so the decay turns the schedule
red. Setup:

1. Deploy once locally: `./scripts/deploy-and-shrink-ttl.sh`
2. Add a repository **variable** `CONTRACT_ID` = the printed contract id
3. Add a repository **secret** `TESTNET_THROWAWAY_SECRET_KEY` = the `S...`
   value in `.deploy/testnet-throwaway.secret`
4. Trigger once with the "Run workflow" button, then let the cron take over

## Faster rehearsal on a standalone network

Waiting ~7 days on testnet is the honest demo, but for iterating on the
scripts themselves, point `SOROBAN_RPC_URL` at a local standalone network
(e.g. `stellar network start` / `stellar container start`) where you control
ledger time and the whole timeline can be compressed. The scripts are
network-agnostic; only the TTL constants differ (set the standalone
`minPersistentTTL` to a small value if you want a fast rehearsal).

## Further reading

- [`docs/surviving-soroban-state-archival.md`](docs/surviving-soroban-state-archival.md) —
  how Soroban storage expiry works, the sentinel's health bands, and how to
  survive it in production
- Stellar docs: [State Archival](https://developers.stellar.org/docs/learn/fundamentals/contract-development/storage/state-archival)