# Demo Recording Script — archival-fixtures-demo

A scripted, 3–5 minute walkthrough of the full Soroban state-archival lifecycle
demonstrated by this repo. Follow the scenes in order and capture each terminal
session and browser view as a continuous screen recording.

> **TESTNET ONLY.** All commands in this script use testnet keys and the testnet
> RPC. Never substitute a mainnet key or mainnet RPC URL at any point.

---

## Pre-flight checklist

Before hitting record, confirm the following are ready:

- [ ] `stellar` CLI installed and on `PATH`
- [ ] `soroban-state-sentinel` installed and on `PATH`
       (build from [`Aycode01/soroban-state-sentinel`](https://github.com/Aycode01/soroban-state-sentinel))
- [ ] `python3` available (stdlib only — no extra packages needed)
- [ ] `bash` >= 4, `curl`, `jq` available
- [ ] Testnet RPC reachable:
       `curl -s https://soroban-testnet.stellar.org -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' -H 'Content-Type: application/json'`
       → should return `{"result":{"status":"healthy",...}}`
- [ ] Terminal font readable at recording resolution (14 pt+ recommended)
- [ ] Browser has `stellar.expert` open to the live contract:
       `https://stellar.expert/explorer/testnet/contract/CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4`

---

## Scene 1 — Deploy (or confirm the live deployment)

**Expected duration:** ~45 seconds  
**What to capture:** terminal output confirming the contract ID and starting TTL.

If the live contract (`CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4`) is
still deployed and Healthy on testnet, **skip the deploy** and go straight to Scene 2 —
the script reuses the existing deployment automatically.

```bash
./scripts/deploy-and-shrink-ttl.sh
```

**Expected output (abbreviated):**

```
======================================================================
  TESTNET ONLY — no mainnet keys, no mainnet contracts, ever.
======================================================================

[demo] rpc:      https://soroban-testnet.stellar.org
[demo] passphrase: Test SDF Network ; September 2015
[ ok ] wasm ready: contracts/rapid-expiry-demo/target/wasm32v1-none/release/rapid_expiry_demo.wasm
[demo] reusing previously deployed contract CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4
[demo] entry 'VALUE' already exists — skipping initialize
[demo] scanning with soroban-state-sentinel...

  contract id : CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4
  entry key   : VALUE (persistent)
  latest ledger: <current>
  entry TTL   : <current ledgers> (~<d>d <h>h remaining)
  health band : Healthy
  archives at : ~ledger <live-until>

[ ok ] deploy complete.
```

> **Talking point:** The contract holds exactly one persistent entry (`VALUE`). Its TTL
> was set to the network minimum at initialization and is never extended — so the
> entry will archive in ~7 days, making the archival event observable and reproducible.

---

## Scene 2 — TTL health-band check

**Expected duration:** ~30 seconds  
**What to capture:** one-shot sentinel output showing the current health band and exact TTL.

```bash
./scripts/trigger-eviction-wait.sh --check
```

Or the low-level Python script used directly by CI:

```bash
python3 scripts/read-entry-ttl.py \
  --contract-id CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4 \
  --rpc-url https://soroban-testnet.stellar.org
```

**Expected output:** a single integer — remaining TTL in ledgers (e.g. `118462`).

> **Talking point:** The off-chain read via `getLedgerEntries` is the only way to
> see the TTL. The contract has no `ttl()` function — the protocol deliberately gives
> contracts no access to their own TTL (CAP-0046-12). This is the production
> monitoring pattern: watch from outside, not from inside.

---

## Scene 3 — Block explorer

**Expected duration:** ~30 seconds  
**What to capture:** browser showing the live contract on stellar.expert with the `VALUE`
entry visible.

Open in browser:

```
https://stellar.expert/explorer/testnet/contract/CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4
```

Point out:
- Contract ID matches the deploy output from Scene 1.
- The `VALUE` persistent entry is visible in the storage tab.
- The `liveUntilLedger` field corresponds to the TTL the script printed.

> **Talking point:** Everything the sentinel reports is publicly verifiable on the
> explorer — no trust required.

---

## Scene 4 — CI passing green

**Expected duration:** ~20 seconds  
**What to capture:** browser showing `test-contract.yml` passing in the Actions tab.

Open in browser:

```
https://github.com/Aycode01/archival-fixtures-demo/actions/workflows/test-contract.yml
```

Point out:
- Most recent run shows a green ✅ checkmark.
- Job `contract-tests` ran `cargo test` against real testnet TTL parameters (120,960
  ledger minimum — not a hardcoded stub).
- 5/5 unit tests passed.

> **Talking point:** CI runs on every push and PR. The required status check
> (`contract-tests`) must pass before any merge is allowed.

---

## Scene 5 — Restore (run after entry archives, ~7 days post-deploy)

**Expected duration:** ~60 seconds  
**What to capture:** terminal showing pre-restore TTL = 0 (Archived), the
`RestoreFootprintOp` submission, and post-restore TTL back to ~120,960.

> ⚠️ **Timing:** This scene requires the entry to be Archived. Either wait ~7 days
> from the original deploy date (2026-09-09), or use a local standalone network with
> a small `minPersistentTTL` for a compressed rehearsal — see the README's
> "Faster rehearsal on a standalone network" section.

**Preferred path — trigger from the Actions UI** (uses the stored throwaway key):

```
GitHub → Actions → demo-restore → Run workflow
```

**Alternative — run locally** (requires `TESTNET_THROWAWAY_SECRET_KEY` set):

```bash
./scripts/run-full-pipeline.sh --wait-for archived
```

**Expected output:**

```
pre-restore ttl=0 ledgers          ← entry is Archived
entry is ARCHIVED — restoring with RestoreFootprintOp...
restore submitted — entry is live again at the network-minimum TTL
extending entry to at least 120960 ledgers...
post-restore ttl=120960 ledgers (~6d 23h)
```

Confirm live again:

```bash
python3 scripts/read-entry-ttl.py \
  --contract-id CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4 \
  --rpc-url https://soroban-testnet.stellar.org
```

Expected: `120960` (the network minimum TTL, post-restore).

> **Talking point:** One `RestoreFootprintOp` brings the entry from Archived back
> to Healthy. The cost is a few stroops. This is the remediation path
> `action-state-watch` automates: it monitors the TTL, alerts at Critical, and
> produces the unsigned restore XDR for a keeper process to sign and submit.

---

## Post-recording — commit the transcripts

After each captured phase, append the real terminal output to `.transcripts/`:

| File | Content |
|------|---------|
| `.transcripts/05-scan-critical.json` | sentinel `scan --json` output when band = Critical |
| `.transcripts/06-scan-archived.txt` | `read-entry-ttl.py` output showing TTL = 0 |
| `.transcripts/07-restore.txt` | full restore script / workflow output |
| `.transcripts/08-scan-post-restore.json` | sentinel scan confirming Healthy after restore |

Once all four files are committed, close
[issue #2](https://github.com/Aycode01/archival-fixtures-demo/issues/2).
