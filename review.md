# Review — `archival-fixtures-demo` (updated 2026-09-09: completion pass + banner pass)

A self-review of the repo as it stands after the verification/hardening
pass: the earlier review marked everything "verified by construction"; this
one records what is now **verified by execution** against the live network,
what was found and fixed, and what is still pending or blocked.

## Purpose (what this repo is for)

A fixture/demo suite that makes Soroban **state archival** observable
end-to-end on testnet: one deliberately short-lived persistent entry,
created at the network-minimum TTL and never extended, so it decays
Healthy → Critical → Archived on a real-time timeline and must be restored.
It exists to give the sibling tools — `soroban-state-sentinel` (scan +
unsigned remediation XDR) and `action-state-watch` (the Action wrapper) —
a real, decaying testnet entry to watch, not a mock.

## Review method (updated)

| Area | Verified against |
|---|---|
| Network TTL/rent constants | Live testnet RPC `getLedgerEntries` (protocol 28, latest ledger 4,583,387+, 2026-09-09) — decoded `STATE_ARCHIVAL` and `CONTRACT_LEDGER_COST_V0` XDR by hand |
| Sentinel CLI/JSON contract | The sentinel's source (`args.rs`, `SCHEMA.md` 1.1.0) **and the real binary built from source (0.1.0)** |
| stellar CLI flags | The actually-installed CLI 28.0.0 (`--help` for `restore`/`read`/`extend`/`keys generate`) |
| Scripts | Executed end-to-end against testnet (deploy, sentinel scan, watcher, off-chain read) |
| Contract | `cargo test` (5/5) + release WASM build, both also green in GitHub Actions |
| CI | Live GitHub Actions runs (test-contract passed; demo-scan scheduled runs recorded) |
| Repo hygiene | Full `find` of `.git`/`.gitkeep`/`.gitignore`, `git status --ignored`, `git check-ignore` |
| README banner convention | Live GitHub: `karagozemin/Sub-Rosa` (top-level `assets/` dir + `<p align="center">` wrapper); `soroban-state-sentinel`, `carbonledger`, `back-it-onchain` have no banner to contradict it |

## Verdict by area (updated)

### Contract (`contracts/rapid-expiry-demo/`) — solid, and now compiles

- Small, single-purpose: one persistent entry `VALUE`, functions
  `initialize` / `read` / `touch` / `extend`. No hidden state.
- **`ttl()` was removed** (commit `9eed1a5`): the completion pass found the
  contract did not compile — soroban-sdk 27.0.6 has no production TTL
  getter (`get_ttl` is testutils-only), per CAP-0046-12's design that
  contracts cannot read their own TTL. `extend` no longer returns the TTL,
  and all TTL reads moved off-chain. This is the production pattern the
  repo teaches, not a workaround.
- Constants (`MIN_PERSISTENT_TTL_LEDGERS` 120,960, `MIN_TEMP_TTL_LEDGERS`
  720, `MAX_ENTRY_TTL_LEDGERS` 3,110,400) **match the live ledger** —
  verified 2026-09-09.
- Unit tests configure the test ledger with the real testnet parameters,
  assert TTL via the testutils trait, and disable SDK 27's test-snapshot
  files. **`cargo test`: 5/5 passing**, and the release WASM builds
  (`wasm32v1-none` target — soroban-sdk 27 no longer supports the legacy
  `wasm32-unknown-unknown`).

### Scripts (`scripts/`) — execute correctly against the real toolchain

- The schema fix from the earlier session (`5da9d50`) was confirmed against
  the **real sentinel binary**, which surfaced one more real mismatch: the
  `--keys` SCVal must be XDR 4-byte-aligned — `Symbol "VALUE"` needs 3
  padding bytes or stellar-xdr rejects it (`27b49fb`).
- `stellar keys generate --as-secret` (CLI 28) does not print the secret —
  it stores it in the CLI identity file. The deploy script now reuses the
  funded identity and reads the secret back via `stellar keys show`.
- `stellar contract restore/read/extend --key --durability` flag spelling
  **verified against the installed CLI** — correct as written.
- `deploy-and-shrink-ttl.sh` now runs end-to-end on testnet: deploys,
  initializes, scans, prints Healthy.
- Remaining soft spot: `trigger-eviction-wait.sh` writes scratch state to
  `/tmp/` files (works, slightly unclean).

### CI workflows (`.github/workflows/`) — self-contained, partly proven live

- `demo-scan.yml` and `demo-restore.yml` no longer depend on a contract
  `ttl()` (which cannot exist); both use the new off-chain reader
  `scripts/read-entry-ttl.py` (stdlib python: builds the
  `LedgerKey::ContractData` XDR, fetches it, reads the `liveUntilLedgerSeq`
  the RPC populates — direct TTL-key queries are rejected by soroban-rpc).
  Cross-validated against the live entry and the sentinel: **identical
  TTLs** (120,873 at first cross-check, later 120,794 — same
  `live_until_ledger` 4,704,624).
- `test-contract.yml` (new, `4a85eb8`): cargo test + wasm build on push and
  every PR. **Live run on the push: passed.**
- `demo-scan.yml`'s scheduled cron has **fired twice and failed both times
  with `CONTRACT_ID repository variable is not set`** — the documented
  setup requirement, now proven live. It will keep failing until the repo
  owner sets the variable (see Blocked below).

### Fixture manifest (`contracts.yml`) — proposal, unvalidated

- Declares the fixture (network, contract-id env var, WASM path, entry
  key + padded SCVal XDR, sentinel thresholds) for `action-state-watch`'s
  self-check. Since that repo is not public, the schema is a documented
  proposal rather than a validated contract (issue #4).

### Docs — real captures now

- `docs/surviving-soroban-state-archival.md` and
  `docs/setting-extend-ttl-boundaries.md` use **ledger-verified numbers**
  (parameters, rent denominators, fee plateaus) with the exact
  `getLedgerEntries` recipe (CONFIG_SETTING / ConfigSettingID 10) to
  reproduce them.
- The scan JSON example is now the **real capture** of the live entry
  (Healthy, 120,847 ledgers remaining at capture, size 72 B) with an
  explicit note that the Critical/Archived variants land when the entry
  decays and that the demo's accelerated thresholds (`--healthy-days 1
  --critical-days 1`) differ from the sentinel's defaults (30d/7d).
- `.transcripts/` holds the actual deploy transcript, sentinel scan JSON,
  watcher check, and off-chain TTL read — cross-checked against each other.
- README ties the pipeline together, links the transcripts, and includes
  the differentiation paragraph (SoroScope = gas/CPU profiling,
  Soroban-Guard = static security analysis; this suite = post-deployment
  TTL/archival monitoring).
- **README banner (Gap 1) now in place** (`f4a6f26`) — an earlier
  compressed-raster banner attempt was reverted at the owner's request
  (`main` reset to `b6c5840` and force-pushed, then the 1.8 MB handoff
  source in `images/` removed in `be6d10e`), so the banner was regenerated
  from scratch as an SVG: a hand-authored 1280×640 `assets/banner.svg`
  with the repo name as real `<text>` elements (`ARCHIVAL` in teal,
  `FIXTURES DEMO` in blue — pulled from the repo name itself so it can't
  drift), tagline "Simulating Soroban state archival on testnet" grounded
  in the README's own description, and a blue→teal shield on the dark
  `#111318` background. Rasterized to `assets/banner.png` (~53 KB,
  1280×640, under the 200 KB target) and referenced above the README
  title, centered per the confirmed approved-repo convention (`assets/`
  dir + `<p align="center">`, matched `karagozemin/Sub-Rosa`; see Review
  method table). Remote verified: GitHub's rendered README rewrites the
  `<img>` to the raw URL, which serves 200 `image/png` end-to-end.

### Hygiene — clean

- `.gitignore`: `.deploy/` (secret key + contract id) and `target/`
  correctly ignored; `git check-ignore` confirms; `.transcripts/` committed
  deliberately (real run output, no secrets — verified).
- `SECURITY.md` names the single key in the suite (the TESTNET-ONLY
  throwaway demo key) and states no other tool holds a key.
- `CONTRIBUTING.md` codifies the git workflow; `scripts/create-issue-backlog.sh`
  documents the issue-backlog generation.

## What is now proven by execution

1. **Live deployment on testnet** — contract
   `CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4`, entry
   initialized, real explorer transaction. Healthy at ~120,790+ ledgers and
   decaying ~1 ledger per ~5s (observed value dropping across checks).
2. **Sentinel scan against real state** — Healthy band with the repo's
   thresholds; Critical-under-defaults behavior also observed live (the
   default 30d/7d thresholds flag a fresh ~7-day entry Critical, justifying
   the repo's explicit 1d/1d override).
3. **Off-chain TTL read == sentinel** — same `live_until_ledger_seq`, same
   TTL, to the ledger.
4. **`cargo test` green (5/5)** and the WASM build green — locally and in
   GitHub Actions (`test-contract.yml` passed on the push).
5. **The scheduled cron fires** — demo-scan has run twice; both runs failed
   for the documented, expected reason (missing `CONTRACT_ID` variable),
   not a workflow bug.
6. **Scripts run end-to-end from a stranger's setup path** — the README's
   deploy → check flow was exercised as written.

## What is still pending (real time, not blockers)

1. **Critical → Archived → restore phases** — the entry is decaying in real
   time; Critical lands in ~6 days, Archived in ~7, then
   `run-full-pipeline.sh --wait-for archived` exercises the restore path.
   The transcripts for those phases will be appended when they land (issue
   #2). Until then, the docs state this plainly — no fabricated output.
2. **`demo-restore.yml` live run** — cannot be exercised until an entry is
   archived (or the owner runs it against the live entry, which exercises
   the extend + verify path only).
3. **`contracts.yml` validation** — blocked on `action-state-watch` being
   public (issue #4).
4. **Sentinel release binaries** — none published; consumers build from
   source (issue #7).
5. **Remaining Gap-1 items** — the README banner item is closed; badges,
   the maintainer table, GitHub topics, and the contrib.rocks credits
   section are still open (all separate, already-scoped items).

## Blocked items that need the repo owner (token permissions)

The environment token is refused (HTTP 403) for: Actions variables/secrets,
workflow dispatch, and the branch-protection API. To finish Gap 4 / Gap 5:

1. Set the repository **variable** `CONTRACT_ID` =
   `CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4`.
2. Set the repository **secret** `TESTNET_THROWAWAY_SECRET_KEY` = the `S...`
   key in `.deploy/testnet-throwaway.secret` (TESTNET-ONLY throwaway).
3. Trigger `demo-scan.yml` (should report Healthy) and `demo-restore.yml`
   (extend+verify path now; restore path once archived); record the runs.
4. Protect `main` with required checks using the real job names:
   `contract-tests` (test-contract.yml) and `scan` (demo-scan.yml — give it
   a `pull_request` trigger so it appears on PRs; read-only). Do **not**
   require `demo-restore`'s job — it is schedule/manual-only, never runs on
   PRs, and a required check on it would deadlock every merge (issue #6).

## Recommendations (what's left)

1. Let the deployed entry decay and capture the Critical/Archived/restore
   transcripts when they land (issue #2) — the docs already point at this.
2. Owner-side: complete the blocked items above (issues #4/#5/#6).
3. Consider the standalone-network rehearsal mode for demoing without the
   ~7-day wait (issue #3).
4. Consider publishing sentinel release binaries (issue #7).

## Summary

The completion pass converted most of the repo from "verified by
construction" to "verified by execution": the contract compiles and tests
green (after a real SDK-27 API fix), the scripts deploy and scan real
testnet state correctly (after three real execution fixes), CI has a green
live run, and the docs now carry real captured output. The demo is
currently mid-flight: deployed, Healthy, and decaying in real time toward
the Archived/restore demonstration. What remains is either real-time wait
(the decay), owner-side admin actions the environment token cannot perform
(variables/secrets, workflow dispatch, branch protection), or dependencies
outside this repo (`action-state-watch` publication). No known design flaws
remain unaddressed. The Gap-1 README banner item is now closed: after an
earlier raster-banner attempt was reverted at the owner's request, the
banner was regenerated as a hand-authored SVG with the repo name as real
`<text>` (so it can't drift out of sync) and rasterized to a ~53 KB PNG —
in the README, centered per the confirmed approved-repo convention, and
verified serving 200 over HTTPS. Badges, the maintainer table, topics, and
contrib.rocks remain the open Gap-1 items.