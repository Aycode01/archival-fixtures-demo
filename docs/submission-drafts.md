# Wave Submission Drafts

> Working drafts for the grant/Wave submission form. Ready to paste, not submitted.
>
> Items marked `<pending: issue #2>` are still placeholders. As of 2026-09-14 the
> Critical/Archived/restore transcripts have **not** landed (the live entry is
> still Healthy), so those placeholders are deliberately left unfilled. Do not
> substitute estimates.

*Last verified: 2026-09-14T11:18Z. Every link below was fetched live at that time.*

---

## Submission shape — read this first

This submission spans **three public repos** and has **no app layer to split into
a second repo**. That is a deliberate deviation from the default two-repo
(pattern: product repo + separate app/frontend repo), and it is a consequence of
what the tools are: a CLI and a GitHub Action, not a web product.

- `soroban-state-sentinel` — the core CLI (Rust)
- `action-state-watch` — a GitHub Action wrapper (TypeScript)
- `archival-fixtures-demo` — the fixture that gives the other two something real
  to watch (bash, Rust contract, CI only)

There is nothing to move into a frontend repo: both tools are headless, and the
third repo exists solely to produce real, decaying testnet state. See
"Repo Relationship Description" below for the technical wiring.

**One thing to confirm with the program, not assume:** whether
`archival-fixtures-demo` qualifies as a separately eligible demo/fixture repo, or
whether only the two tool repos count. This was flagged as to-confirm in the
previous draft and remains genuinely unresolved — see "Eligibility question" at
the end. It is a rules question about this program, not something the repo can
answer about itself.

---

## Repo Relationship Description

The three repos form one system with a single direction of dependency:

```
action-state-watch  (GitHub Action, TypeScript, cron)   ── wraps ──▶  soroban-state-sentinel
        │                                                                     ▲
        │ reads a contracts.yml manifest                                      │ builds from source
        ▼                                                                     │
   archival-fixtures-demo  ──── supplies a real, live, decaying testnet entry ─┘
```

**`soroban-state-sentinel`** ([`Aycode01/soroban-state-sentinel`](https://github.com/Aycode01/soroban-state-sentinel))
is the core CLI. It connects to a Soroban RPC endpoint, reads the TTL of every
ledger entry associated with a deployed contract, classifies each into health
bands (Healthy / ExpiringSoon / Critical / Archived), computes exact stroop costs
for remediation using the canonical `soroban-env-host` fee model, and produces
unsigned `ExtendFootprintTTLOp` / `RestoreFootprintOp` XDR. It **never holds a
private key and never submits a transaction** — its output is meant to be signed
by a human, a multisig, or a separately-secured keeper.

**`action-state-watch`** ([`Aycode01/action-state-watch`](https://github.com/Aycode01/action-state-watch))
wraps that CLI as a GitHub Action. On a cron schedule it reads a `contracts.yml`
manifest, invokes the sentinel per listed contract, routes severity-graded alerts
to Slack, Discord, or GitHub Issues, deduplicates notifications per contract, and
uploads unsigned restore XDR as a workflow artifact. Its config loader lives in
[`src/config.ts`](https://github.com/Aycode01/action-state-watch/blob/main/src/config.ts).

**`archival-fixtures-demo`** ([`Aycode01/archival-fixtures-demo`](https://github.com/Aycode01/archival-fixtures-demo))
is the fixture. It provides a real, live, decaying testnet contract — exactly one
persistent entry (`VALUE`, contract
`CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4`) — plus the scripts and
CI workflows that make the full archival lifecycle observable end-to-end against
the actual network rather than a simulation. Its job is to prove the other two
work against real, decaying state.

**A note on `contracts.yml` (corrected 2026-09-14).** Earlier drafts of this
document described this repo's `contracts.yml` as "the fixture manifest consumed
by action-state-watch". That was wrong, and has been checked against the real
consumer: `action-state-watch`'s self-check workflow runs with
`config-path: contracts.example.yml` — **its own copy inside that repo** — so this
repo's `contracts.yml` was not being read by anything. It has since been rewritten
into the shape the consumer's loader actually accepts (`network` + `contracts[]` +
`alert`), with the demo's fixture metadata retained as extra keys the loader
ignores, and is now validated in CI. The consumer's own copy still needs aligning
to match.

---

## Project Description

**Short version (for the form's summary field).**

This suite makes Soroban **state archival** observable, measurable, and
remediable before it breaks a production contract. A Soroban contract's
persistent data has a time-to-live, and nothing extends it automatically: a
persistent entry created at the network minimum starts with **120,960 ledgers
(≈7 days)** of life and can be raised only up to **3,110,400 ledgers (≈180
days)**, and ordinary contract writes do not extend it at all. A contract whose
users keep transacting can therefore reach TTL 0 while every external metric
looks healthy — at which point reads and writes revert until someone submits a
`RestoreFootprintOp`. `soroban-state-sentinel` monitors TTL off-chain, computes
the exact stroop cost of remediation, and emits **unsigned** remedy XDR;
`action-state-watch` turns that into a scheduled GitHub Action that alerts
before expiry; and `archival-fixtures-demo` runs a real, deliberately short-lived
testnet contract through the whole Healthy → Critical → Archived → Restore arc so
both tools are exercised against genuinely decaying state rather than a mock.

**Problem.** Production Soroban contracts can silently lose access to their
persistent data. Every ledger entry has a TTL, `extend_ttl` only ever raises it
and never lowers it, and ordinary writes do not extend it — so a contract can
reach TTL = 0 while all its metrics look normal. Reads and writes then revert
until a `RestoreFootprintOp` brings the entry back. The need for systematic TTL
monitoring surfaced concretely in the `wraith-protocol` repository, where a
contributor was tracking WASM and TTL budgets by hand in issues because no
automated tooling existed to watch deployed contract state.

**Mechanism.** Three integrated capabilities: (1) RPC-based TTL scanning via
`getLedgerEntries` — the only correct off-chain read path, since the protocol
deliberately gives contracts no access to their own TTL (CAP-0046-12); (2) exact
stroop cost computation for both `ExtendFootprintTTLOp` and `RestoreFootprintOp`,
ported from the canonical `soroban-env-host` fee model with source citations; and
(3) an unsigned XDR builder that batches remediation to the live network's
per-transaction footprint limits, producing output a human, multisig, or
separately-secured keeper process can sign and submit — the tool itself never
holds a key. `action-state-watch` wraps this into a scheduled Action that
monitors a `contracts.yml` manifest, routes severity-graded alerts, deduplicates
per contract, and uploads unsigned restore XDR as a workflow artifact.

**Technical foundation.** Rust (stable, edition 2021), `soroban-sdk` 27,
`stellar-xdr`, GitHub Actions, testnet RPC (`getLedgerEntries`,
`getLatestLedger`, `getNetworkConfig`). Contract unit tests are configured with
real testnet network parameters (protocol 28, `minPersistentTTL` 120,960 ledgers,
`maxEntryTTL` 3,110,400, `persistentRentRateDenominator` 1,215, verified against
the live ledger). The sentinel's JSON output schema is versioned and documented
in its `SCHEMA.md`; current version **`1.1.0`**.

**Current status.** All three repos are public, building, and tested; CI on this
repo's `main` is green. The live demo contract is deployed and decaying on
testnet. The Healthy-phase transcript is committed under `.transcripts/`. The
Critical/Archived/restore transcripts from the live decay are
`<pending: issue #2>` — the entry is still Healthy, with **TTL 32,424 ledgers
(≈45 h)** as of the scheduled scan run
[#34837370757](https://github.com/Aycode01/archival-fixtures-demo/actions/runs/34837370757)
(2026-09-14T11:16Z). At the current decay rate Critical lands ~Sep 15 and
Archived ~Sep 16. Capture of those transcripts is now automated; only a merge
remains manual.

---

## Supporting Links

Every link below was fetched live on 2026-09-14; nothing here is from memory.

| What | Link | Verified status |
|---|---|---|
| Live demo contract (testnet) | https://stellar.expert/explorer/testnet/contract/CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4 | HTTP 200 |
| Fixture repo | https://github.com/Aycode01/archival-fixtures-demo | public |
| Sentinel CLI repo | https://github.com/Aycode01/soroban-state-sentinel | public, pushed 2026-09-14T08:06Z |
| Action wrapper repo | https://github.com/Aycode01/action-state-watch | public, pushed 2026-09-11T09:22Z |
| CI status (this repo) | https://github.com/Aycode01/archival-fixtures-demo/workflows/test-contract/badge.svg | **passing** — latest `main` run [#34836835786](https://github.com/Aycode01/archival-fixtures-demo/actions/runs/34836835786) succeeded 2026-09-14T11:10Z |
| Sentinel JSON schema | https://github.com/Aycode01/soroban-state-sentinel/blob/main/SCHEMA.md | current version `1.1.0` |
| Consumer config loader | https://github.com/Aycode01/action-state-watch/blob/main/src/config.ts | authoritative schema for `contracts.yml` |
| Committed transcripts | `archival-fixtures-demo/.transcripts/` (01–04 committed; 05–08 pending issue #2) | |

**There is no hosted docs site.** `docs-site/` is a GitBook-style directory
(`SUMMARY.md` + pages) that lives in the repo and is read on GitHub; it is not
published to a URL. Do not submit a docs-site link.

**There is no demo video, and this is not an oversight.** `docs/demo-recording-script.md`
contains a *script* for recording one; it has **not been executed**. No video
file exists anywhere in the repo or the `assets/` directory. Do not include a
video link in the submission unless one is recorded first — the honest statement
is that the recording script is ready and the recording is outstanding.

---

## Planned Issues / Ongoing Work

Open at the time of writing, organised by **what it actually blocks** rather than
as a roadmap. There is exactly **one** open issue in this repo; everything else
has been closed.

### Open

**Issue #2 — Capture Critical and Archived pipeline transcripts from the live
decay.** ([#2](https://github.com/Aycode01/archival-fixtures-demo/issues/2))
*Blocks:* the submission's own "current status" claims, and the
`<pending: issue #2>` placeholders in this document and in the docs site.
*Why it is still open:* it is bounded by real elapsed ledger time on live
testnet, which cannot be compressed or faked. The entry is Healthy (TTL 32,424,
≈45 h). Capture is now automated — `capture-transcript.yml` commits the
Critical/Archived scan when the band flips, and
`capture-restore-transcript.yml` commits the restore run's log — so the wait no
longer needs a human watching the right hour. What remains is **merging the
resulting PRs**: branch protection sets `enforce_admins: true`, so the automation
cannot self-merge. This is expected to close itself in ~1–3 days.

### Owner actions (not issues, but genuinely outstanding)

| Action | Blocks |
|---|---|
| Set the `TESTNET_THROWAWAY_SECRET_KEY` Actions secret | `demo-restore.yml`, and therefore the restore transcript (issue #2's last third) and issue #5's unmet half |
| Merge the transcript PRs as Critical/Archived/restore land | Issue #2 closing itself |
| Record the demo video from `docs/demo-recording-script.md` | The submission video link (currently correctly absent) |
| Confirm fixture-repo eligibility with the program | Whether `archival-fixtures-demo` is counted separately |

### Recently closed, for context

Issues #3 (standalone-network rehearsal mode), #4 (`contracts.yml` schema
validation), #5 (Actions variables/secrets), #6 (branch protection) and #7
(sentinel release binaries) are all closed. Two of those closures needed
correcting during the 2026-09-14 pass and are worth knowing about:

- **#5** was closed citing a *manual* `workflow_dispatch` run as proof the
  schedule worked, which it was not. All 22 scheduled runs had failed up to that
  point. The schedule has since succeeded for real (run `34837370757`, event
  `schedule`, 2026-09-14T11:16Z), so the substance now holds — but the original
  evidence was backwards, and the secret half of the issue remains unmet.
- **#7** was closed as out-of-scope for this repo with a note that an equivalent
  issue "should be opened" in the sentinel repo. That issue was never actually
  opened; `Aycode01/soroban-state-sentinel` currently has zero issues, so the
  release-binaries need is tracked nowhere. Consumers still build the sentinel
  from source (see this repo's Prerequisites).

---

## Eligibility question (open, deliberately not guessed)

Whether a fixture/demo repo like `archival-fixtures-demo` is **separately
eligible** under this program's current rules — as opposed to only the two tool
repos counting — is not answered anywhere this repo can see. It is a rules
question, not a technical one, and it should be confirmed with the program at
submission time.

What was checked: the repo's own README positions it as supporting demonstration
infrastructure for the sibling tools, and the two tool repos are independently
public, building and tested. Nothing in this repo states or implies eligibility
either way. **Do not assume either direction based on this draft.**
