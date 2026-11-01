#!/bin/sh
# Source-only integrity guard. It does NOT compile or execute guest Oreslang.
# Reject every tracked byte/mode mismatch, untracked or ignored file, and symlink.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
die() { printf 'SG_EXACT_TREE_REJECTED: %s\n' "$*" >&2; exit 1; }
command -v git >/dev/null 2>&1 || die "git missing"
expected="${EXPECTED_TREE_SHA:-}"
case "$expected" in '' | *[!0123456789abcdef]*) die "invalid EXPECTED_TREE_SHA";; esac
[ "${#expected}" -eq 40 ] || die "wrong tree SHA length"
observed="$(git rev-parse --verify 'HEAD^{tree}')" || die "HEAD has no tree"
[ "$observed" = "$expected" ] || die "HEAD tree mismatch"
if [ -n "${EXPECTED_SOURCE_SHA:-}" ]; then
  [ "$(git rev-parse --verify HEAD)" = "$EXPECTED_SOURCE_SHA" ] || die "source commit mismatch"
fi

# Ordinary git status may omit ignored data. Reject them too, before native
# compilation, so altered or hidden implementation inputs cannot get credit.
[ -z "$(git -c core.filemode=true status --porcelain=v1 --ignored --untracked-files=all)" ] ||
  die "dirty, untracked or ignored worktree"
links="$(find . -path './.git' -prune -o -type l -print)"
[ -z "$links" ] || die "symlinks in source worktree"

count=0
for path in $(git ls-files); do
  # Every supported repo path must be unambiguous in this POSIX-shell loop.
  case "$path" in '' | *[!a-zA-Z0-9._/-]*) die "unsupported tracked filename";; esac
  [ -f "$path" ] && [ ! -L "$path" ] || die "non-regular file $path"
  mode="$(git ls-files --stage -- "$path" | cut -d' ' -f1)"
  case "$mode" in
    100644) [ ! -x "$path" ] || die "unexpected executable bit $path" ;;
    100755) [ -x "$path" ] || die "missing executable bit $path" ;;
    *) die "unsafe tracked mode $path" ;;
  esac
  blob="$(git rev-parse "HEAD:$path")" || die "missing committed blob $path"
  actual="$(git hash-object --path="$path" "$path")" || die "cannot hash $path"
  [ "$blob" = "$actual" ] || die "worktree blob mismatch $path"
  count=$((count + 1))
  [ "$count" -le 4096 ] || die "excessive tracked files"
done
[ "$count" -ge 3 ] || die "unexpected empty source tree"
printf 'SG_EXACT_TREE_SOURCE_ONLY_PASS tree=%s tracked=%s\n' "$observed" "$count"
