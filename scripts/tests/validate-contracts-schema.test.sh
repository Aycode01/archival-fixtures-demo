#!/usr/bin/env bash
# validate-contracts-schema.test.sh — fixture tests for
# scripts/validate-contracts-schema.py.
#
# Each fixture is asserted to be accepted or rejected. The two rejection classes
# are distinguished on purpose: CONSUMER failures are ones action-state-watch
# itself would throw on, REPO failures are ones it silently accepts and the
# sentinel then chokes on. The malformed `keys[]` fixture is the latter.
#
# Also asserts the repo's real contracts.yml validates, so the manifest and the
# validator cannot drift apart.
#
# Usage: bash scripts/tests/validate-contracts-schema.test.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-contracts-schema.py"
FIXTURES="$ROOT/scripts/tests/fixtures"

PASS=0
FAIL=0

# expect_ok <path> <description>
expect_ok() {
  local path="$1" desc="$2"
  if output="$(python3 "$VALIDATOR" "$path" 2>&1)"; then
    printf '  ok    %s\n' "$desc"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n        expected VALID, got:\n%s\n' "$desc" "$output"
    FAIL=$((FAIL + 1))
  fi
}

# expect_reject <path> <description> <expected-class>
expect_reject() {
  local path="$1" desc="$2" class="$3"
  if output="$(python3 "$VALIDATOR" "$path" 2>&1)"; then
    printf '  FAIL  %s\n        expected REJECTED, but the validator accepted it\n' "$desc"
    FAIL=$((FAIL + 1))
  elif ! grep -q "$class" <<<"$output"; then
    printf '  FAIL  %s\n        rejected, but not as %s:\n%s\n' "$desc" "$class" "$output"
    FAIL=$((FAIL + 1))
  else
    printf '  ok    %s  (%s)\n' "$desc" "$class"
    PASS=$((PASS + 1))
  fi
}

echo "validate-contracts-schema fixture tests"

# The real manifest must satisfy the schema the consumer enforces.
expect_ok "$ROOT/contracts.yml" "repo contracts.yml is consumer-valid"
expect_ok "$FIXTURES/contracts-valid.yml" "fully-populated valid fixture"

# Deliberately malformed fixtures must be caught.
expect_reject "$FIXTURES/contracts-invalid-missing-contracts.yml" \
  "missing 'contracts' array (old fixture shape)" "CONSUMER"
expect_reject "$FIXTURES/contracts-invalid-address.yml" \
  "malformed Stellar address" "CONSUMER"
expect_reject "$FIXTURES/contracts-invalid-dedupe-window.yml" \
  "dedupe-window-hours of 0" "CONSUMER"
expect_reject "$FIXTURES/contracts-invalid-key-xdr.yml" \
  "misaligned SCVal key XDR" "REPO"

echo
printf 'validate-contracts-schema: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
