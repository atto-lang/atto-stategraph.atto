#!/bin/sh
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
fail() { printf '%s\n' "SG_SOURCE_POLICY_FAIL: $*" >&2; exit 1; }
command -v git >/dev/null 2>&1 || fail "git not installed"
for p in src/supersteps.ores tests/smoke.ores tests/supersteps/resume.ores tests/supersteps/topology.ores tests/supersteps/allowlist.ores tests/supersteps/patch-validation.ores ci/supersteps-cases.txt ci/verify-supersteps-native.sh src/stategraph.ores src/builder.ores src/patches.ores tests/native/builder-compile.ores tests/native/builder-entry.ores tests/native/step-budgets.ores tests/native/patch-batch.ores tests/native/patch-admission.ores tests/native/invalid-boundaries.ores tests/native/missing-outgoing.ores tests/native/conditional.ores tests/native/bounded-loop.ores tests/native/invalid-graphs.ores tests/native/route-errors.ores ci/native-cases.txt ci/verify-native.sh docs/IMPLEMENTATION.md; do
  git ls-files --error-unmatch -- "$p" >/dev/null 2>&1 || fail "untracked source $p"
  [ -f "$p" ] && [ ! -L "$p" ] || fail "not regular source $p"
done
bad="$(git ls-files | grep -E '(^|/)(package(-lock)?\.json|[^/]+\.(py|pyi|ipynb|js|jsx|mjs|cjs|ts|tsx))$' || true)"
[ -z "$bad" ] || fail "disallowed host implementation: $bad"
[ "$(git ls-files 'tests/native/*.ores' | wc -l | tr -d ' ')" -eq 11 ] || fail "native case drift"
[ "$(grep -c '^tests/native/.*\.ores|' ci/native-cases.txt)" -eq 11 ] || fail "manifest case drift"
[ "$(git ls-files 'tests/supersteps/*.ores' | wc -l | tr -d ' ')" -eq 4 ] || fail "superstep fixtures missing"
[ "$(grep -c '^tests/.*\.ores|' ci/supersteps-cases.txt)" -eq 5 ] || fail "superstep manifest drift"
if git grep -nE 'child_process|require\(|eval\(|node:|npm run' -- '*.ores'; then
  fail "host-execution escape in Oreslang source"
fi
printf '%s\n' 'SG_SOURCE_POLICY_PASS (source-only; no native guest claims)'
