#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
for t in test-lib.sh test-context.sh test-run.sh test-verify.sh test-merge.sh test-wave.sh test-ix.sh test-triad.sh; do
  [ -f "$t" ] || continue
  echo "== $t"; bash "$t" || exit 1
done
echo "ALL PASS"
