# Security Policy

## Key handling — the short version

**No tool in this suite ever holds, stores, or transmits a private key —
with one exception, called out by name:**

- `scripts/deploy-and-shrink-ttl.sh` may generate (or reuse) the
  **TESTNET-ONLY throwaway demo key**, saved as
  `.deploy/testnet-throwaway.secret` (mode 600, gitignored) and/or supplied
  via the `TESTNET_THROWAWAY_SECRET_KEY` environment variable. It holds only
  **testnet lumens**, is funded by the testnet friendbot, and can be
  discarded at any time. `.github/workflows/demo-scan.yml` and
  `.github/workflows/demo-restore.yml` use the same key from the
  `TESTNET_THROWAWAY_SECRET_KEY` repository secret to read and restore the
  demo entry.

That is the entire inventory. `soroban-state-sentinel` (the sibling repo
this suite depends on) has no signing capability by design and produces
only unsigned XDR. Nothing here ever touches a mainnet key — the scripts
refuse to run if the network passphrase or RPC URL is not testnet, and
`require_testnet_env` / `require_testnet_key` in `scripts/lib.sh` enforce
that loudly.

## Reporting a vulnerability

If you find a security issue — a way the guardrails could be bypassed, a
path where a mainnet key could be accepted, a secret leaking into logs or
commits, or anything that could compromise the TESTNET-ONLY posture —
**do not open a public issue.** Report it privately:

- Open a [private security advisory](https://github.com/Aycode01/archival-fixtures-demo/security/advisories/new)
  on this repository, or
- email the maintainer (see the repository owner) with full reproduction
  steps.

We will acknowledge within 3 business days and work toward a fix before any
public disclosure.

## Secrets checklist for maintainers and contributors

- Never commit `.deploy/` — it contains a secret key and is gitignored.
- Never paste a secret key (`S...`) into issues, PRs, or docs.
- Keep `TESTNET_THROWAWAY_SECRET_KEY` a GitHub Actions *secret*, not a
  variable, and expect any run to log only the key's prefix checks, never
  the key itself.
- If a throwaway key is ever exposed, discard it (it only holds testnet
  lumens, so the blast radius is zero) and generate a fresh one with
  `stellar keys generate`.