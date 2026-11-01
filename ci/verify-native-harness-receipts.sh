#!/usr/bin/env bash
# HOST-SIDE RECEIPT SHAPE CHECKER ONLY; text is never compiler/guest proof.
set -euo pipefail
export LC_ALL=C
fail() { printf 'ORES_RECEIPT_REJECTED: %s\n' "$*" >&2; exit 1; }
[[ $# -eq 2 ]] || fail 'usage: verify-native-harness-receipts.sh MANIFEST STDOUT'
manifest=$1; output=$2
[[ -f "$manifest" && -f "$output" && ! -L "$manifest" && ! -L "$output" ]] || fail 'missing/symlinked input'
[[ $(wc -l < "$manifest") -eq 6 && $(wc -c < "$manifest") -le 1024 ]] || fail 'wrong manifest size'
[[ $(grep -Ec '^[a-zA-Z0-9_/-]+$' "$manifest") -eq 6 ]] || fail 'invalid manifest names'
[[ $(sort -u "$manifest" | wc -l) -eq 6 ]] || fail 'duplicate manifest entries'
[[ $(wc -c < "$output") -le 8192 && $(wc -l < "$output") -eq 7 ]] || fail 'wrong stdout size/count'
[[ $(tail -c 1 "$output" | od -An -tu1 | tr -d '[:space:]') == 10 ]] || fail 'missing final newline'
if LC_ALL=C grep -q '[^ -~]' "$output"; then fail 'control or non-ASCII output'; fi
summary='ORES_TEST|SUMMARY|total=6|passed=6|failed=0|skipped=0|filtered=0'
[[ $(tail -n 1 "$output") == "$summary" ]] || fail 'summary must be exact final line'
tmp=$(mktemp -d) || fail 'no temp directory'
trap 'rm -rf "$tmp"' EXIT
chmod 700 "$tmp"
awk -F '|' -v summary="$summary" '
  NR == 7 { if ($0 != summary) exit 1; next }
  NR < 7 {
    if (NF != 4 || $1 != "ORES_TEST" || $2 != "PASS" || $3 !~ /^[A-Za-z0-9_\/-]+$/ || $4 != "") exit 1
    print $3
    next
  }
  { exit 1 }
' "$output" > "$tmp/observed" || fail 'malformed receipt event'
sort "$manifest" > "$tmp/expected"
sort "$tmp/observed" > "$tmp/actual"
cmp -s "$tmp/expected" "$tmp/actual" || fail 'missing, duplicate, or unexpected case IDs'
