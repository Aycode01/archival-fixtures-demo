# Review — `archival-fixtures-demo`

A self-review of everything in this repo as of the current commit: the
contract, the scripts, the CI workflows, the docs, and the repo hygiene,
including what was verified against live evidence and what still needs a
real run to prove.

## Purpose (what this repo is for)

A fixture/demo suite that makes Soroban **state archival** observable
end-to-end on testnet: one deliberately short-lived persistent entry,
created at the network-minimum TTL and never extended, so it decays
Healthy → Critical → Archived on a real-time timeline and must be restored.
It exists to give the sibling tools — `soroban-state-sentinel` (scan +
unsigned remediation XDR) and `action-state-watch` (the Action wrapper) —
a real, decaying testnet entry to watch, not a mock.

## Review method

| Area | Verified against |
|---|---|
| Network TTL/rent constants | Live testnet RPC `getLedgerEntries` (protocol 28, latest ledger 4,583,387, 2026-09-09) — decoded `STATE_ARCHIVAL` and `CONTRACT_LEDGER_COST_V0` XDR by hand |
| Sentinel CLI/JSON contract | The sentinel's source (`crates/cli/src/args.rs`) and locked `SCHEMA.md` 1.1.0 |
| stellar CLI flags (`contract extend/restore/read`, `keys generate --fund --as-secret`) | Official CLI manual (developers.stellar.org) |
| Script parsing logic | `bash -n` + a fake `SENTINEL_BIN` emitting a schema-accurate scan JSON (healthy + archived variants), exercising the real `jq` expressions |
| Repo hygiene | Full `find` of `.git`/`.gitkeep`/`.gitignore`, `git status --ignored`, `git check-ignore` |

## Verdict by area

### Contract (`contracts/rapid-expiry-demo/`) — solid

- Small, single-purpose: one persistent entry `VALUE`, functions
  `initialize` / `read` / `touch` / `extend` / `ttl`. No hidden state.
- The "short TTL" story is honest: you cannot create an entry shorter than
  `minPersistentTTL`; the contract writes at the network minimum and then
  never extends, which is the shortest possible demo timeline.
- Constants (`MIN_PERSISTENT_TTL_LEDGERS` 120,960, `MIN_TEMP_TTL_LEDGERS`
  720, `MAX_ENTRY_TTL_LEDGERS` 3,110,400) **match the live ledger** —
  re-verified 2026-09-09, not guessed.
- Unit tests configure the test ledger with the real testnet parameters and
  assert on `get_ttl` (the SDK-recommended approach). **Not re-run here** —
  no Rust toolchain in this environment; tests were authored in the scaffold
  commit.

### Scripts (`scripts/`) — fixed and now schema-correct

- The main defect found in review: the scripts parsed a **fictional
  sentinel JSON schema** (`.status`, `.latestLedger`, `.entries[].ttl`) and
  passed a nonexistent `--contract-id` flag. Fixed in `5da9d50` to consume
  the real contract: positional id, explicit `--keys <SCVal>` for the VALUE
  entry, lowercase band names mapped to Healthy/Critical/Archived,
  `.entries[].ledgers_remaining` / `.network.latest_ledger`.
- **Threshold choice is load-bearing and documented**: the sentinel's
  defaults (healthy 30d / critical 7d) would flag a fresh ~7-day demo entry
  as Critical instantly, killing the demo arc. Scripts scan with
  `--healthy-days 1 --critical-days 1` so Critical = ≤ 1 day (17,280
  ledgers), consistent with `demo-scan.yml`'s hard-coded floor.
- TESTNET-ONLY guardrails are strong: passphrase + RPC-URL checks in
  `require_testnet_env`, `S...` prefix check on the key, loud banners.
- Known soft spot: `stellar contract restore --key ... --durability ...`
  flag spelling is inferred from the documented `extend` options (same
  option family) — not executed against a real CLI. Also
  `trigger-eviction-wait.sh` writes scratch state to `/tmp/` files (works,
  slightly unclean).

### CI workflows (`.github/workflows/`) — solid, deliberately self-contained

- `demo-scan.yml` (scheduled) and `demo-restore.yml` (manual, added
  `39d5ce5`) share the `CONTRACT_ID` variable + `TESTNET_THROWAWAY_SECRET_KEY`
  secret, with clear setup headers and missing-config errors. demo-restore
  uses the stellar CLI to submit the restore; demo-scan is pure python3
  (`scripts/read-entry-ttl.py`) — no sentinel binary and no CLI needed in CI.
- Restore path detects archival via the off-chain TTL read (0 = archived),
  submits `RestoreFootprintOp` via `stellar contract restore`, extends, and
  re-verifies off-chain.
- **Not executed in GitHub Actions yet** — variables/secrets were configured
  after this review was written; see the completion-pass commit log.

### Fixture manifest (`contracts.yml`) — proposal, unvalidated

- Declares the fixture (network, contract-id env var, WASM path, entry
  key + SCVal XDR, sentinel thresholds) for `action-state-watch`'s
  self-check. Since that repo is not public, the schema is a documented
  proposal rather than a validated contract.

### Docs — honest, evidence-based

- `docs/surviving-soroban-state-archival.md` and
  `docs/setting-extend-ttl-boundaries.md` use **ledger-verified numbers**
  (parameters, rent denominators, fee plateaus) with the exact
  `getLedgerEntries` recipe (CONFIG_SETTING / ConfigSettingID 10 — the
  protocol 21+ renumbering is called out) to reproduce them.
- The scan JSON example is labeled as schema-shaped illustrative
  placeholders, not a captured run — per the repo rule that doc output must
  come from real runs, and none has happened yet.
- README ties the pipeline together and includes the differentiation
  paragraph (SoroScope = gas/CPU profiling, Soroban-Guard = static
  security analysis; this suite = post-deployment TTL/archival monitoring).

### Hygiene — clean

- `.gitignore`: `.deploy/` (secret key + contract id) and `target/`
  correctly ignored; `git check-ignore` confirms; nothing unignored in the
  tree.
- `.gitkeep` placeholders removed once their directories gained real files
  (`6f708d1`).
- `SECURITY.md` names the single key in the suite (the TESTNET-ONLY
  throwaway demo key) and states no other tool holds a key.
- `CONTRIBUTING.md` codifies the git workflow (one commit per unit,
  conventional commits, no `git add .`, no fabricated output).

## What has NOT been proven yet (honest gaps)

1. **No end-to-end testnet run.** Nothing here has been executed against a
   live deployed contract from this environment (no stellar CLI, no
   sentinel binary, no testnet key available here). The Healthy →
   Critical → Archived flip, the restore, and the CI workflows are
   unproven in the wild.
2. **Contract tests not re-run** (no cargo here).
3. **`contracts.yml` unvalidated** against `action-state-watch` (not public).
4. **Sentinel flag spelling verified from source, not from a live run** —
   the fake-binary dry run confirms the invocation shape and parsing, not
   the real binary's behavior.
5. **`stellar contract restore/read --key` assumed**, not executed.
6. **GitHub-side Phase 10 items not done**: branch protection with required
   checks, and the `gh`-generated issue backlog — both require repo access
   outside this working tree.

## Recommendations

1. Run the full pipeline against testnet once (deploy → scan → wait → restore)
   and capture the real output into the docs, replacing the illustrative JSON.
2. Run `cargo test` on the contract after any change; CI could add a
   `cargo test` job to make this automatic.
3. Once `action-state-watch` is public, align `contracts.yml` to its actual
   self-check schema.
4. Consider an optional `--wait-for` "instant rehearsal" mode backed by a
   standalone network for demoing without the ~7-day wait.
5. Configure branch protection + required checks (matching the two workflow
   job names) and generate the issue backlog via `gh`.

## Summary

The repo is in good shape: the contract is minimal and correct, the scripts
now speak the sentinel's real output contract, the CI is self-contained and
TESTNET-ONLY-guarded, the docs use ledger-verified numbers, and the hygiene
files are in place. The remaining risk is **verification debt**, not design
flaws: the whole demo needs one real testnet run (and a GitHub Actions run)
to turn "verified by construction" into "verified by execution".