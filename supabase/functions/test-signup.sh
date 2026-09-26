#!/usr/bin/env bash
# Email self-signup check: proves a stranger cannot create an account.
#
# WHY THIS IS A SCRIPT AND NOT A TEST. `[auth.email] enable_signup` is a
# GoTrue setting read from config.toml at container start. The Dart suites
# never touch the signup endpoint, and nothing in `supabase test db` can see
# a GoTrue env var -- so no automated suite in this repo can tell whether
# signup is open or closed. This is the same shape as
# `[functions.confirm] verify_jwt = false` in M3 Phase 1b, which
# test-gateway.sh covers for the same reason and in the same way.
#
# Consequence, stated plainly: a change to that setting is NOT test-covered.
# Run this after any edit to config.toml's [auth.email] block, and after any
# `supabase init` or CLI upgrade, both of which rewrite the whole file.
#
# WHY IT MATTERS. No path in this product needs email self-signup. Consumers
# arrive by phone OTP; staff accounts are provisioned by an administrator
# (admin.auth.admin.createUser, then a DBA `update profiles set is_staff`).
# Leaving signup open lets a stranger occupy an auth.users row with no
# `people` row behind it -- harmless in itself, since is_staff defaults false
# and every staff policy gates on private.is_staff(), but the project has no
# path to clean such rows up.
#
# Run with:
#   supabase start
#   ./supabase/functions/test-signup.sh
set -uo pipefail
cd "$(dirname "$0")/../.."

URL="${SUPABASE_URL:-http://127.0.0.1:54321}"

ANON="${SUPABASE_ANON_KEY:-}"
if [[ -z "$ANON" ]]; then
  # `supabase status -o json` breaks when any service is stopped (it prints a
  # plain-text preamble before the JSON), so parse the table instead.
  ANON=$(supabase status 2>/dev/null \
    | grep -i "publishable" \
    | awk -F'│' '{print $3}' \
    | tr -d ' ')
fi
if [[ -z "$ANON" ]]; then
  echo "FAILED: could not read the anon/publishable key. Is the stack up?"
  exit 1
fi

# A fixed prefix so Step 3's cleanup can find the row precisely, and a
# timestamp so a second run never collides with the first.
EMAIL="signupprobe+$(date +%s)@example.com"

resp=$(curl -s -w '\n%{http_code}' -X POST "$URL/auth/v1/signup" \
  -H "apikey: $ANON" \
  -H "content-type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"probe-password-123\"}")
status=$(echo "$resp" | tail -n1)
body=$(echo "$resp" | sed '$d')

echo "Email self-signup check"
echo "Target: $URL/auth/v1/signup"
echo "Probe:  $EMAIL"
echo

# A created user comes back 200 with an id (and, with confirmations off, an
# access_token). Checking the BODY and not just the status matters: GoTrue
# answers a refused signup with 4xx, but a misconfigured gateway could also
# 4xx for reasons that have nothing to do with this setting -- so a pass
# requires both "not 200" and "no user id in the body".
if [[ "$status" == "200" ]] || echo "$body" | grep -q '"id"'; then
  echo "FAILED: signup was ACCEPTED (status $status)."
  echo "  A stranger can create an account. Set [auth.email] enable_signup ="
  echo "  false in supabase/config.toml, then restart the stack:"
  echo "    supabase stop && supabase start"
  echo "  Body: $body"
  echo
  echo "  Clean up the row this probe created:"
  echo "    docker exec -i supabase_db_birthday_app psql -U postgres -c \\"
  echo "      \"delete from auth.users where email like 'signupprobe%';\""
  exit 1
fi

echo "  signup -> $status, no user created -- closed OK"
echo
echo "ok | 1 checked | 0 failed -- email self-signup is refused"
