#!/usr/bin/env bash
# Admission-only verifier. All test bodies execute inside the pinned Oreslang guest.
# Never count source scans, an echoed ORES_TEST receipt, or zero-step Actions as guest evidence.
set -euo pipefail
export LC_ALL=C
die() { printf 'ORES_NATIVE_NOT_ACCEPTED: %s\n' "$*" >&2; exit 1; }
cd "$(dirname "$0")/.."
case "${EXPECTED_SOURCE_SHA:-}" in
  *[!0-9a-f]*|'') die "missing or invalid expected source SHA";;
esac
[[ "${#EXPECTED_SOURCE_SHA}" -eq 40 ]] || die "source SHA is not 40 hex bytes"
observed="$(git rev-parse --verify HEAD)" || die "source commit unavailable"
[[ "$observed" == "$EXPECTED_SOURCE_SHA" ]] || die "source commit mismatch"
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] || die "dirty tracked source or untracked checkout files"
for f in tests/native-harness-extended.ores vendor/oreslang/testing.ores ci/native-harness-cases.txt; do
  [[ -f "$f" && ! -L "$f" ]] || die "missing or symlink test artifact $f"
  git ls-files --error-unmatch -- "$f" >/dev/null || die "untracked test artifact $f"
done
case "${ORESLANG_BIN:-}" in /*) ;; *) die "ORESLANG_BIN must be an absolute path";; esac
[[ -f "$ORESLANG_BIN" && -x "$ORESLANG_BIN" && ! -L "$ORESLANG_BIN" ]] || die "compiler must be a regular executable"
case "${ORESLANG_COMPILER_SHA256:-}" in *[!0-9a-f]*|'') die "missing or invalid compiler SHA256";; esac
[[ "${#ORESLANG_COMPILER_SHA256}" -eq 64 ]] || die "compiler SHA256 must contain 64 hex digits"
if command -v sha256sum >/dev/null 2>&1; then
  fingerprint() { sha256sum "$ORESLANG_BIN" | cut -d ' ' -f 1; }
elif command -v shasum >/dev/null 2>&1; then
  fingerprint() { shasum -a 256 "$ORESLANG_BIN" | cut -d ' ' -f 1; }
else die "SHA256 utility missing"; fi
[[ "$(fingerprint)" == "$ORESLANG_COMPILER_SHA256" ]] || die "compiler bytes do not match configured digest"
limiter="$(command -v timeout || command -v gtimeout || true)"
[[ -n "$limiter" ]] || die "timeout/gtimeout unavailable"
tmp="$(mktemp -d)" || die "cannot create bounded test workspace"
trap 'rm -rf "$tmp"' EXIT
chmod 700 "$tmp"
"$limiter" -k 3s 15s "$ORESLANG_BIN" --build-info >"$tmp/build-info" 2>"$tmp/build-info.err" || die "compiler --build-info failed"
[[ "$(wc -c <"$tmp/build-info" | tr -d ' ')" -le 2048 ]] || die "oversized compiler identity"
grep -Fq '"guest_execution":' "$tmp/build-info" || die "compiler has no guest_execution identity"
"$limiter" -k 3s 30s "$ORESLANG_BIN" --check tests/native-harness-extended.ores >"$tmp/check.out" 2>"$tmp/check.err" || { cat "$tmp/check.err" >&2; die "Oreslang compiler check failed"; }
"$limiter" -k 3s 45s "$ORESLANG_BIN" tests/native-harness-extended.ores >"$tmp/guest.stdout" 2>"$tmp/guest.stderr" || { cat "$tmp/guest.stderr" >&2; die "Oreslang guest execution failed"; }
[[ "$(fingerprint)" == "$ORESLANG_COMPILER_SHA256" ]] || die "compiler changed during execution"
[[ ! -s "$tmp/guest.stderr" ]] || die "unexpected guest stderr; review diagnostic output separately"
[[ "$(wc -c <"$tmp/guest.stdout" | tr -d ' ')" -le 8192 ]] || die "guest stdout exceeded receipt limit"
[[ "$(wc -l <"$tmp/guest.stdout" | tr -d ' ')" -eq 7 ]] || die "guest stdout must contain exactly six PASS lines and one SUMMARY"
[[ "$(wc -l <ci/native-harness-cases.txt | tr -d ' ')" -eq 6 ]] || die "expected case count must be six"
[[ "$(LC_ALL=C sort -u ci/native-harness-cases.txt | wc -l | tr -d ' ')" -eq 6 ]] || die "duplicate expected case names"
[[ "$(grep -Ec '^[a-zA-Z0-9_/-]+$' ci/native-harness-cases.txt)" -eq 6 ]] || die "invalid expected case names"
awk -F'|' '$1=="ORES_TEST" && $2=="PASS" && NF==4 && $4=="" { print $3 }' "$tmp/guest.stdout" >"$tmp/actual-cases"
[[ "$(wc -l <"$tmp/actual-cases" | tr -d ' ')" -eq 6 ]] || die "missing, duplicate, or malformed PASS receipts"
LC_ALL=C sort ci/native-harness-cases.txt >"$tmp/expected"
LC_ALL=C sort "$tmp/actual-cases" >"$tmp/actual"
cmp -s "$tmp/expected" "$tmp/actual" || die "PASS case identities differ from reviewed manifest"
[[ "$(grep -Fxc 'ORES_TEST|SUMMARY|total=6|passed=6|failed=0|skipped=0|filtered=0' "$tmp/guest.stdout")" -eq 1 ]] || die "wrong or duplicate guest summary"
[[ "$(tail -n 1 "$tmp/guest.stdout")" == 'ORES_TEST|SUMMARY|total=6|passed=6|failed=0|skipped=0|filtered=0' ]] || die "SUMMARY must be the final guest event"
printf 'ORES_NATIVE_GUEST_PASS source_sha=%s compiler_sha256=%s cases=6\n' "$observed" "$ORESLANG_COMPILER_SHA256"
