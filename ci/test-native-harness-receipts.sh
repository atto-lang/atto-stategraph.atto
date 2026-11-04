#!/usr/bin/env bash
# HOST ONLY: synthetic receipt mutations are not native Oreslang guest executions.
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."
checker=ci/verify-native-harness-receipts.sh
manifest=ci/native-harness-cases.txt
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; chmod 700 "$tmp"
mapfile -t cases < "$manifest"
[[ ${#cases[@]} -eq 6 ]] || exit 1
base="$tmp/base.out"
for name in "${cases[@]}"; do printf 'ORES_TEST|PASS|%s|\n' "$name" >> "$base"; done
printf 'ORES_TEST|SUMMARY|total=6|passed=6|failed=0|skipped=0|filtered=0\n' >> "$base"
bash "$checker" "$manifest" "$base" >/dev/null
mutant="$tmp/mutant.out"
reject() {
  if bash "$checker" "$manifest" "$mutant" > "$tmp/check.out" 2> "$tmp/check.err"; then
    printf 'HOST_RECEIPT_MUTATION_MISSED: %s\n' "$1" >&2; exit 1
  fi
}
cp "$base" "$mutant"; sed -i "1s@${cases[0]}@${cases[1]}@" "$mutant"; reject duplicate_case
cp "$base" "$mutant"; sed -i '1d' "$mutant"; reject missing_case
cp "$base" "$mutant"; sed -i '1s@PASS@FAIL@' "$mutant"; reject fail_event
cp "$base" "$mutant"; sed -i '1s@PASS@SKIP@' "$mutant"; reject skip_event
cp "$base" "$mutant"; sed -i '1s@PASS|@PASS|unexpected/@' "$mutant"; reject unexpected_id
cp "$base" "$mutant"; sed -i '1s@|$@@' "$mutant"; reject missing_pipe
cp "$base" "$mutant"; sed -i '1s@|$@|unexpected@' "$mutant"; reject detail
cp "$base" "$mutant"; sed -i '1s@|$@||@' "$mutant"; reject extra_pipe
cp "$base" "$mutant"; sed -i '7s@passed=6@passed=5@' "$mutant"; reject incorrect_summary
cp "$base" "$mutant"; sed -i '7s@filtered=0@filtered=1@' "$mutant"; reject filtered_summary
cp "$base" "$mutant"; sed -i '7d' "$mutant"; reject missing_summary
cp "$base" "$mutant"; sed -i '7i ORES_TEST|SUMMARY|total=6|passed=6|failed=0|skipped=0|filtered=0' "$mutant"; reject duplicate_summary
cp "$base" "$mutant"; sed -i '1i ORES_TEST|SUMMARY|total=6|passed=6|failed=0|skipped=0|filtered=0' "$mutant"; reject early_summary
cp "$base" "$mutant"; sed -i '1i ALIEN_OUTPUT' "$mutant"; reject alien_output
cp "$base" "$mutant"; sed -i '1s@^@\x1b[31m@' "$mutant"; reject ansi_output
cp "$base" "$mutant"; sed -i '1s@$@\r@' "$mutant"; reject CR_output
cp "$base" "$mutant"; sed -i '1s@|$@\x00|@' "$mutant"; reject NUL_output
cp "$base" "$mutant"; truncate -s -1 "$mutant"; reject missing_final_LF
cp "$base" "$mutant"; printf '\n' >> "$mutant"; reject extra_blank
cp "$manifest" "$tmp/oracle"; sed -i "1s@${cases[0]}@${cases[1]}@" "$tmp/oracle"
if bash "$checker" "$tmp/oracle" "$base" >/dev/null 2>&1; then echo 'HOST_RECEIPT_MUTATION_MISSED: duplicate_oracle' >&2; exit 1; fi
cp "$manifest" "$tmp/oracle"; sed -i '1d' "$tmp/oracle"
if bash "$checker" "$tmp/oracle" "$base" >/dev/null 2>&1; then echo 'HOST_RECEIPT_MUTATION_MISSED: short_oracle' >&2; exit 1; fi
printf 'HOST_ONLY_RECEIPT_MUTATIONS_PASS cases=21; NOT_COMPILER_EXECUTION\n'
