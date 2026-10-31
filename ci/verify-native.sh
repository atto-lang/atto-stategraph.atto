#!/bin/sh
# Fail-closed Oreslang guest execution; a static check never emits SG_NATIVE_PASS.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
die() { printf 'SG_NATIVE_NOT_ACCEPTED %s\n' "$*" >&2; exit 1; }
command -v git >/dev/null 2>&1 || die "git missing"
tree="$(git rev-parse --verify 'HEAD^{tree}')" || die "Git tree missing"
expected="$(printenv EXPECTED_TREE_SHA || true)"
case "$expected" in ''|*[!0123456789abcdef]*) die "set a hex EXPECTED_TREE_SHA";; esac
[ "$(printf '%s' "$expected" | wc -c | tr -d ' ')" -eq 40 ] || die "bad tree SHA length"
[ "$tree" = "$expected" ] || die "wrong source Git tree"
[ -z "$(git status --porcelain --untracked-files=normal -- src/stategraph.ores tests/smoke.ores)" ] ||
  die "dirty source/test bytes"
for path in src/stategraph.ores tests/smoke.ores; do
  [ -f "$path" ] && [ ! -L "$path" ] || die "missing or symlinked file $path"
  git ls-files --error-unmatch -- "$path" >/dev/null 2>&1 || die "untracked $path"
  printf 'SG_NATIVE_SOURCE path=%s blob=%s\n' "$path" "$(git rev-parse "HEAD:$path")"
done
binary="$(printenv ORESLANG_BIN || true)"
case "$binary" in /*) ;; *) die "ORESLANG_BIN must be absolute";; esac
[ -f "$binary" ] && [ -x "$binary" ] && [ ! -L "$binary" ] || die "compiler unavailable"
digest="$(printenv ORESLANG_COMPILER_SHA256 || true)"
case "$digest" in ''|*[!0123456789abcdef]*) die "set a hex compiler SHA256";; esac
[ "$(printf '%s' "$digest" | wc -c | tr -d ' ')" -eq 64 ] || die "bad digest length"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$binary" | cut -d ' ' -f 1)"
elif command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$binary" | cut -d ' ' -f 1)"
else
  die "SHA256 utility unavailable"
fi
[ "$actual" = "$digest" ] || die "compiler digest mismatch"
limiter="$(command -v timeout || command -v gtimeout || true)"
[ -n "$limiter" ] || die "timeout utility unavailable"
printf 'SG_NATIVE_BEGIN tree=%s compiler_sha256=%s\n' "$tree" "$actual"
"$limiter" --kill-after=3s 90s "$binary" --check tests/smoke.ores ||
  die "compiler check failed"
"$limiter" --kill-after=3s 90s "$binary" tests/smoke.ores ||
  die "guest program failed"
printf 'SG_NATIVE_PASS tree=%s compiler_sha256=%s smoke_blob=%s\n' \
  "$tree" "$actual" "$(git rev-parse HEAD:tests/smoke.ores)"
