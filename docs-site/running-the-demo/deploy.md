# Deploy

`scripts/deploy-and-shrink-ttl.sh` deploys the contract (or reuses an
existing deployment), initializes the single persistent entry, and runs a
starting sentinel scan. It is the entry point to the whole demo.

## What it does

1. Builds/checks the WASM is ready.
2. Generates and friendbot-funds a TESTNET-ONLY throwaway key if
   `TESTNET_THROWAWAY_SECRET_KEY` is unset (saved mode 600 to
   `.deploy/testnet-throwaway.secret`).
3. Deploys the contract (or reuses the previous contract id; pass
   `--force` to redeploy).
4. Calls `initialize()` — writes the `VALUE` entry at the network-minimum
   TTL (120,960 ledgers ≈ 7 days).
5. Runs `soroban-state-sentinel scan` and prints the starting health band.

The entry is created at the shortest TTL the network allows and then never
extended, so the decay starts immediately.

## Real transcript

From the live testnet run, 2026-09-09 (`.transcripts/01-deploy-healthy.txt`):

```
[ ok ] wasm ready: contracts/rapid-expiry-demo/target/wasm32v1-none/release/rapid_expiry_demo.wasm
[demo] reusing TESTNET-ONLY throwaway key from .../testnet-throwaway.secret
[demo] reusing previously deployed contract CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4 (pass --force to redeploy)
[demo] entry 'VALUE' already exists — skipping initialize
[demo] scanning with soroban-state-sentinel...

  contract id : CAEDHSOD3TXIAZF2BZMMNX7A2OKBCVE4WU7A6RWTHGGHWHJXHEQUMAT4
  entry key   : VALUE (persistent)
  latest ledger: 4583709
  entry TTL   : 120915 ledgers (~6d 23h 56m)
  health band : Healthy
  archives at : ~ledger 4704624

[ ok ] deploy complete. The entry is at the shortest TTL the network allows and is now decaying.
```

## Run it

```bash
./scripts/deploy-and-shrink-ttl.sh
```

Re-running is idempotent: it reuses the deployed contract and existing
entry. The printed contract id is what you need for the CI setup
(`CONTRACT_ID` repository variable).

## After deploy

- Watch it decay: [`watching-decay`](watching-decay.md)
- Set up the scheduled scan: [CI workflows](../ci-workflows.md)