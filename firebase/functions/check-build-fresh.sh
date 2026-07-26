#!/usr/bin/env bash
#
# Blocks `firebase deploy --only functions` when firebase/functions/lib is older
# than src.
#
# WHY THIS EXISTS. package.json `main` is `lib/index.js`, and the Firebase CLI
# uploads the functions directory AS-IS — it does not compile TypeScript. With no
# predeploy step, `firebase deploy --only functions` reports "Successful update
# operation" for every function while shipping whatever stale JS happens to be in
# lib/. That is not hypothetical: the recruitingViewDigest owner-grouping rewrite
# sat undeployed for weeks behind a series of green deploys, and the 2026-07-25
# review found it by comparing mtimes.
#
# The obvious fix — a predeploy that runs `npm run build` — does NOT work here.
# The CLI puts its own bundled pkg-built node ahead of the real one on PATH, and
# npm dies on it with "Cannot read properties of undefined (reading 'stdin')".
# So this guard only DETECTS staleness and tells you to build; it never builds.
#
# Two CLI quirks this file is shaped around, both learned the hard way:
#   1. A predeploy command containing "=" is silently NOT RUN (the CLI warns and
#      carries on), so a guard written inline can no-op without failing.
#   2. Inline commands with && and nested quotes get mangled by the CLI's arg
#      parsing. Hence a script file invoked with no quoting at all.
# Predeploy runs with the cwd set to the directory holding firebase.json, but
# this script resolves its own location so it works from anywhere.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$DIR/lib/index.js" ]; then
  printf '\nERROR: firebase/functions/lib/index.js does not exist.\n'
  printf '       The Firebase CLI does NOT compile TypeScript — it uploads lib/ as-is.\n'
  printf '       Run: cd firebase/functions && npm run build\n\n'
  exit 1
fi

STALE="$(find "$DIR/src" -name '*.ts' -newer "$DIR/lib/index.js" -print -quit 2>/dev/null)"
if [ -n "$STALE" ]; then
  printf '\nERROR: firebase/functions/lib is OLDER than src — this deploy would ship STALE code.\n'
  printf '       Newer source file: %s\n' "$STALE"
  printf '       The Firebase CLI does NOT compile TypeScript — it uploads lib/ as-is.\n'
  printf '       Run: cd firebase/functions && npm run build\n\n'
  exit 1
fi

echo "functions: lib/ is newer than src/ — build is current."
