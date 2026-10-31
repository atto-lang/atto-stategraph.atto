#!/bin/sh
# This script never treats static checks, interpreters, wrappers or zero-step
# GitHub Actions jobs as evidence that Oreslang guest code executed.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
die() { printf '%s\n' "SG_NATIVE_NOT_ACCEPTED: $*" >&2; exit 1; }
command -v git >/dev/null 2>&1 || die "git missing"
head="$(git rev-parse --verify HEAD)" || die "missing source commit"
case "$head" in *[!0123456789abcdef]* | '') die "invalid source commit";; esac
[ "${#head}" -eq 40 ] || die "invalid source SHA length"
if [ -n "${EXPECTED_SOURCE_SHA:-}" ] && [ "$head" != "$EXPECTED_SOURCE_SHA" ]; then
  die "source SHA mismatch (expected $EXPECTED_SOURCE_SHA, observed $head)"
fi
[ -z "$(git status --porcelain --untracked-files=normal -- src/ tests/native/ ci/native-cases.txt)" ] ||
  die "dirty source tree"
sh ci/audit-source.sh
case "${ORESLANG_BIN:-}" in /*) ;; *) die "set absolute ORESLANG_BIN";; esac
[ -x "$ORESLANG_BIN" ] && [ -f "$ORESLANG_BIN" ] && [ ! -L "$ORESLANG_BIN" ] ||
  die "trusted compiler executable unavailable"
case "${ORESLANG_COMPILER_SHA256:-}" in *[!0123456789abcdef]* | '') die "invalid pinned compiler SHA256";; esac
[ "${#ORESLANG_COMPILER_SHA256}" -eq 64 ] || die "invalid pinned SHA256 length"
if command -v sha256sum >/dev/null 2>&1; then
  digest="$(sha256sum "$ORESLANG_BIN" | cut -d ' ' -f 1)"
elif command -v shasum >/dev/null 2>&1; then
  digest="$(shasum -a 256 "$ORESLANG_BIN" | cut -d ' ' -f 1)"
else
  die "no SHA256 utility"
fi
[ "$digest" = "$ORESLANG_COMPILER_SHA256" ] || die "compiler digest mismatch"
limiter="$(command -v timeout || command -v gtimeout || true)"
[ -n "$limiter" ] || die "bounded timeout utility missing"
tmp="$(mktemp -d)" || die "cannot create private temp dir"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
chmod 700 "$tmp"
# Require real executable self-identification rather than inferring
# compiler capability from its pathname or wrapper script name.
"$limiter" --kill-after=3s 15s "$ORESLANG_BIN" --build-info >"$tmp/info" 2>"$tmp/info.err" ||
  die "compiler --build-info did not execute"
[ "$(wc -c < "$tmp/info" | tr -d ' ')" -le 2048 ] || die "oversized compiler build-info"
grep -Fq '"build_mode":' "$tmp/info" || die "compiler lacks build_mode attestation"
grep -Fq '"guest_execution":' "$tmp/info" || die "compiler lacks guest_execution attestation"
count=0
printf 'SG_NATIVE_BEGIN source_sha=%s compiler_sha256=%s\n' "$head" "$digest"
while IFS='|' read -r path expected || [ -n "$path" ]; do
  case "$path" in '' | \#*) continue;; tests/native/*.ores) ;; *) die "bad manifest path";; esac
  case "$path" in *[!a-z0-9./-]*) die "bad filename characters";; esac
  case "$expected" in '' | *[!a-z0-9:-]*) die "bad expected output";; esac
  [ -f "$path" ] && [ ! -L "$path" ] || die "case is missing or symlink"
  git ls-files --error-unmatch -- "$path" >/dev/null 2>&1 || die "untracked test"
  if grep -Fxq "$path" "$tmp/seen" 2>/dev/null; then die "duplicate test case"; fi
  printf '%s\n' "$path" >> "$tmp/seen"
  count=$((count + 1))
  [ "$count" -le 32 ] || die "test budget exceeded"
  "$limiter" --kill-after=3s 25s "$ORESLANG_BIN" --check "$path" >"$tmp/check.out" 2>"$tmp/check.err" ||
    { cat "$tmp/check.err" >&2; die "NATIVE_CHECK_FAIL $path"; }
  "$limiter" --kill-after=3s 25s "$ORESLANG_BIN" "$path" >"$tmp/actual" 2>"$tmp/run.err" ||
    { cat "$tmp/run.err" >&2; die "NATIVE_RUN_FAIL $path"; }
  [ "$(wc -c < "$tmp/actual" | tr -d ' ')" -le 1024 ] || die "oversized test output"
  printf '%s' "$expected" >"$tmp/expected"
  cmp -s "$tmp/actual" "$tmp/expected" || die "NATIVE_OUTPUT_FAIL $path"
  printf 'SG_NATIVE_CASE_PASS path=%s blob=%s\n' "$path" "$(git rev-parse "HEAD:$path")"
done <ci/native-cases.txt
tracked="$(git ls-files 'tests/native/*.ores' | wc -l | tr -d ' ')"
[ "$count" -eq 8 ] && [ "$tracked" -eq "$count" ] || die "manifest/source coverage mismatch"
printf 'SG_NATIVE_PASS count=%s source_sha=%s compiler_sha256=%s\n' "$count" "$head" "$digest"
