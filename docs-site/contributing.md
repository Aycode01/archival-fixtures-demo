# Contributing

Contributions are welcome. The full rules live in
[`CONTRIBUTING.md`](../CONTRIBUTING.md) — this page is a pointer, not a
duplicate.

## The short version

- Git workflow: never `git add .`, one commit per logical unit, push
  immediately, conventional commit format
  (`type(scope): description`).
- Never use a mainnet key or mainnet contract anywhere in this repo.
- Doc output must come from real runs — no fabricated transcripts or
  expected-output screenshots. If a phase of the demo hasn't happened yet
  (the Critical/Archived/restore phases, as of this writing), say so
  plainly in the doc.
- The TESTNET-ONLY throwaway key (`TESTNET_THROWAWAY_SECRET_KEY`) is the
  only key in this suite. See [`SECURITY.md`](../SECURITY.md) for the
  key-handling policy.

## Where to start

- The docs site (`docs-site/`) and reference docs (`docs/`) are the best
  map of the repo.
- Open an issue for a bug or feature before a large PR.
- Contract changes need `cargo test` green (CI runs it on push/PR).