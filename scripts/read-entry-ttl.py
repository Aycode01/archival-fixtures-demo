#!/usr/bin/env python3
"""read-entry-ttl.py — read a contract-data entry's TTL off-chain.

Soroban contracts cannot read their own TTL (CAP-0046-12; the soroban-sdk
`get_ttl` helpers are testutils-only), so TTL monitoring is an off-chain
job: this script asks the RPC for the entry via `getLedgerEntries` and
prints how many ledgers remain until archival — exactly what
`soroban-state-sentinel scan` does, in ~60 lines of stdlib so CI stays
dependency-free.

How it works: Soroban RPC refuses direct `LedgerKey::Ttl` queries
("ledger ttl entries cannot be queried directly" — soroban-rpc v28.0.1,
protocol 28) but populates `liveUntilLedgerSeq` on the entries it does
return. So this script builds the `LedgerKey::ContractData` XDR for the
storage key, fetches it, and reads `liveUntilLedgerSeq` off the response.

Usage:
  python3 scripts/read-entry-ttl.py --contract-id C... \
      [--entry-key VALUE] [--durability persistent|temporary] \
      [--rpc-url https://soroban-testnet.stellar.org]

Prints the TTL in ledgers (0 when the entry is archived / no entry), and
the latest + live-until ledgers to stderr. Exit 0 always (the caller
decides what a TTL means); exit 2 on usage/RPC errors.

TESTNET-ONLY posture: read-only, never signs, never holds a key.
"""

import argparse
import base64
import json
import struct
import sys
import urllib.request

# XDR enum values (protocol 28, stellar-xdr 28.0.0)
LEDGER_ENTRY_TYPE_CONTRACT_DATA = 6
SC_ADDRESS_TYPE_CONTRACT = 1
SCV_SYMBOL = 15
# NOTE: ContractDataDurability is TEMPORARY = 0, PERSISTENT = 1 (protocol 28
# XDR) — the opposite of the intuitive order.
CONTRACT_DATA_DURABILITY_PERSISTENT = 1
CONTRACT_DATA_DURABILITY_TEMPORARY = 0

# Strkey alphabet is RFC 4648 base32 (uppercase). Contract ids are
# version byte 0x10 ('C') + 32 payload bytes + 2 CRC16-XMODEM checksum
# bytes, all 56 chars base32-encoded with no padding.
STRKEY_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"


def crc16_xmodem(data: bytes) -> int:
    crc = 0
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def decode_strkey(s: str) -> bytes:
    if len(s) != 56:
        raise ValueError(f"not a strkey: {s}")
    # 56 chars * 5 bits = 280 bits = 35 bytes: version(1) + body(32) + crc16(2).
    bits = "".join(f"{STRKEY_ALPHABET.index(c):05b}" for c in s)
    raw = bytes(int(bits[i : i + 8], 2) for i in range(0, 280, 8))
    version, body, crc = raw[0], raw[1:-2], raw[-2:]
    if version != 0x10:  # VERSION_BYTE_CONTRACT (0x02 << 3)
        raise ValueError(f"not a contract id strkey (version {version})")
    # Stellar stores the CRC16-XMODEM checksum little-endian (low byte first).
    expected = crc16_xmodem(raw[:-2])
    if crc != bytes((expected & 0xFF, expected >> 8)):
        raise ValueError("strkey checksum mismatch")
    return body


def symbol_scval_xdr(symbol: str) -> bytes:
    """SCVal for SCV_SYMBOL: disc + length + bytes padded to 4-byte XDR alignment."""
    data = symbol.encode()
    padding = (-len(data)) % 4
    return struct.pack(">II", SCV_SYMBOL, len(data)) + data + b"\x00" * padding


def contract_data_key_xdr(contract_id: bytes, key: bytes, durability: int) -> bytes:
    """LedgerKey::ContractData { contract: SCAddress(contract), key: SCVal, durability }."""
    sc_address = struct.pack(">I", SC_ADDRESS_TYPE_CONTRACT) + contract_id
    return (
        struct.pack(">I", LEDGER_ENTRY_TYPE_CONTRACT_DATA)
        + sc_address
        + key
        + struct.pack(">I", durability)
    )


def rpc_call(rpc_url: str, method: str, params: dict) -> dict:
    req = urllib.request.Request(
        rpc_url,
        data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode(),
        # The public testnet RPC rejects urllib's default User-Agent (403);
        # identify ourselves plainly instead.
        headers={"Content-Type": "application/json", "User-Agent": "read-entry-ttl/0.1 (archival-fixtures-demo)"},
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read())


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--contract-id", required=True, help="C... contract id to read TTL for")
    ap.add_argument("--entry-key", default="VALUE", help="storage key symbol (default VALUE)")
    ap.add_argument(
        "--durability",
        default="persistent",
        choices=["persistent", "temporary"],
        help="storage durability (default persistent)",
    )
    ap.add_argument(
        "--rpc-url",
        default="https://soroban-testnet.stellar.org",
        help="testnet/localhost/standalone RPC only",
    )
    args = ap.parse_args()

    contract_id = decode_strkey(args.contract_id)
    durability = (
        CONTRACT_DATA_DURABILITY_PERSISTENT
        if args.durability == "persistent"
        else CONTRACT_DATA_DURABILITY_TEMPORARY
    )
    cd_key = contract_data_key_xdr(contract_id, symbol_scval_xdr(args.entry_key), durability)

    result = rpc_call(
        args.rpc_url, "getLedgerEntries", {"keys": [base64.b64encode(cd_key).decode()]}
    )
    if "error" in result:
        print(f"RPC error: {result['error']}", file=sys.stderr)
        return 2

    latest = result.get("result", {}).get("latestLedger")
    entries = result.get("result", {}).get("entries", [])
    if not entries:
        # No live entry => the persistent entry is archived, or a temporary
        # entry is dead. Either way the TTL is 0 until restored/recreated.
        print(0)
        print(f"no live entry — archived (latest ledger {latest})", file=sys.stderr)
        return 0

    entry = entries[0]
    # The RPC populates liveUntilLedgerSeq on returned entries (direct
    # LedgerKey::Ttl queries are rejected by soroban-rpc).
    live_until = entry.get("liveUntilLedgerSeq")
    if not live_until:
        print(0)
        print(f"entry has no liveUntilLedgerSeq (latest ledger {latest})", file=sys.stderr)
        return 0
    ttl = max(0, live_until - latest)
    print(ttl)
    print(f"latest_ledger={latest} live_until_ledger={live_until} ttl={ttl}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())