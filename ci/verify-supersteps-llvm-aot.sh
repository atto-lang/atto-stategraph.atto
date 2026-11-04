#!/bin/sh
# LLVM-specific AOT acceptance: Oreslang source -> REAL LLVM IR -> Clang -> guest.
# Never execute an LLVM IR-emitting compiler as though it were a guest interpreter.
# No fallback, no mock backend, and no cross-repository source download.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
die() { printf 'SG_LLVM_AOT_NOT_ACCEPTED: %s\n' "$*" >&2; exit 1; }
sh ci/verify-exact-tree.sh || die "source/tree integrity check failed"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum unavailable"
limiter="$(command -v timeout || true)"
[ -n "$limiter" ] || die "timeout unavailable"
compiler="$(printenv ORESLANG_LLVM_BIN || true)"
clang="$(printenv SG_CLANG_BIN || true)"
expected_compiler="$(printenv ORESLANG_COMPILER_SHA256 || true)"
expected_clang="$(printenv SG_CLANG_SHA256 || true)"
for binary in "$compiler" "$clang"; do
  case "$binary" in /*) ;; *) die "compiler and clang must be absolute paths";; esac
  [ -x "$binary" ] && [ -f "$binary" ] && [ ! -L "$binary" ] ||
    die "compiler or clang unavailable or symlinked"
done
for digest in "$expected_compiler" "$expected_clang"; do
  case "$digest" in "" | *[!0123456789abcdef]*) die "invalid pinned tool SHA256";; esac
  [ "$(printf '%s' "$digest" | wc -c | tr -d ' ')" -eq 64 ] ||
    die "wrong pinned SHA256 length"
done
compiler_sha="$(sha256sum "$compiler" | cut -d ' ' -f1)"
clang_sha="$(sha256sum "$clang" | cut -d ' ' -f1)"
[ "$compiler_sha" = "$expected_compiler" ] || die "wrong LLVM compiler binary"
[ "$clang_sha" = "$expected_clang" ] || die "wrong Clang binary"

# Optional prebuilt native runtime archive for Array/String/record/stdio helpers.
# It must be provided and pinned as a single reviewed library, never downloaded
# from the tested PR, and there are no ambient linker/search-path fallbacks.
archive="$(printenv SG_LLVM_RUNTIME_ARCHIVE || true)"
archive_pin="$(printenv SG_LLVM_RUNTIME_SHA256 || true)"
if [ -n "$archive" ] || [ -n "$archive_pin" ]; then
  case "$archive" in /*.a) ;; *) die "runtime archive must be absolute .a";; esac
  [ -f "$archive" ] && [ ! -L "$archive" ] || die "unsafe runtime archive"
  case "$archive_pin" in "" | *[!0123456789abcdef]*) die "invalid runtime archive SHA256";; esac
  [ "$(printf '%s' "$archive_pin" | wc -c | tr -d ' ')" -eq 64 ] ||
    die "wrong runtime archive SHA256 length"
  [ "$(sha256sum "$archive" | cut -d ' ' -f1)" = "$archive_pin" ] ||
    die "runtime archive digest mismatch"
fi

tmp="$(mktemp -d)" || die "cannot create temporary directory"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
chmod 700 "$tmp"
manifest=ci/supersteps-native-cases.txt
[ -f "$manifest" ] && [ ! -L "$manifest" ] || die "missing fixture manifest"
git ls-files --error-unmatch -- "$manifest" >/dev/null 2>&1 ||
  die "untracked fixture manifest"
: > "$tmp/seen"
count=0
printf 'SG_LLVM_AOT_BEGIN tree=%s compiler_sha256=%s clang_sha256=%s\n' \
  "$(git rev-parse 'HEAD^{tree}')" "$compiler_sha" "$clang_sha"
while IFS='|' read -r path expected || [ -n "$path" ]; do
  case "$path" in '' | \#*) continue;; tests/*.ores) ;; *) die "unsafe case path";; esac
  case "$path" in *[!a-zA-Z0-9._/-]*) die "unsafe source characters";; esac
  case "$expected" in '' | *[!A-Z0-9_]*) die "unsafe expected guest stdout";; esac
  [ -s "$path" ] && [ ! -L "$path" ] || die "missing or symlinked guest"
  git ls-files --error-unmatch -- "$path" >/dev/null 2>&1 || die "untracked guest"
  if grep -Fxq "$path" "$tmp/seen"; then die "duplicate guest"; fi
  printf '%s\n' "$path" >> "$tmp/seen"
  count=$((count + 1))
  [ "$count" -le 16 ] || die "fixture count overflow"
  blob="$(git rev-parse "HEAD:$path")"
  [ "$(git hash-object "$path")" = "$blob" ] || die "guest source blob drift"
  ir="$tmp/case-$count.ll"
  executable="$tmp/case-$count"
  "$limiter" --kill-after=3s 90s "$compiler" --target=host "$path" > "$ir" 2> "$tmp/compiler.err" ||
    { cat "$tmp/compiler.err" >&2; die "Oreslang LLVM source lowering failed for $path"; }
  [ -s "$ir" ] && grep -q 'define .*@main(' "$ir" ||
    die "compiler emitted no native main definition"
  if [ -n "$archive" ]; then
    "$limiter" --kill-after=3s 90s "$clang" -O2 -x ir "$ir" -x none "$archive" -pthread -o "$executable" 2> "$tmp/clang.err" ||
      { cat "$tmp/clang.err" >&2; die "LLVM native runtime link failed for $path"; }
  else
    "$limiter" --kill-after=3s 90s "$clang" -O2 -x ir "$ir" -o "$executable" 2> "$tmp/clang.err" ||
      { cat "$tmp/clang.err" >&2; die "LLVM guest link failed for $path (runtime archive may be required)"; }
  fi
  [ -x "$executable" ] || die "Clang did not produce an executable"
  "$limiter" --kill-after=3s 60s "$executable" > "$tmp/stdout" 2> "$tmp/stderr" ||
    { cat "$tmp/stderr" >&2; die "LLVM AOT guest failed for $path"; }
  [ ! -s "$tmp/stderr" ] || die "unexpected guest stderr"
  printf '%s' "$expected" | cmp -s - "$tmp/stdout" ||
    die "wrong native guest stdout for $path"
  printf 'SG_LLVM_AOT_CASE_PASS file=%s blob=%s guest_exit=0\n' "$path" "$blob"
done < "$manifest"
[ "$count" -eq 4 ] || die "missing native superstep cases"
printf 'SG_LLVM_AOT_PASS count=%s tree=%s compiler_sha256=%s clang_sha256=%s\n' \
  "$count" "$(git rev-parse 'HEAD^{tree}')" "$compiler_sha" "$clang_sha"
