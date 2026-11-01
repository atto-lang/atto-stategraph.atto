#!/bin/sh
# Fail-closed, exact-head native Oreslang acceptance. No interpreter or static
# source check may emit a native PASS. A fabricated compiler cannot be ruled
# out by this script alone: operator MUST attest executable origin and digest.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
die() { printf 'SG_SUPERSTEPS_NATIVE_NOT_ACCEPTED: %s\n' "$*" >&2; exit 1; }
sh ci/verify-exact-tree.sh || die "physical source integrity failed"
case "${ORESLANG_BIN:-}" in /*) ;; *) die "compiler path must be absolute";; esac
[ -f "$ORESLANG_BIN" ] && [ -x "$ORESLANG_BIN" ] && [ ! -L "$ORESLANG_BIN" ] ||
  die "trusted compiler unavailable"
case "${ORESLANG_COMPILER_SHA256:-}" in
  '' | *[!0123456789abcdef]*) die "compiler digest must be lowercase SHA256";;
esac
[ "${#ORESLANG_COMPILER_SHA256}" -eq 64 ] || die "invalid digest length"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$ORESLANG_BIN" | cut -d ' ' -f1)"
elif command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$ORESLANG_BIN" | cut -d ' ' -f1)"
else
  die "SHA256 utility missing"
fi
[ "$actual" = "$ORESLANG_COMPILER_SHA256" ] || die "compiler digest mismatch"
limiter="$(command -v timeout || command -v gtimeout || true)"
[ -n "$limiter" ] || die "bounded timeout utility unavailable"
tmp="$(mktemp -d)" || die "temporary directory unavailable"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
chmod 700 "$tmp"

"$limiter" --kill-after=3s 15s "$ORESLANG_BIN" --build-info > "$tmp/build-info" 2> "$tmp/build-err" ||
  die "compiler --build-info did not execute"
[ "$(wc -c < "$tmp/build-info" | tr -d ' ')" -le 2048 ] ||
  die "oversized compiler build-info"
grep -Fq '"build_mode":' "$tmp/build-info" || die "missing compiler build_mode"
grep -Fq '"guest_execution":' "$tmp/build-info" || die "missing compiler guest_execution"

manifest="ci/supersteps-native-cases.txt"
[ -f "$manifest" ] && [ ! -L "$manifest" ] || die "missing case manifest"
git ls-files --error-unmatch -- "$manifest" >/dev/null 2>&1 || die "untracked manifest"
count=0
: > "$tmp/seen"
: > "$tmp/expected-paths"
printf 'SG_SUPERSTEPS_NATIVE_BEGIN source_sha=%s tree=%s compiler_sha256=%s\n' \
  "$(git rev-parse HEAD)" "$(git rev-parse 'HEAD^{tree}')" "$actual"
while IFS='|' read -r path expected || [ -n "$path" ]; do
  case "$path" in '' | \#*) continue;; tests/*.ores) ;; *) die "invalid manifest path $path";; esac
  case "$path" in *[!a-z0-9./-]*) die "unsafe manifest path";; esac
  case "$expected" in '' | *[!A-Z0-9_]*) die "invalid expected output";; esac
  [ -f "$path" ] && [ ! -L "$path" ] || die "test missing/symlinked"
  git ls-files --error-unmatch -- "$path" >/dev/null 2>&1 || die "untracked test"
  if grep -Fxq "$path" "$tmp/seen"; then die "duplicate manifest test"; fi
  printf '%s\n' "$path" >> "$tmp/seen"
  printf '%s\n' "$path" >> "$tmp/expected-paths"
  count=$((count + 1))
  [ "$count" -le 16 ] || die "manifest budget exceeded"
  "$limiter" --kill-after=4s 50s "$ORESLANG_BIN" --check "$path" > "$tmp/check" 2> "$tmp/check-error" ||
    { cat "$tmp/check-error" >&2; die "compiler check failed for $path"; }
  "$limiter" --kill-after=4s 50s "$ORESLANG_BIN" "$path" > "$tmp/out" 2> "$tmp/run-error" ||
    { cat "$tmp/run-error" >&2; die "native guest failed for $path"; }
  [ "$(wc -c < "$tmp/out" | tr -d ' ')" -le 1024 ] || die "guest output too large"
  printf '%s' "$expected" | cmp -s - "$tmp/out" || die "wrong guest stdout for $path"
  printf 'SG_SUPERSTEPS_NATIVE_CASE_PASS file=%s blob=%s\n' "$path" \
    "$(git rev-parse "HEAD:$path")"
done < "$manifest"
[ "$count" -eq 4 ] || die "missing or extra native cases"
git ls-files ':(glob)tests/*.ores' | sort > "$tmp/tracked-paths"
sort "$tmp/expected-paths" > "$tmp/manifest-paths"
cmp -s "$tmp/tracked-paths" "$tmp/manifest-paths" || die "manifest does not cover all native superstep guests"
printf 'SG_SUPERSTEPS_NATIVE_PASS count=%s tree=%s source_sha=%s compiler_sha256=%s\n' \
  "$count" "$(git rev-parse 'HEAD^{tree}')" "$(git rev-parse HEAD)" "$actual"
