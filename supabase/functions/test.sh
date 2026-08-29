#!/usr/bin/env bash
# Edge Function tests. Requires `supabase start` and `supabase functions serve`
# to already be running -- both are long-lived and this script does not own them.
set -euo pipefail
cd "$(dirname "$0")/../.."

SUPABASE_ANON_KEY=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
SUPABASE_SERVICE_ROLE_KEY=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["SERVICE_ROLE_KEY"])')
# add_celebrations/index.test.ts seeds a suppression directly over Postgres
# (there is no Edge Function that calls private.suppress_person), so the
# suite also needs a direct DB connection string, not just the API keys.
SUPABASE_DB_URL=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["DB_URL"])')
export SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY SUPABASE_DB_URL

deno test --allow-net --allow-env supabase/functions/
