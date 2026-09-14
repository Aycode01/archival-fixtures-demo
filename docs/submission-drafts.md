# Wave Submission Drafts

> Working drafts for the grant/Wave submission form. Ready to paste, not submitted.
>
> Items marked `<pending: issue #2>` are still placeholders. As of 2026-09-14 the
> Critical/Archived/restore transcripts have **not** landed (the live entry is
> still Healthy), so those placeholders are deliberately left unfilled. Do not
> substitute estimates.

*Last verified: 2026-09-14T11:35Z. Every link below was fetched live at that time. The program-status and eligibility section was researched against the program's own published docs on the same date — see the citations there.*

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
`<pending: issue #2>` — the entry is still Healthy, with **TTL 32,261 ledgers
(≈44 h)** as of 2026-09-14T11:30Z (`live_until_ledger` 4,704,624, latest ledger
4,672,363 — read live with `scripts/read-entry-ttl.py`). At the current decay
rate Critical lands ~Sep 15 and Archived ~Sep 16. Capture of those transcripts is
now automated; only merging remains manual.

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
| Open PR (validation + docs) | https://github.com/Aycode01/archival-fixtures-demo/pull/12 | open, `contract-tests` **passing**, awaiting merge |
| Program page | https://www.drips.network/wave/stellar | HTTP 200 — "no active or upcoming Waves" |
| Program Terms & Rules | https://docs.drips.network/wave/terms-and-rules/ | HTTP 200 — §3.1 repo admission is discretionary |
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
testnet, which cannot be compressed or faked. The entry is Healthy (TTL 32,261,
≈44 h). Capture is now automated — `capture-transcript.yml` commits the
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
| Merge [PR #12](https://github.com/Aycode01/archival-fixtures-demo/pull/12) | The `contracts.yml` schema validation + these corrected drafts reaching `main` |
| Check repo approval status in the Drips maintainer dashboard | Whether `archival-fixtures-demo` is counted separately (see the program section above) |

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

## Program status and eligibility (researched live, 2026-09-14)

This replaces the earlier "eligibility question, deliberately not guessed" note.
The question is now researched against the program's own published material.
Every claim is cited; where the rules are genuinely silent, that is said plainly
rather than filled in.

### There is no active or upcoming Wave right now

From the program page (`drips.network/wave/stellar`, fetched 2026-09-14):
**"There are no active or upcoming Waves at the moment."** Eight Waves have run,
roughly monthly, from 2026-01-21 through **Wave 8: 2026-08-24 → 08-31**. Program
totals on the same page: **737 approved repos, 442 orgs, 251,739 issues, 8
Waves.**

*Consequence for this submission:* repo applications can be submitted at any
time and are reviewed independently of the Wave schedule, but issues added to a
Program are only actionable by contributors **during an active Wave**. The
practical deadline is therefore "before the next Wave is announced", not
immediately.

### Is this repo already approved? — cannot be confirmed from here

The approved-repo listing is public and reports "Showing 737 matching repos", but
it is server-rendered and filterable only by an internal organisation UUID; the
visible search box is client-side, so `?search=Aycode01` returns the unfiltered
page (verified — the same 20 rows come back for any search term). No public,
unauthenticated way to confirm one org's approval status was found.

Two weaker signals were checked and are **not conclusive either way**:

- None of `archival-fixtures-demo`, `soroban-state-sentinel` or
  `action-state-watch` carries a `Stellar Wave` label, and the Drips bot has
  never posted in any of them. The docs say the bot applies that label when an
  issue is added to a Program — but approval is repo-level and adding issues is a
  separate, deliberate maintainer action, so the label's absence does not imply
  rejection.
- `Aycode01` does appear on the platform as a contributor on a
  `Stellar Wave`-labelled issue in another repo, which shows the account is known
  to the program but says nothing about repo approval.

**How to resolve it: check the maintainer dashboard directly** — Drips Wave app →
Maintainers → Orgs and Repos, signed in as the applying account. That is the only
authoritative source.

### Does a fixture/demo repo qualify? — no rule excludes it; admission is discretionary

The Terms and Conditions (`docs.drips.network/wave/terms-and-rules`, fetched
2026-09-14) are the governing document and set **no eligibility criteria on
repository type**. The §4 eligibility requirements are all about the
*participant* (age, sanctions, jurisdiction, KYC). Repo admission is §3.1:

> "A maintainer … may submit a repository, containing a set of technical issues,
> for consideration in a Drips Wave Program. **The Association and the Wave
> Program Organizer retain sole discretion to select which repositories are
> admitted** to a Wave Program and may remove a repository at any time…"

The maintainer docs add that applications "require approval from the Wave
Program organizers", judged on code, project quality, activity, and "relevance to
the Stellar ecosystem".

So there is **no published rule that a fixture/demo repo is ineligible** — and
equally none stating it qualifies. The decision is explicitly discretionary.
Supporting precedent, observed directly in the live approved list:
**`wraith-protocol / demo` is an approved repo**, tagged "Stellar Agentic
Hackathon", worth 2x points, with 3 open issues. A repository literally named
"demo" with no description is approved and active, so repo type alone is not
disqualifying.

**Practically:** apply, and if declined use the appeal process (available since
Wave 7, from the same dashboard — first appeal two weeks after rejection, three
maximum). Do not present this repo in the submission as though eligibility were
already settled.

**Still unresolved, and named as such:** whether the program *counts* a
supporting fixture repo toward the submission's repo list is a policy question
only the organizers can answer. The honest framing is that the two tool repos are
the product and this repo is the demonstrable evidence they work against real,
decaying state.

### Funding shape, and whether priorities have shifted

No published list of "funding priorities" was found after searching the docs, the
Drips blog and the program page — the stated aim is simply "growing the Stellar
Open Source Ecosystem". What *is* published and may matter:

- The reward pool has been **$75,000 per Wave** for Waves 4–8 ($60,000 for 1–3).
- Since Wave 4 there are **per-repository points budgets**, to spread rewards.
- Approved repos carry **point multipliers** (2x / 4x) and hackathon tags.

So there is no priority list this repo has drifted from — but equally no
published signal that TTL/archival monitoring is a *named* priority. The
strongest evidence it is relevant is external and concrete; see below.

### White-space check: what changed since the original recon

Re-checked against the live approved list and GitHub on 2026-09-14. Two adjacent
efforts exist; neither duplicates this suite, and one is independent validation
of the problem statement:

1. **`stellar/js-stellar-sdk` is planning proactive TTL management.** Epic
   [#1625](https://github.com/stellar/js-stellar-sdk/issues/1625) ("Soroban
   Contract Operations", opened 2026-08-10, milestone Q3) includes
   [#1600](https://github.com/stellar/js-stellar-sdk/issues/1600) "TTL toolkit for
   proactive state archival management". Its own framing endorses the problem:

   > "The SDK's only archival help is reactive… **Nothing helps you keep state
   > alive on purpose, so every production dapp writes its own keeper from
   > scratch.**"

   This validates that the gap is real and prioritised — it is not a shipped
   competitor: it is unstarted (`0 / 4` sub-issues complete) and SDK-side, aimed
   at developers extending TTL from inside their own app. The sentinel's niche is
   the other direction: monitoring deployed contracts you do not control,
   alerting on them, and producing unsigned remediation XDR. The overlap is
   worth stating rather than ignoring.

2. **`Stellar-Cost-Labs/soroban-cost-estimator`** covers adjacent ground: it wraps
   `simulateTransaction` for resource/fee estimation and snapshots the network's
   pricing `ConfigSetting` entries to diff pricing changes over time. That
   overlaps the sentinel's cost-computation and config-decoding surface, but by a
   different mechanism (per-invocation simulation vs. per-entry TTL scanning) and
   for a different question ("what does this call cost?" vs. "when will this
   state die, and what does it cost to save?"). Not a duplicate; worth knowing.

No approved repository was found whose primary purpose is proactive **TTL
monitoring of deployed contracts**. That is a "nothing found", not a "nothing
exists" — the approved list could not be enumerated in full unauthenticated.
