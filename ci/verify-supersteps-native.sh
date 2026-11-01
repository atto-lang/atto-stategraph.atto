#!/bin/sh
# Source SHA/tree-bound native Oreslang guest acceptance.
# Source-only checks and zero-step CI jobs NEVER count as native passes.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
die() { printf '%s\n' "SG_SUPERSTEPS_NATIVE_NOT_ACCEPTED: $*" >&2; exit 1; }
command -v git >/dev/null 2>&1 || die "git missing"
commit="$(git rev-parse --verify HEAD)" || die "no Git HEAD"
tree="$(git rev-parse --verify 'HEAD^{tree}')" || die "no source tree"
is_sha() {
  case "$1" in "" | *[!0123456789abcdef]*) return 1 ;; esac
  [ "${#1}" -eq 40 ]
}
is_sha "${EXPECTED_SOURCE_SHA:-}" || die "EXPECTED_SOURCE_SHA must be a full lowercase SHA"
is_sha "${EXPECTED_TREE_SHA:-}" || die "EXPECTED_TREE_SHA must be a full lowercase Git tree SHA"
[ "$commit" = "$EXPECTED_SOURCE_SHA" ] || die "source commit mismatch"
[ "$tree" = "$EXPECTED_TREE_SHA" ] || die "source tree mismatch"
# Do not accept modified, untracked, ignored, or symlinked source material.
[ -z "$(git status --porcelain --untracked-files=all -- src/ tests/ ci/)" ] ||
  die "source files are dirty or untracked"
ignored="$(git ls-files --others --ignored --exclude-standard -- src/ tests/ ci/)"
[ -z "$ignored" ] || die "ignored source files present"
sh ci/audit-source.sh
for file in src/supersteps.ores tests/smoke.ores ci/supersteps-cases.txt; do
  [ -f "$file" ] && [ ! -L "$file" ] || die "file missing or symlinked: $file"
  git ls-files --error-unmatch -- "$file" >/dev/null 2>&1 || die "untracked source: $file"
  printf 'SG_SOURCE_BLOB path=%s blob=%s\n' "$file" "$(git rev-parse "HEAD:$file")"
done

binary="${ORESLANG_BIN:-}"
case "$binary" in /*) ;; *) die "ORESLANG_BIN must be an absolute path" ;; esac
[ -f "$binary" ] && [ -x "$binary" ] && [ ! -L "$binary" ] ||
  die "compiler binary missing or symlinked"
digest="${ORESLANG_COMPILER_SHA256:-}"
case "$digest" in "" | *[!0123456789abcdef]*) die "invalid lowercase compiler SHA256" ;; esac
[ "${#digest}" -eq 64 ] || die "invalid compiler SHA256 length"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$binary" | cut -d ' ' -f 1)"
elif command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$binary" | cut -d ' ' -f 1)"
else
  die "SHA256 utility unavailable"
fi
[ "$actual" = "$digest" ] || die "compiler identity differs from pin"
limiter="$(command -v timeout || command -v gtimeout || true)"
[ -n "$limiter" ] || die "timeout utility unavailable"
tmp="$(mktemp -d)" || die "cannot create private temp directory"
chmod 700 "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

"$limiter" --kill-after=5s 15s "$binary" --build-info >"$tmp/info" 2>"$tmp/err" ||
  die "compiler --build-info failed"
[ "$(wc -c <"$tmp/info" | tr -d ' ')" -le 2048 ] || die "oversized compiler identity response"
grep -Fq '"build_mode":' "$tmp/info" || die "compiler build_mode attestation missing"
grep -Fq '"guest_execution":' "$tmp/info" || die "compiler guest_execution attestation missing"

printf 'SG_SUPERSTEPS_NATIVE_BEGIN source_sha=%s tree=%s compiler_sha256=%s\n' "$commit" "$tree" "$digest"
count=0
: >"$tmp/seen"
while IFS='|' read -r path expected || [ -n "$path" ]; do
  case "$path" in "" | \#*) continue ;;
    tests/smoke.ores | tests/supersteps/*.ores) ;;
    *) die "unrecognized test path $path" ;;
  esac
  case "$path" in *[!a-z0-9./-]*) die "invalid test path characters" ;; esac
  case "$expected" in "" | *[!A-Za-z0-9_-]*) die "invalid expected output" ;; esac
  [ -f "$path" ] && [ ! -L "$path" ] || die "missing/symlink test case $path"
  git ls-files --error-unmatch -- "$path" >/dev/null 2>&1 || die "untracked test $path"
  if grep -Fxq "$path" "$tmp/seen"; then die "duplicate test $path"; fi
  printf '%s\n' "$path" >>"$tmp/seen"
  count=$((count + 1))
  [ "$count" -le 32 ] || die "test case budget exceeded"
  "$limiter" --kill-after=5s 30s "$binary" --check "$path" >"$tmp/check.out" 2>"$tmp/check.err" ||
    { cat "$tmp/check.err" >&2; die "NATIVE_CHECK_FAILED $path"; }
  "$limiter" --kill-after=5s 30s "$binary" "$path" >"$tmp/output" 2>"$tmp/run.err" ||
    { cat "$tmp/run.err" >&2; die "NATIVE_EXEC_FAILED $path"; }
  [ "$(wc -c <"$tmp/output" | tr -d ' ')" -le 2048 ] || die "oversized guest output $path"
  printf '%s' "$expected" >"$tmp/expected"
  cmp -s "$tmp/output" "$tmp/expected" || die "guest output mismatch $path"
  printf 'SG_NATIVE_CASE_PASS path=%s blob=%s\n' "$path" "$(git rev-parse "HEAD:$path")"
done <ci/supersteps-cases.txt
total="$(git ls-files -- 'tests/smoke.ores' 'tests/supersteps/*.ores' | wc -l | tr -d ' ')"
[ "$count" -eq 5 ] && [ "$total" -eq "$count" ] ||
  die "manifest does not cover every native guest (checked=$count tracked=$total)"
printf 'SG_SUPERSTEPS_NATIVE_PASS count=%s source_sha=%s tree=%s compiler_sha256=%s\n' "$count" "$commit" "$tree" "$digest"
