#!/bin/sh
# Native GraphRun ledger guest evidence. No host-language substitutes allowed.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
die() { printf 'SG_RUN_LEDGER_NOT_ACCEPTED: %s\n' "$*" >&2; exit 1; }
command -v git >/dev/null 2>&1 || die "git missing"
commit="$(git rev-parse --verify HEAD)" || die "no source commit"
tree="$(git rev-parse --verify 'HEAD^{tree}')" || die "no source tree"
[ "${EXPECTED_SOURCE_SHA:-}" = "$commit" ] || die "source commit mismatch"
[ "${EXPECTED_TREE_SHA:-}" = "$tree" ] || die "source tree mismatch"
[ -z "$(git -c core.filemode=true status --porcelain=v1 --ignored --untracked-files=all)" ] ||
  die "dirty, ignored or untracked working tree"
[ -z "$(find . -path './.git' -prune -o -type l -print)" ] ||
  die "symlink in source checkout"

case "${ORESLANG_BIN:-}" in /*) ;; *) die "absolute compiler path required";; esac
[ -f "$ORESLANG_BIN" ] && [ -x "$ORESLANG_BIN" ] && [ ! -L "$ORESLANG_BIN" ] ||
  die "compiler executable unavailable"
case "${ORESLANG_COMPILER_SHA256:-}" in
  '' | *[!0123456789abcdef]*) die "lowercase 64-character SHA256 required";;
esac
[ "${#ORESLANG_COMPILER_SHA256}" -eq 64 ] || die "invalid SHA256 length"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$ORESLANG_BIN" | cut -d ' ' -f1)"
elif command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$ORESLANG_BIN" | cut -d ' ' -f1)"
else
  die "SHA256 utility missing"
fi
[ "$actual" = "$ORESLANG_COMPILER_SHA256" ] || die "compiler digest mismatch"
limiter="$(command -v timeout || command -v gtimeout || true)"
[ -n "$limiter" ] || die "bounded timeout unavailable"
tmp="$(mktemp -d)" || die "cannot make isolated temp directory"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
chmod 700 "$tmp"

"$limiter" --kill-after=3s 15s "$ORESLANG_BIN" --build-info > "$tmp/build" 2> "$tmp/error" ||
  die "compiler --build-info failed"
[ "$(wc -c < "$tmp/build" | tr -d ' ')" -le 2048 ] ||
  die "oversized compiler build-info"
grep -Fq '"build_mode":' "$tmp/build" || die "missing build_mode identity"
grep -Fq '"guest_execution":' "$tmp/build" || die "missing guest_execution identity"
manifest="ci/run-ledger-cases.txt"
[ -f "$manifest" ] && [ ! -L "$manifest" ] || die "manifest missing or symlink"
git ls-files --error-unmatch -- "$manifest" >/dev/null 2>&1 ||
  die "untracked manifest"
count=0
: > "$tmp/seen"
: > "$tmp/cases"
printf 'SG_RUN_LEDGER_NATIVE_BEGIN commit=%s tree=%s compiler_sha256=%s\n' "$commit" "$tree" "$actual"
while IFS='|' read -r path expected || [ -n "$path" ]; do
  case "$path" in '' | \#*) continue;; tests/run-*.ores) ;; *) die "manifest path rejected";; esac
  case "$path" in *[!a-z0-9./-]*) die "manifest filename rejected";; esac
  case "$expected" in '' | *[!A-Z0-9_]*) die "manifest output rejected";; esac
  [ -f "$path" ] && [ ! -L "$path" ] || die "case file unavailable"
  git ls-files --error-unmatch -- "$path" >/dev/null 2>&1 || die "untracked case"
  grep -Fxq "$path" "$tmp/seen" && die "duplicate case"
  printf '%s\n' "$path" >> "$tmp/seen"
  printf '%s\n' "$path" >> "$tmp/cases"
  count=$((count + 1))
  [ "$count" -le 16 ] || die "case budget exceeded"
  "$limiter" --kill-after=3s 35s "$ORESLANG_BIN" --check "$path" > "$tmp/check" 2> "$tmp/check-err" ||
    { cat "$tmp/check-err" >&2; die "native compiler check failed for $path"; }
  "$limiter" --kill-after=3s 35s "$ORESLANG_BIN" "$path" > "$tmp/out" 2> "$tmp/run-err" ||
    { cat "$tmp/run-err" >&2; die "native guest execution failed for $path"; }
  [ "$(wc -c < "$tmp/out" | tr -d ' ')" -le 1024 ] || die "oversized guest output"
  printf '%s' "$expected" | cmp -s - "$tmp/out" || die "wrong guest output for $path"
  printf 'SG_RUN_LEDGER_NATIVE_CASE_PASS file=%s blob=%s\n' "$path" "$(git rev-parse "HEAD:$path")"
done < "$manifest"
[ "$count" -eq 14 ] || die "required cases missing"
git ls-files ':(glob)tests/run-*.ores' | sort > "$tmp/tracked"
sort "$tmp/cases" > "$tmp/manifest"
cmp -s "$tmp/tracked" "$tmp/manifest" || die "manifest/source mismatch"
printf 'SG_RUN_LEDGER_NATIVE_PASS count=14 commit=%s tree=%s compiler_sha256=%s\n' "$commit" "$tree" "$actual"
