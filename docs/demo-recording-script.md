# Demo Recording Script — archival-fixtures-demo

A scripted, 3–5 minute walkthrough of the full Soroban state-archival lifecycle
demonstrated by this repo. Follow the scenes in order and capture each terminal
session and browser view as a continuous screen recording.

> **TESTNET ONLY.** All commands in this script use testnet keys and the testnet
> RPC. Never substitute a mainnet key or mainnet RPC URL at any point.

> **Status of this document.** The commands below were re-verified against the
> actual scripts on 2026-09-14 (every flag still exists). Expected outputs marked
> **[live]** were captured from real runs on that date; those marked **[template]**
> could not be produced in the reviewing environment because it has neither the
> `stellar` CLI nor `soroban-state-sentinel` installed, and no `.deploy/` state —
> they are the shapes you should see, not fabricated numbers.

---

## Current state of the demo (as of 2026-09-14)

| | |
|---|---|
| Contract | `CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4` |
| Entry | `VALUE`, persistent |
| Band | **Healthy** |
| TTL at last check | **32,261 ledgers** ≈ 44 h **[live]** |
| `live_until_ledger` | 4,704,624 (entry archives at this ledger) |
| Latest ledger | 4,672,363 **[live]** |
| Expected archive | ~2026-09-16 |

**The entry is still Healthy, so Scene 5 stays a fallback.** It has *not* archived
and no restore transcript exists yet, so the restore scene below shows the
conditional path rather than captured restore output. Re-check before recording:

```bash
python3 scripts/read-entry-ttl.py \
  --contract-id CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4 \
  --rpc-url https://soroban-testnet.stellar.org
```

`0` or an empty result means Archived → record the full Scene 5. A positive
integer means still live → record the extend-only fallback in Scene 5.

---

## Pre-flight checklist

Before hitting record, confirm the following are ready:

- [ ] `stellar` CLI installed and on `PATH`
- [ ] `soroban-state-sentinel` installed and on `PATH`
- [ ] `python3` available (stdlib only for the TTL read — no extra packages)
- [ ] `bash` >= 4, `curl`, `jq` available
- [ ] Testnet RPC reachable:
       `curl -s https://soroban-testnet.stellar.org -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' -H 'Content-Type: application/json'`
       → should return `{"result":{"status":"healthy",...}}`
- [ ] Terminal font readable at recording resolution (14 pt+ recommended)
- [ ] Browser has `stellar.expert` open to the live contract:
       `https://stellar.expert/explorer/testnet/contract/CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4`

### Installing the sentinel (there are no release binaries)

`soroban-state-sentinel` has **no published releases** — that is issue #7, still
open against the sentinel repo. Build it from source once, before recording:

```bash
git clone https://github.com/Aycode01/soroban-state-sentinel
cd soroban-state-sentinel
cargo build --release --bin soroban-state-sentinel -p sentinel-cli
export PATH="$PWD/target/release:$PATH"
cd -
soroban-state-sentinel --version   # confirm it resolves before you record
```

(The build command is the one `action-state-watch`'s own self-check workflow uses,
so it is known-good.)

---

## Scene 1 — Deploy (or confirm the live deployment)

**Expected duration:** ~45 seconds
**What to capture:** terminal output confirming the contract ID and starting TTL.

If the live contract is still deployed and Healthy on testnet, **skip the deploy**
and go straight to Scene 2 — the script reuses the existing deployment
automatically. It only deploys fresh with `--force`, or if `.deploy/contract-id.txt`
is absent.

```bash
./scripts/deploy-and-shrink-ttl.sh
```

**Expected output [template]** — the `<...>` values are live and will differ:

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
  archives at : ~ledger 4704624

[ ok ] deploy complete.
```

> **If `.deploy/` is missing on the recording machine**, the script will generate
> and fund a *new* testnet key and deploy a *new* contract. That resets the demo's
> 7-day clock and changes the contract ID everywhere in this script. Copy the
> existing `.deploy/` directory over instead, or expect to update the ID.

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

**Expected output [live]** — stdout is a single integer, nothing else. As of
2026-09-14T11:30Z that was:

```
32261
```

with the detail line on stderr (so it does not pollute the captured value):

```
latest_ledger=4672363 live_until_ledger=4704624 ttl=32261
```

> `--check` needs `soroban-state-sentinel` on `PATH`. If only `python3` is
> available, the second command alone carries the scene: it is the same read
> `demo-scan.yml` runs in CI, and the one this repo trusts.

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
- The `liveUntilLedger` field reads `4704624`, matching the TTL the script printed.

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
- Most recent run on `main` shows a green ✅ checkmark. **[live]** At the time of
  writing that was run
  [#34836835786](https://github.com/Aycode01/archival-fixtures-demo/actions/runs/34836835786),
  succeeded 2026-09-14T11:10Z.
- Job `contract-tests` runs `cargo test` against real testnet TTL parameters (120,960
  ledger minimum — not a hardcoded stub), and now also validates `contracts.yml`
  against `action-state-watch`'s consumer schema.
- 5/5 unit tests passed.

> **Talking point:** CI runs on every push and PR. The required status check
> (`contract-tests`) must pass before any merge is allowed.

---

## Scene 5 — Restore (run after the entry archives)

**Expected duration:** ~60 seconds
**What to capture:** terminal showing pre-restore TTL = 0 (Archived), the
`RestoreFootprintOp` submission, and post-restore TTL back to ~120,960.

> ⚠️ **Timing — this scene is not recordable yet.** The entry is still Healthy
> (~44 h of TTL remaining as of 2026-09-14) and archives around **2026-09-16**.
> There is no way to accelerate it: `minPersistentTTL` is enforced by the protocol
> and nothing lets you fast-forward a real testnet entry.

**Two honest options:**

1. **Wait and record the real thing** (~Sep 16) — the preferred path, and the one
   that produces a genuine archive→restore transcript.
2. **Record the extend-only fallback now.** While the entry is still live, this
   exercises the restore workflow's *verification and extension* half against real
   testnet state, but it does **not** demonstrate `RestoreFootprintOp`. Label the
   scene as the fallback when you record it — do not present it as a restore.

**Preferred path — trigger from the Actions UI** (uses the stored throwaway key):

```
GitHub → Actions → demo-restore → Run workflow
```

**Alternative — run locally** (requires `TESTNET_THROWAWAY_SECRET_KEY` set):

```bash
./scripts/run-full-pipeline.sh --wait-for archived
```

**Expected output — archived case [template]:**

```
pre-restore ttl=0 ledgers          ← entry is Archived
entry is ARCHIVED — restoring with RestoreFootprintOp...
restore submitted — entry is live again at the network-minimum TTL
extending entry to at least 120960 ledgers...
post-restore ttl=120960 ledgers (~6d 23h)
```

**Expected output — fallback, entry still live [template]:**

```
pre-restore ttl=32261 ledgers
entry is LIVE — nothing to restore; extending as a floor
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

> ⚠️ **Blocker to be aware of before recording:** `demo-restore.yml` needs the
> `TESTNET_THROWAWAY_SECRET_KEY` Actions secret, and it is not confirmed set. If it
> is missing the workflow fails immediately with a clear error rather than doing
> anything partial. Verify before you record this scene:
> `gh secret list --repo Aycode01/archival-fixtures-demo`.

> **Talking point:** One `RestoreFootprintOp` brings the entry from Archived back
> to Healthy. The cost is a few stroops. This is the remediation path
> `action-state-watch` automates: it monitors the TTL, alerts at Critical, and
> produces the unsigned restore XDR for a keeper process to sign and submit.

---

## Copy-paste block — the whole recording, in order

Run top to bottom. Scenes 1 and 2's `--check` need the full toolchain; the rest
need only `python3`/`curl`. Comments name the scene.

```bash
# ---- 0. Preflight -----------------------------------------------------------
curl -s https://soroban-testnet.stellar.org \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}'
# expect: {"result":{"status":"healthy",...}}

# Sentinel has no published releases (issue #7) — build it once, before recording.
# git clone https://github.com/Aycode01/soroban-state-sentinel
# cd soroban-state-sentinel && cargo build --release --bin soroban-state-sentinel -p sentinel-cli
# export PATH="$PWD/target/release:$PATH" && cd -

# ---- 1. Deploy / confirm the live deployment --------------------------------
./scripts/deploy-and-shrink-ttl.sh

# ---- 2. TTL health band -----------------------------------------------------
./scripts/trigger-eviction-wait.sh --check
python3 scripts/read-entry-ttl.py \
  --contract-id CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4 \
  --rpc-url https://soroban-testnet.stellar.org

# ---- 3. Block explorer (browser) -------------------------------------------
open "https://stellar.expert/explorer/testnet/contract/CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4"
# (Linux: xdg-open)

# ---- 4. CI green (browser) -------------------------------------------------
open "https://github.com/Aycode01/archival-fixtures-demo/actions/workflows/test-contract.yml"

# ---- 5. Restore — ONLY once the entry has archived --------------------------
# Re-check first; expect a positive integer (still live) until ~2026-09-16.
python3 scripts/read-entry-ttl.py \
  --contract-id CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4 \
  --rpc-url https://soroban-testnet.stellar.org
# Archived now? Then either:
#   GitHub → Actions → demo-restore → Run workflow        (preferred)
# or locally, with TESTNET_THROWAWAY_SECRET_KEY set:
./scripts/run-full-pipeline.sh --wait-for archived

# ---- 6. Verify the restore --------------------------------------------------
python3 scripts/read-entry-ttl.py \
  --contract-id CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4 \
  --rpc-url https://soroban-testnet.stellar.org
# expect: 120960
```

---

## Post-recording — transcripts are now captured automatically

You **do not** need to hand-write transcripts after recording any more. Two
workflows do it, which is what makes issue #2 self-closing:

| File | Written by | When |
|------|-----------|------|
| `.transcripts/05-scan-critical.json` | `capture-transcript.yml` | band flips to Critical |
| `.transcripts/06-scan-archived.json` | `capture-transcript.yml` | band flips to Archived |
| `.transcripts/07-restore.txt` | `capture-restore-transcript.yml` | a `demo-restore` run succeeds |
| `.transcripts/08-scan-post-restore.json` | `capture-restore-transcript.yml` | same run |

Each writes its file and opens a PR; **merging is still manual**, because branch
protection sets `enforce_admins: true`, which binds the Actions bot as well. Once
all three phases are present, the next scheduled `demo-scan` lets
`capture-transcript.yml` comment on
[issue #2](https://github.com/Aycode01/archival-fixtures-demo/issues/2) — review
that data and close it then, rather than closing it by hand in advance.

The recording itself (a video file) is **not** produced by any of the above, and
none exists yet. Uploading it is a manual step.
