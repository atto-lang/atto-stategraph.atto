#!/bin/sh
# Source-only admission for native GraphRun ledger fixtures.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
die() { printf 'SG_RUN_LEDGER_SOURCE_FAIL: %s\n' "$*" >&2; exit 1; }
command -v git >/dev/null 2>&1 || die "git missing"
expected="${EXPECTED_SOURCE_SHA:-}"
[ -n "$expected" ] || die "source SHA missing"
[ "$(git rev-parse --verify HEAD)" = "$expected" ] || die "wrong source SHA"
[ -z "$(git -c core.filemode=true status --porcelain=v1 --ignored --untracked-files=all)" ] ||
  die "dirty, ignored or untracked worktree"
[ -z "$(find . -path './.git' -prune -o -type l -print)" ] ||
  die "symlink in source"
for path in src/run_ledger.ores tests/run-ledger.ores tests/run-cancellation.ores \
            tests/run-budget.ores ci/run-ledger-cases.txt ci/verify-run-ledger-native.sh; do
  [ -f "$path" ] && [ ! -L "$path" ] || die "missing or symlink file $path"
  git ls-files --error-unmatch -- "$path" >/dev/null 2>&1 || die "untracked file $path"
done
[ "$(git ls-files ':(glob)tests/run-*.ores' | wc -l | tr -d ' ')" -eq 3 ] ||
  die "guest case count changed"
[ "$(grep -c '^tests/run-.*\.ores|' ci/run-ledger-cases.txt)" -eq 3 ] ||
  die "manifest case count changed"
for marker in 'pub fnc start(' 'pub fnc enqueue(' 'pub fnc claim(' \
              'pub fnc publish(' 'pub fnc cancel(' 'pub fnc finish(' ; do
  grep -Fq "$marker" src/run_ledger.ores || die "missing lifecycle operation $marker"
done
if git grep -nE 'node:|child_process|require\(|eval\(|python3|import java:' -- 'src/*.ores' 'tests/run-*.ores'; then
  die "host fallback in guest source"
fi
printf 'SG_RUN_LEDGER_SOURCE_ONLY_PASS commit=%s\n' "$expected"
