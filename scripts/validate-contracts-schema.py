#!/usr/bin/env python3
"""validate-contracts-schema.py — validate a contracts.yml against the real
action-state-watch consumer schema.

The schema enforced here is transcribed from the actual consumer, not invented:
`Aycode01/action-state-watch`, `src/config.ts` (`loadConfig` /
`validateContractEntry` / `validateAlertConfig`), read 2026-09-14 once that repo
became public. The consumer is what decides whether a config file is usable, so
its rules are the ones that matter.

Two classes of check are reported separately, because only the first is the
consumer's rule:

  CONSUMER  — mirrors src/config.ts exactly. A failure here means
              action-state-watch would throw at load time.
  REPO      — stricter invariants this repo adds on top, which the consumer
              does not check but which break the sentinel at runtime (for
              example, a `keys[]` entry that is not decodable base64 SCVal XDR
              is accepted by the consumer and then rejected by the CLI).

Note what the consumer does NOT do: unknown keys are read into a typed object
and silently dropped. So extra keys are allowed, and this validator does not
reject them — that is what lets this repo keep its fixture-only metadata
alongside the consumer-required fields.

Usage:
    python3 scripts/validate-contracts-schema.py [file ...]
    python3 scripts/validate-contracts-schema.py contracts.yml

Exit codes: 0 valid, 1 invalid, 2 file/parse/usage error.
"""

import argparse
import base64
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover - CI installs pyyaml
    print("validate-contracts-schema: pyyaml is required (pip install pyyaml)", file=sys.stderr)
    sys.exit(2)

# Transcribed from action-state-watch src/config.ts.
ADDRESS_RE = re.compile(r"^[CG][A-Z0-9]{55}$")
SCV_SYMBOL = 15


class Invalid(Exception):
    """A CONSUMER-class violation: the consumer would reject this file."""


class RepoInvalid(Exception):
    """A REPO-class violation: accepted by the consumer, breaks the toolchain."""


def _is_mapping(value) -> bool:
    return isinstance(value, dict)


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise Invalid(message)


def validate_key_scval_xdr(value: str, where: str) -> None:
    """REPO check: `keys[]` entries are handed to `soroban-state-sentinel
    --keys`, so they must be base64 SCVal XDR.

    A Symbol SCVal is disc(4) + len(4) + data padded to a 4-byte boundary.
    This repo has already shipped a padding bug here once (Symbol "VALUE" needs
    three padding bytes, not one), which is exactly the failure the consumer's
    "must be a string" check cannot catch.
    """
    try:
        raw = base64.b64decode(value, validate=True)
    except Exception as exc:
        raise RepoInvalid(f"{where}: not valid base64 ({exc})") from exc

    if len(raw) < 8:
        raise RepoInvalid(f"{where}: decodes to {len(raw)} bytes, too short to be an SCVal")

    disc = int.from_bytes(raw[0:4], "big")
    if disc == SCV_SYMBOL:
        declared = int.from_bytes(raw[4:8], "big")
        body = raw[8:]
        expected = (declared + 3) // 4 * 4
        if len(body) != expected:
            raise RepoInvalid(
                f"{where}: Symbol len={declared} needs {expected} padded body bytes, got {len(body)} "
                "(XDR is not 4-byte aligned)"
            )

    if len(raw) % 4 != 0:
        raise RepoInvalid(f"{where}: decodes to {len(raw)} bytes, not a multiple of 4")


def validate_contract_entry(entry, index: int) -> None:
    where = f"contracts[{index}]"
    _require(_is_mapping(entry), f"{where}: must be a mapping")

    # --- CONSUMER: address is required, non-empty, and strkey-shaped ---
    address = entry.get("address")
    _require(
        isinstance(address, str) and address,
        f"{where}: 'address' is required and must be a non-empty string",
    )
    _require(
        ADDRESS_RE.fullmatch(address) is not None,
        f"{where}: address '{address}' does not look like a valid Stellar address",
    )

    # --- CONSUMER: optional typed fields ---
    if entry.get("label") is not None:
        _require(isinstance(entry["label"], str), f"{where}: 'label' must be a string if provided")

    keys = entry.get("keys")
    if keys is not None:
        _require(isinstance(keys, list), f"{where}: 'keys' must be an array if provided")
        for k, key in enumerate(keys):
            _require(isinstance(key, str), f"{where}: keys[{k}] must be a string")

    for field in ("healthy-days", "critical-days"):
        if entry.get(field) is not None:
            value = entry[field]
            try:
                num = float(value)
            except (TypeError, ValueError):
                raise Invalid(f"{where}.{field} must be a non-negative number, got: {value}")
            _require(num >= 0, f"{where}.{field} must be a non-negative number, got: {value}")

    # --- REPO: the sentinel cannot consume malformed key XDR ---
    if isinstance(keys, list):
        for k, key in enumerate(keys):
            if isinstance(key, str):
                validate_key_scval_xdr(key, f"{where}.keys[{k}]")


def validate_alert_config(alert) -> None:
    _require(_is_mapping(alert), "'alert' must be a mapping if provided")
    value = alert.get("dedupe-window-hours")
    if value is not None:
        try:
            num = float(value)
        except (TypeError, ValueError):
            raise Invalid(f"alert.dedupe-window-hours must be a positive integer, got: {value}")
        _require(
            num.is_integer() and num >= 1,
            f"alert.dedupe-window-hours must be a positive integer, got: {value}",
        )


def validate_document(parsed) -> None:
    _require(
        _is_mapping(parsed),
        "config is not a valid YAML mapping",
    )

    # --- CONSUMER: network is a required non-empty string ---
    network = parsed.get("network")
    _require(
        isinstance(network, str) and network,
        "Config must include a 'network' string (e.g. 'testnet', 'mainnet')",
    )

    # --- CONSUMER: contracts is a required non-empty array ---
    contracts = parsed.get("contracts")
    _require(
        isinstance(contracts, list) and len(contracts) > 0,
        "Config must include a non-empty 'contracts' array",
    )

    for i, entry in enumerate(contracts):
        validate_contract_entry(entry, i)

    if parsed.get("alert") is not None:
        validate_alert_config(parsed["alert"])


def validate_file(path: str) -> list[str]:
    """Return a list of problem descriptions; empty means valid."""
    try:
        with open(path, encoding="utf-8") as fh:
            raw = fh.read()
    except OSError as exc:
        print(f"validate-contracts-schema: cannot read {path}: {exc}", file=sys.stderr)
        return [f"{path}: unreadable ({exc})"]

    try:
        parsed = yaml.safe_load(raw)
    except yaml.YAMLError as exc:
        return [f"CONSUMER {path}: failed to parse YAML: {exc}"]

    try:
        validate_document(parsed)
    except Invalid as exc:
        return [f"CONSUMER {path}: {exc}"]
    except RepoInvalid as exc:
        return [f"REPO {path}: {exc}"]

    return []


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Validate contracts config against the action-state-watch schema."
    )
    ap.add_argument(
        "paths",
        nargs="*",
        default=["contracts.yml"],
        help="config file(s) to validate (default: contracts.yml)",
    )
    ap.add_argument("-q", "--quiet", action="store_true", help="only print failures")
    args = ap.parse_args()

    paths = args.paths or ["contracts.yml"]
    failed = False

    for path in paths:
        problems = validate_file(path)
        if problems:
            failed = True
            for problem in problems:
                print(problem)
        elif not args.quiet:
            print(f"OK {path}: valid against action-state-watch's consumer schema")

    if failed:
        print(
            "\ncontracts schema validation FAILED — see CONSUMER/REPO problems above.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
