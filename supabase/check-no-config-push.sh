#!/usr/bin/env bash
# Two checks on the test-OTP block in supabase/config.toml:
#
#   1. No tracked RUNNABLE file invokes `supabase config push`.
#   2. The number of test-OTP entries matches EXPECTED_TEST_OTP below.
#
# Why both. That block maps real-format Indian phone numbers to the hardcoded
# OTP "123456". `db push` does not touch config.toml; `config push` DOES, and
# would place every one of them on an internet-facing GoTrue as a working
# backdoor. This project has already reproduced two account-takeover bugs on
# this exact surface.
#
# The count check exists because the prose drifted: four numbers were added
# at some point while the spec, the runbook, this script and config.toml's
# own warning all still said "twelve" -- so the file and every description of
# it disagreed, silently, and the only reason anyone noticed was a code
# review. A number in a comment cannot police itself; this can. When the
# block legitimately changes, update EXPECTED_TEST_OTP in the same commit and
# the reviewer sees the delta.
#
# SCOPE OF CHECK 1 IS DELIBERATE. The places that mention `config push` most
# are the ones FORBIDDING it: config.toml's own warning, the specs, the
# ledgers, this runbook. A check that flagged prose would have failed the day
# it was written and been deleted by the first person it annoyed. So it
# searches only files that can execute, and skips comment lines inside them.
#
# This guards the REPO's contents. It cannot guard an operator's shell.
set -euo pipefail
cd "$(dirname "$0")/.."

EXPECTED_TEST_OTP=26

if ! grep -q '^\[auth.sms.test_otp\]' supabase/config.toml; then
  echo "note: no [auth.sms.test_otp] block; both checks are moot."
  exit 0
fi

# --- 1. nothing runs the command ----------------------------------------
# git grep prints `path:lineno:content`; the filter drops content whose first
# non-space character starts a comment.
# `--include-seed` and `reset --linked` are here too: either would send
# local_dev_otp.sql (any number signs in with "123456") to a hosted project.
hits=$(git grep -n -E -- 'config push|include-seed|reset --linked' -- \
         '*.sh' '*.bash' '*.zsh' '*.yml' '*.yaml' '*.mk' \
         'Makefile' 'justfile' 'package.json' '.github/**' \
         ':!supabase/check-no-config-push.sh' \
       | grep -vE ':[0-9]+:[[:space:]]*#' || true)

if [ -n "$hits" ]; then
  echo "FAIL: a runnable tracked file invokes 'supabase config push',"
  echo "'db push --include-seed' or 'db reset --linked' while local-only auth"
  echo "backdoors ([auth.sms.test_otp], local_dev_otp.sql) are in the repo."
  echo "$hits"
  exit 1
fi

# --- 2. the block is the size we think it is ----------------------------
actual=$(sed -n '/^\[auth.sms.test_otp\]/,/^\[/p' supabase/config.toml \
         | grep -cE '^[0-9]+ = ' || true)

if [ "$actual" -ne "$EXPECTED_TEST_OTP" ]; then
  echo "FAIL: [auth.sms.test_otp] has $actual entries, expected $EXPECTED_TEST_OTP."
  echo
  echo "Every entry is a working backdoor credential if this block ever"
  echo "reaches a hosted project. If the change is intended, update"
  echo "EXPECTED_TEST_OTP in this script in the same commit, so the delta is"
  echo "visible in review rather than buried in a config file."
  exit 1
fi

echo "PASS: nothing runs 'supabase config push'; test_otp has $actual entries."
