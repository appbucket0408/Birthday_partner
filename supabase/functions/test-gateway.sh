#!/usr/bin/env bash
# Gateway-level verify_jwt check for the confirm endpoint and its five siblings.
#
# NOT INTERCHANGEABLE WITH test.sh -- the two scripts require OPPOSITE server
# flags and must never share a running `supabase functions serve` process:
#
#   test.sh          needs  supabase functions serve --no-verify-jwt
#   test-gateway.sh  needs  supabase functions serve            (no flag)
#
# test.sh's suite reaches into each function's OWN Authorization/
# x-drain-secret check, so its six tests need an unauthenticated request to
# actually get past the platform gateway (Kong) and land in the handler --
# that only happens with --no-verify-jwt, which disables Kong's JWT gate
# entirely for every function.
#
# This script tests the opposite thing: that Kong's gate is doing its job.
# It must run WITHOUT --no-verify-jwt, so an unauthenticated request to any
# of the five gated functions is stopped by Kong BEFORE the handler ever
# runs, while `confirm` (config.toml: [functions.confirm] verify_jwt = false)
# passes straight through to its handler. Run this against a
# --no-verify-jwt server and every function looks gateway-exempt --
# it would pass for the wrong reason, proving nothing.
#
# Restart the server between running this and test.sh; do not try to
# satisfy both with one flag choice.
#
# Run with:
#   supabase functions serve            # NOTE: no --no-verify-jwt
#   ./supabase/functions/test-gateway.sh
set -uo pipefail
cd "$(dirname "$0")/../.."

URL="${SUPABASE_URL:-http://127.0.0.1:54321}"

EXEMPT="confirm"
GATED=(
  claim_profile
  delete_account
  drain_reminders
  resolve_contacts
  add_celebrations
)

failures=()

# Kong's own rejection body is {"msg": "Error: ..."}; every handler's own
# guard in this project returns {"error": "..."} instead. Checking the body
# SHAPE, not just the 401 status, is what actually distinguishes "the
# gateway stopped this before the handler ran" from "the handler's own
# guard also happens to return 401" -- without the shape check, this script
# would report success even if verify_jwt had been silently flipped to
# false, as long as the handler's own guard still fired.
is_kong_shaped() {
  echo "$1" | grep -q '"msg"'
}

check_gated() {
  local name="$1" resp status body
  resp=$(curl -s -w '\n%{http_code}' -X POST "$URL/functions/v1/$name" \
    -H "content-type: application/json" -d '{}')
  status=$(echo "$resp" | tail -n1)
  body=$(echo "$resp" | sed '$d')

  if [[ "$status" != "401" ]]; then
    failures+=("$name: expected the GATEWAY to block with 401, got $status: $body")
    return
  fi
  if ! is_kong_shaped "$body"; then
    failures+=("$name: got 401 but body is not Kong's {\"msg\": ...} shape ($body) -- this looks like the HANDLER's own guard fired, not the gateway; verify_jwt may not be true for this function")
    return
  fi
  echo "  $name -> 401, Kong-shaped body -- gateway-blocked OK"
}

check_exempt() {
  local name="$1" resp status body
  resp=$(curl -s -w '\n%{http_code}' -X POST "$URL/functions/v1/$name" \
    -H "content-type: application/json" -d '{}')
  status=$(echo "$resp" | tail -n1)
  body=$(echo "$resp" | sed '$d')

  # Deliberately loose: today the stub returns 501. Task 3 will make GET
  # return a real page, and Task 4 will give POST real behaviour (200, or a
  # 4xx from confirm's OWN logic, e.g. an unknown token) -- any of those are
  # correct here, as long as Kong did not stop the request first. Pinning
  # the exact status would make this script fail the moment Task 3 or 4
  # lands, for a reason that has nothing to do with what it checks: whether
  # the gateway let the request through.
  if [[ "$status" == "401" ]] && is_kong_shaped "$body"; then
    failures+=("$name: looks GATEWAY-BLOCKED (401, Kong-shaped body: $body) but config.toml sets verify_jwt = false, so this request should reach the handler")
    return
  fi
  echo "  $name -> $status, not Kong-blocked -- gateway-exempt OK"
}

echo "Gateway checks (requires: supabase functions serve, WITHOUT --no-verify-jwt)"
echo "Target: $URL"
echo

for name in "${GATED[@]}"; do
  check_gated "$name"
done
check_exempt "$EXEMPT"

if [[ ${#failures[@]} -gt 0 ]]; then
  echo
  echo "FAILED:"
  for f in "${failures[@]}"; do
    echo "  - $f"
  done
  exit 1
fi

echo
echo "ok | 6 checked | 0 failed -- the 5 gated functions are still blocked at the gateway, confirm passes through"
