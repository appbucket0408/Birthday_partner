#!/usr/bin/env bash
# Fails if any tracked RUNNABLE file invokes `supabase config push` while
# config.toml still carries the test-OTP block.
#
# config.toml holds twelve real-format phone numbers whose OTP is a
# hardcoded "123456". `db push` does not touch config.toml; `config push`
# DOES, and would place those numbers on an internet-facing GoTrue. This
# project has already reproduced two account-takeover bugs on this surface.
#
# SCOPE IS THE WHOLE SUBTLETY HERE. The places that mention this command
# most are the ones FORBIDDING it: config.toml's own warning, the specs, the
# ledgers, the deploy runbook. A check that flagged prose would fail on the
# day it was written and be deleted by the first person it annoyed. So this
# searches only files that can actually execute -- shell, CI, Makefiles,
# package scripts -- and inside those, skips comment lines. Prose in docs/
# and .md is never matched, by design and not by oversight.
#
# This guards the REPO's contents. It cannot guard an operator's shell.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! grep -q '^\[auth.sms.test_otp\]' supabase/config.toml; then
  echo "note: no [auth.sms.test_otp] block; this check is moot."
  exit 0
fi

# git grep prints `path:lineno:content`; the filter drops content whose
# first non-space character starts a comment.
hits=$(git grep -n -- 'config push' -- \
         '*.sh' '*.bash' '*.zsh' '*.yml' '*.yaml' '*.mk' \
         'Makefile' 'justfile' 'package.json' '.github/**' \
         ':!supabase/check-no-config-push.sh' \
       | grep -vE ':[0-9]+:[[:space:]]*#' || true)

if [ -n "$hits" ]; then
  echo "FAIL: a runnable tracked file invokes 'supabase config push' while"
  echo "[auth.sms.test_otp] is present in supabase/config.toml."
  echo "$hits"
  exit 1
fi

echo "PASS: no runnable tracked file runs 'supabase config push'."
