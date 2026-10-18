#!/usr/bin/env bash
# Queue one test push for a member and drain it, to check a real device end to
# end without waiting for a birthday or a wish. Runbook:
# docs/superpowers/execution/2026-10-18-push-deploy-runbook.md.
#
#   SUPABASE_URL=https://<ref>.supabase.co \
#   SERVICE_ROLE_KEY=... \
#   DRAIN_SECRET=...            # optional; see below
#   ./supabase/functions/smoke-push.sh <profile-uuid> [reminder|wish] [--local]
#
# reminder  "It's <your name>'s birthday today", about the member's own person.
# wish      re-sends the newest real wish on their wall (post one first).
#
# With DRAIN_SECRET set, one drain runs immediately and its sent/failed counts
# are printed. Without it the row is only queued, and the */10 cron sends it.
#
# Refuses to run against 127.0.0.1/localhost unless --local is passed: the
# same keys work against both, and a smoke test aimed at the wrong stack
# "passes" while proving nothing about the one you meant.
#
# NEVER prints a secret. The keys reach curl through a 0600 header file, not
# argv -- anything on a command line is readable by every user via `ps`.
set -euo pipefail

usage() {
  echo "usage: SUPABASE_URL=... SERVICE_ROLE_KEY=... [DRAIN_SECRET=...] \\" >&2
  echo "       $0 <profile-uuid> [reminder|wish] [--local]" >&2
  exit 2
}

profile=""
kind="reminder"
local_ok=0
for arg in "$@"; do
  case "$arg" in
    --local) local_ok=1 ;;
    reminder|wish) kind="$arg" ;;
    -h|--help) usage ;;
    *)
      if [ -z "$profile" ]; then profile="$arg"; else usage; fi
      ;;
  esac
done

[ -n "$profile" ] || usage
# A uuid, and nothing else: it is interpolated into a JSON body below.
if ! [[ "$profile" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  echo "error: profile id must be a uuid (public.profiles.id)" >&2
  exit 2
fi
: "${SUPABASE_URL:?set SUPABASE_URL, e.g. https://<ref>.supabase.co}"
: "${SERVICE_ROLE_KEY:?set SERVICE_ROLE_KEY (Dashboard -> Project Settings -> API)}"

url="${SUPABASE_URL%/}"
host=$(printf '%s' "$url" | sed -E 's#^[a-zA-Z]+://##; s#[/:].*$##')
case "$host" in
  127.0.0.1|localhost|0.0.0.0|::1|\[::1\])
    if [ "$local_ok" -ne 1 ]; then
      echo "error: SUPABASE_URL points at $host. Pass --local to target the local stack." >&2
      exit 2
    fi
    ;;
esac

hdr=$(mktemp)
chmod 600 "$hdr"
body=$(mktemp)
trap 'rm -f "$hdr" "$body"' EXIT

printf 'apikey: %s\nAuthorization: Bearer %s\nContent-Type: application/json\n' \
  "$SERVICE_ROLE_KEY" "$SERVICE_ROLE_KEY" > "$hdr"

echo "queueing a '$kind' push for $profile on $host ..."
status=$(curl -sS -o "$body" -w '%{http_code}' -X POST \
  -H @"$hdr" \
  "$url/rest/v1/rpc/rpc_queue_test_push" \
  -d "{\"p_profile_id\":\"$profile\",\"p_kind\":\"$kind\"}")
if [ "$status" != "200" ]; then
  # PostgREST's error body is the function's own message (no secrets in it):
  # "no claimed person", "no wish by someone else", or a 401/404 meaning the
  # key or URL is wrong / the migration has not been pushed.
  echo "error: queue failed (HTTP $status): $(cat "$body")" >&2
  exit 1
fi
echo "queued outbox row $(cat "$body")"

if [ -z "${DRAIN_SECRET:-}" ]; then
  echo "DRAIN_SECRET not set: not draining now. The */10 cron will send it;"
  echo "check net._http_response afterwards (see the runbook)."
  exit 0
fi

printf 'x-drain-secret: %s\nContent-Type: application/json\n' "$DRAIN_SECRET" > "$hdr"
echo "triggering one drain ..."
status=$(curl -sS -o "$body" -w '%{http_code}' -X POST \
  -H @"$hdr" \
  "$url/functions/v1/drain_reminders" \
  -d '{}')
# The drain's body is counts only: {"dryRun":false,"sent":1,"failed":0}.
echo "drain HTTP $status: $(cat "$body")"
case "$status" in
  200) ;;
  401) echo "hint: DRAIN_SECRET does not match the function's DRAIN_SECRET secret." >&2; exit 1 ;;
  404) echo "hint: drain_reminders is not deployed at this URL." >&2; exit 1 ;;
  *) exit 1 ;;
esac
