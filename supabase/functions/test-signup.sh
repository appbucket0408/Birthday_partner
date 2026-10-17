#!/usr/bin/env bash
# Email sign-up check: an email account can be created, but cannot claim a
# person until it has also verified a phone.
#
# WHY THIS IS A SCRIPT AND NOT A TEST. `[auth.email] enable_signup` is a
# GoTrue setting read from config.toml at container start, and nothing in
# `supabase test db` can see a GoTrue env var. The Dart contract suite
# test/repositories/auth_email_test.dart covers the same path through the
# app's own repository; this checks the raw endpoints with no app code in
# between, the same arrangement test-gateway.sh provides for verify_jwt.
#
# Run this after any edit to config.toml's [auth.email] block or its email
# templates, and after any `supabase init` or CLI upgrade, both of which
# rewrite the whole file.
#
# WHY IT MATTERS. Email sign-up is open (consumers may sign in by email). What
# keeps an email account harmless is that claim_profile refuses any session
# without a verified phone -- so an account that never links one has no
# person, no graph, and nothing social it can do. If that refusal ever stops
# holding, an email account could become a person without proving it owns
# the number behind it.
#
# Run with:
#   supabase start
#   ./supabase/functions/test-signup.sh
set -uo pipefail
cd "$(dirname "$0")/../.."

URL="${SUPABASE_URL:-http://127.0.0.1:54321}"
MAILPIT="${MAILPIT_URL:-http://127.0.0.1:54324}"

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

# A fixed prefix so cleanup can find the row precisely, and a timestamp so a
# second run never collides with the first.
EMAIL="signupprobe+$(date +%s)@example.com"

cleanup() {
  docker exec -i supabase_db_birthday_app psql -U postgres -qtAc \
    "delete from auth.users where email like 'signupprobe%';" >/dev/null 2>&1
}
trap cleanup EXIT

echo "Email sign-up check"
echo "Probe: $EMAIL"
echo

# 1. Ask for a code. Sign-up is open, so this must create the account.
status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL/auth/v1/otp" \
  -H "apikey: $ANON" -H "content-type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"create_user\":true}")
if [[ "$status" != "200" ]]; then
  echo "FAILED: requesting an email code returned $status."
  echo "  Is [auth.email] enable_signup = true in supabase/config.toml?"
  exit 1
fi
echo "  1. code requested -> 200"

# 2. Read the code from Mailpit. It must be a 6-digit CODE, not a magic
#    link: the app has no deep-link handling for one.
code=""
for _ in $(seq 1 20); do
  id=$(curl -s "$MAILPIT/api/v1/search?query=to:$EMAIL" \
    | python3 -c 'import sys,json;m=json.load(sys.stdin)["messages"];print(m[0]["ID"] if m else "")')
  if [[ -n "$id" ]]; then
    code=$(curl -s "$MAILPIT/api/v1/message/$id" \
      | python3 -c 'import sys,json,re;m=re.search(r"\b(\d{6})\b",json.load(sys.stdin)["Text"]);print(m.group(1) if m else "")')
    break
  fi
  sleep 0.25
done
if [[ -z "$code" ]]; then
  echo "FAILED: no 6-digit code in the mail to $EMAIL."
  echo "  Check the [auth.email.template.*] blocks point at"
  echo "  supabase/templates/email_otp.html, then restart the stack."
  exit 1
fi
echo "  2. mailed a 6-digit code"

# 3. Verify it: a real session for an email-only account.
token=$(curl -s -X POST "$URL/auth/v1/verify" \
  -H "apikey: $ANON" -H "content-type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"token\":\"$code\",\"type\":\"email\"}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
if [[ -z "$token" ]]; then
  echo "FAILED: the mailed code did not verify."
  exit 1
fi
echo "  3. code verified -> session"

# 4. THE CHECK: that session must not be able to claim a person.
resp=$(curl -s -w '\n%{http_code}' -X POST "$URL/functions/v1/claim_profile" \
  -H "Authorization: Bearer $token" -H "apikey: $ANON")
status=$(echo "$resp" | tail -n1)
body=$(echo "$resp" | sed '$d')
if [[ "$status" == "200" ]] || echo "$body" | grep -q '"person_id"'; then
  echo "FAILED: an email account with NO verified phone claimed a person."
  echo "  Body: $body"
  exit 1
fi
echo "  4. claim without a phone -> $status, refused OK"
echo
echo "ok | 4 checked | 0 failed -- email sign-up works and cannot claim without a phone"
