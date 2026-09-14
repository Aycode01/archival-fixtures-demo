# Review — `archival-fixtures-demo` (updated 2026-09-14: closeout pass + submission pass)

A self-review of the repo as it stands after the verification/hardening
pass: the earlier review marked everything "verified by construction"; this
one records what is now **verified by execution** against the live network,
what was found and fixed, and what is still pending or blocked.

## Closeout + submission passes (2026-09-14)

Two passes ran on this date. The first was scoped to close issues #3–#7 and land
PR #9; re-checking found all of that already done (#3–#7 closed, PRs #9 and #10
merged) except issue #2, so it became a verification pass plus one real fix. The
second did the remaining actionable item and produced the submission materials.

> **Process note.** The first pass's update to this file was committed
> (`ad8360b`) and pushed to its fork branch, but PR #11 was opened and merged
> before that commit landed, so it never reached `main`. This revision folds
> both passes in. Worth remembering generally: a commit pushed to the fork is
> not a commit that has been merged.

### Issue #2's automation could not self-close (fixed, `585ebb6`)

`capture-transcript.yml` dispatched `demo-restore.yml` when the entry reached
Archived, but **nothing anywhere wrote `.transcripts/07-restore.txt`** — while
that same workflow's final step gated its comment on issue #2 on that exact file
existing. The condition was unreachable by construction. `585ebb6` adds
`capture-restore-transcript.yml`, which on a **successful** restore run fetches
the run's real log into `07-restore.txt`, writes the
`08-scan-post-restore.json` that `docs/demo-recording-script.md` already
expected, and opens one PR on the fixed branch `auto/transcripts-restore` so
re-runs update it rather than stacking new ones. Failed runs are never captured,
so an unset secret leaves it green and silent instead of committing a broken run
as evidence. `e361f58` removed a dead duplicate TTL assignment in
`capture-transcript.yml`.

Capture is now automatic for all three transcripts. **Merging them is still
manual** — branch protection sets `enforce_admins: true`, which binds the
`GITHUB_TOKEN` too, so the automation cannot self-merge.

### `contracts.yml` was loadable by nothing (fixed, `933687e` / `b05bf67` / `25078cf`)

This file previously described `contracts.yml` as a proposal for
`action-state-watch`'s self-check "since that repo is not public". That repo is
now public, and reading it produced the opposite of the assumption: its
self-check runs with `config-path: contracts.example.yml`, **its own copy**, so
nothing was reading this repo's file. Handed to the real loader it throws
`Config must include a non-empty 'contracts' array` — the shape was never
loadable.

The schema was taken from the authoritative source, the consumer's
`src/config.ts`, not from its example file: `network` (required, non-empty
string); `contracts` (required, non-empty array), each entry requiring `address`
matching `/^[CG][A-Z0-9]{55}$/` and optionally `label` (string), `keys`
(string[]), `healthy-days` / `critical-days` (non-negative numbers); optional
`alert.dedupe-window-hours` (positive integer >= 1). Unknown keys are read into a
typed object and dropped, which is what lets this repo keep fixture metadata
alongside consumer-required fields.

- `scripts/validate-contracts-schema.py` transcribes that schema and reports
  **CONSUMER** failures (the action would throw) separately from **REPO**
  failures (the action silently accepts, then the sentinel chokes) — the latter
  catches misaligned SCVal key XDR, the same class of bug this repo shipped
  once before.
- `contracts.yml` is restructured into the consumer's shape with fixture
  metadata kept as ignored extras, and validated in CI as a step inside the
  existing `contract-tests` job — a step, not a new required check, since
  adding one changes merge behaviour and belongs to the owner.
- Two consequences, not buried: `address` is now **literal** (the consumer
  cannot resolve one indirectly), and the duplicated `scan:` block is gone in
  favour of the per-entry thresholds.

### Issue #5's record was wrong; the schedule has since fixed itself

Issue #5 was closed citing run `34832138820` as proof `demo-scan.yml` is "green
and running on schedule". That run was a **manual `workflow_dispatch`**. At
re-check time **all 22 scheduled runs had failed**, every one back to
2026-09-08, with `CONTRACT_ID repository variable is not set`.

The schedule then produced its first genuine success — run `34837370757`, event
`schedule`, 2026-09-14T11:16:23Z, reading `ttl=32424 band=Healthy`. Tally: 1
scheduled success, 22 scheduled failures, 1 manual success. The variable is
therefore set and the cron works; the earlier failures indicate it did not exist
yet, not a workflow bug. A correcting comment was drafted for #5, but see the
token limits below — it could not be posted.

### Issue #7's redirect was never made

#7 was closed as out-of-scope for this repo with a note that an equivalent issue
"should be opened" in the sentinel repo. It was not:
`Aycode01/soroban-state-sentinel` is public, has issues enabled, and has **zero
issues**, so the release-binaries need is tracked nowhere. Consumers still build
the sentinel from source.

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
| Consumer schema (`contracts.yml`) | The consumer's own source — `action-state-watch` `src/config.ts` (read 2026-09-14) — not its example file, and not the earlier assumption |
| Scheduled CI evidence | Each `demo-scan` run's **`event` field**, not just its conclusion. Checking `event` is how the "green on schedule" claim was found to be a manual dispatch |
| Issue/PR write capability | Exercised, not assumed: the REST `permissions` object reports `push: true, triage: true` on both repos while `addComment`, `createIssue` and `git push upstream` all return 403 |

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
- `demo-scan.yml`'s scheduled cron is proven to fire and has now succeeded.
  History: 22 scheduled failures (every run back to 2026-09-08, all
  `CONTRACT_ID repository variable is not set`), then the **first scheduled
  success** — run `34837370757`, event `schedule`, 2026-09-14T11:16:23Z,
  `ttl=32424 band=Healthy`. The single earlier green run was a manual
  `workflow_dispatch` and was never evidence about the schedule.
- `capture-transcript.yml` (`fa019f6`) — on each completed `demo-scan`, writes
  the Critical/Archived scan transcript when the band flips and that file is
  absent, then opens a PR.
- `capture-restore-transcript.yml` (`585ebb6`) — on a successful
  `demo-restore` run, commits `07-restore.txt` and
  `08-scan-post-restore.json`. Together these close the gap that made issue #2
  uncloseable; see the pass notes above.

### Fixture manifest (`contracts.yml`) — aligned and validated

- Written in the shape `action-state-watch`'s consumer actually loads, with the
  fixture metadata (WASM path, deploy script, entry XDR, rpc_url) retained as
  extra keys its loader drops. Validated by
  `scripts/validate-contracts-schema.py` in CI (issue #4, closed).
- The schema comes from the consumer's source, not a guess. Worth recording what
  the earlier pass got wrong: this file was described as a proposal for the
  consumer's self-check *while that repo was private*. Once public, the
  self-check turned out to read its own `contracts.example.yml`, so this repo's
  manifest was consumed by nothing and was not even loadable by the consumer.
- Known trade-off: `address` is literal, because the consumer requires a
  concrete strkey. A redeploy must update it alongside `.deploy/contract-id.txt`.
- Still outstanding downstream: the consumer's own copy
  (`action-state-watch/contracts.example.yml`) has not been aligned to match,
  so the two can drift.

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
5. **The scheduled cron fires and now succeeds** — 22 scheduled failures (all
   `CONTRACT_ID`), then the first scheduled success: `34837370757`, event
   `schedule`, 2026-09-14T11:16:23Z, `ttl=32424 band=Healthy`. Firing alone was
   never evidence of health; the `event` field is what settles it.
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
3. **`contracts.yml` validation** — **done** (issue #4 closed): the consumer
   schema was read from `action-state-watch`'s `src/config.ts` and is enforced
   in CI. The consumer's own copy still needs aligning.
4. **Sentinel release binaries** — none published; consumers build from source.
   Issue #7 was closed as out-of-scope, but the promised redirect issue in
   `soroban-state-sentinel` was **never opened**, so the need is tracked nowhere.
5. **Remaining Gap-1 items** — none. Banner, badges, topics (8 set) and the
   contrib.rocks question are all closed; contrib.rocks was removed (`91de157`)
   in favour of a Maintainers/Contributors section stating there are no outside
   contributors.

## Blocked items that need the repo owner (token permissions)

The environment token is **read-only and fork-scoped**. Confirmed refused (HTTP
403) for: Actions variables/secrets, workflow dispatch, the branch-protection
API, **issue and PR comment creation**, **issue creation** (on any repo,
including `soroban-state-sentinel`), and **`git push` to upstream**
(`Aycode01/*`). 

Do not read the REST `permissions` field as a capability check: it reports
`push: true, triage: true` on both repos while the actual credential cannot
write to either.

Remaining, all owner-side:

1. ~~Set the repository **variable** `CONTRACT_ID`~~ — **done.** Proven by the
   first scheduled success (run `34837370757`, 2026-09-14T11:16:23Z), which
   logged the contract id and read a live TTL.
2. **Set the repository secret `TESTNET_THROWAWAY_SECRET_KEY`** = the `S...` key
   in `.deploy/testnet-throwaway.secret` (TESTNET-ONLY throwaway). The last real
   blocker on `demo-restore.yml` and therefore on the restore transcript.
3. ~~Protect `main`~~ — **done** (issue #6): required check `contract-tests`
   only, `enforce_admins: true`, `required_approving_review_count: 0`,
   force-push and deletion disabled. The earlier advisory here (never require
   `scan` or `restore` — both are schedule/manual-only and would deadlock every
   PR) was followed. Consequence worth remembering: `enforce_admins: true` binds
   the `GITHUB_TOKEN` too, which is why the transcript workflows must open PRs
   rather than push to `main`.
4. **Merge the transcript PRs** as Critical/Archived/restore data lands.
5. **Post the drafted correction on issue #5** and **open the missing
   `soroban-state-sentinel` release-binaries issue** — both texts are drafted in
   the 2026-09-14 session output, but writing them needs a token this
   environment does not have.
6. **Record the demo video** from `docs/demo-recording-script.md`; it has not
   been executed and no video file exists anywhere in the repo.
7. **Confirm fixture-repo eligibility** with the program — a rules question,
   flagged in `docs/submission-drafts.md`, not something this repo can answer.

## Recommendations (what's left)

1. **Set `TESTNET_THROWAWAY_SECRET_KEY`** (issue #5). It is the only remaining
   blocker on the restore transcript; everything else in #2 is automated.
2. **Merge the transcript PRs when they land** so #2 closes itself. Do not close
   #2 by hand — let it close on real data.
3. **Align the consumer's copy of the manifest.** This repo's `contracts.yml` is
   now consumer-valid, but `action-state-watch/contracts.example.yml` has not
   been updated to match, so the two can drift.
4. **Open the missing `soroban-state-sentinel` issue** for #7's release
   binaries — the redirect was declared but never made.
5. ~~Standalone-network rehearsal mode~~ — **done** (issue #3, PR #10), shipped
   as a standalone-network recipe (`docs/standalone-rehearsal.md`) rather than a
   `--rehearsal` flag. Rehearsal output is explicitly ephemeral and must never
   enter `.transcripts/`.
6. **Record the demo video** and confirm fixture-repo eligibility before
   submitting; both are open in `docs/submission-drafts.md`.

## Summary

The completion pass converted most of the repo from "verified by
construction" to "verified by execution": the contract compiles and tests
green (after a real SDK-27 API fix), the scripts deploy and scan real
testnet state correctly (after three real execution fixes), CI has a green
live run, and the docs now carry real captured output. The demo is
currently mid-flight: deployed, Healthy, and decaying in real time toward the
Archived/restore demonstration — TTL 32,424 ledgers (≈45 h) at the last
scheduled scan, so Critical falls ~Sep 15 and Archived ~Sep 16.

The 2026-09-14 passes added two findings the earlier review could not have
reached: **issue #2's automation was structurally unable to close itself**
(nothing wrote the restore transcript its closing condition depended on), and
**`contracts.yml` was loadable by nothing** (the consumer reads its own copy, and
this repo's file was in a shape its loader rejects outright). Both are fixed;
the manifest is now validated in CI against the consumer's real source, and the
scheduled scan has finally gone green on its own. The remaining hard blocker is a
secret this environment cannot set, and the two issue-tracker records that were
wrong (#5's evidence, #7's redirect) are drafted but need a token that can write.
All Gap-1 items are closed — banner, badges, topics, and contrib.rocks, the last
replaced by an honest Maintainers/Contributors section.