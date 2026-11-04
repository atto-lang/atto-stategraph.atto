#!/bin/sh
# Canonical shared Oreslang portable StateGraph source-contract verifier.
# SOURCE ONLY: never report compiler/backend support or guest execution.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
die() { printf 'SG_PORTABILITY_SOURCE_REJECTED: %s\n' "$*" >&2; exit 1; }
root=contracts/stategraph-portability/v1
manifest="$root/manifest.txt"
command -v git >/dev/null 2>&1 || die "git unavailable"
[ -f "$manifest" ] && [ ! -L "$manifest" ] || die "manifest missing or symlinked"
if [ -n "${EXPECTED_SOURCE_SHA:-}" ]; then
  [ "$(git rev-parse --verify HEAD)" = "$EXPECTED_SOURCE_SHA" ] ||
    die "wrong checkout head"
fi
[ -z "$(git status --porcelain=v1 --untracked-files=all -- "$root" ci/verify-stategraph-portability.sh)" ] ||
  die "dirty/untracked portability files"
[ -z "$(find "$root" -type l -print)" ] || die "symlinks in portability profile"
tmp="$(mktemp -d)" || die "cannot allocate private verifier dir"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
: > "$tmp/seen"
: > "$tmp/cases"
count=0
while IFS='|' read -r id filename feature expected pinned || [ -n "$id" ]; do
  case "$id" in ''|\#*) continue;; esac
  case "$id" in *[!a-z0-9-]*) die "unsafe fixture id";; esac
  case "$filename" in
    0[0-8]-*.ores) ;;
    *) die "unexpected fixture path" ;;
  esac
  case "$filename" in *[!a-zA-Z0-9._-]*) die "unsafe fixture filename";; esac
  case "$pinned" in ''|*[!a-f0-9]*) die "missing pinned Git blob SHA";; esac
  [ "${#pinned}" -eq 40 ] || die "invalid Git blob length"
  case "$feature" in ''|*[!a-z0-9_]*) die "unsafe semantic label";; esac
  case "$expected" in ''|*[!A-Z_a-z0-9]*) die "unsafe expected result";; esac
  grep -Fxq "$id" "$tmp/seen" && die "duplicate requirement $id"
  printf '%s\n' "$id" >> "$tmp/seen"
  path="$root/$filename"
  [ -f "$path" ] && [ ! -L "$path" ] || die "missing Oreslang probe $path"
  git ls-files --error-unmatch -- "$path" >/dev/null 2>&1 || die "untracked source $path"
  observed="$(git hash-object "$path")" || die "cannot hash $path"
  [ "$observed" = "$pinned" ] || die "canonical source blob mismatch $path"
  [ "$(git rev-parse "HEAD:$path")" = "$pinned" ] || die "Git index/head mismatch $path"
  printf '%s\n' "$path" >> "$tmp/cases"
  count=$((count + 1))
done < "$manifest"
[ "$count" -eq 9 ] || die "expected nine feature probes"
support="$root/graph_support.ores"
[ -f "$support" ] && [ ! -L "$support" ] || die "missing linked namespace module"
[ "$(git hash-object "$support")" = "174cfd9b258a626bc08136ac148148a5032e4075" ] ||
  die "canonical support blob mismatch"
printf '%s\n' "$support" >> "$tmp/cases"
git ls-files ':(glob)contracts/stategraph-portability/v1/*.ores' | sort > "$tmp/actual"
sort "$tmp/cases" > "$tmp/expected"
cmp -s "$tmp/actual" "$tmp/expected" || die "unlisted or missing Oreslang source"
shared=contracts/stategraph-portability/shared-scalar.ores
[ -f "$shared" ] && [ ! -L "$shared" ] || die "canonical shared scalar missing or symlinked"
git ls-files --error-unmatch -- "$shared" >/dev/null 2>&1 || die "untracked shared scalar"
[ "$(git hash-object "$shared")" = "ec1cb5e6cc38c26842d724ccacb0df028b702c3f" ] ||
  die "canonical shared scalar Git blob mismatch"
[ "$(git rev-parse "HEAD:$shared")" = "ec1cb5e6cc38c26842d724ccacb0df028b702c3f" ] ||
  die "canonical shared scalar differs from committed file"

generic=contracts/stategraph-portability/shared-generic-state.ores
[ -f "$generic" ] && [ ! -L "$generic" ] || die "canonical generic fixture missing or symlinked"
git ls-files --error-unmatch -- "$generic" >/dev/null 2>&1 || die "untracked canonical generic"
[ "$(git hash-object "$generic")" = "c3a67b837a73f427a6157c446cc6e3989e9a66da" ] ||
  die "canonical generic source blob mismatch"
[ "$(git rev-parse "HEAD:$generic")" = "c3a67b837a73f427a6157c446cc6e3989e9a66da" ] ||
  die "canonical generic source HEAD mismatch"


# Additional semantic kernel has exactly the same Git blob in the Java and
# LLVM compiler repos; source integrity never counts as executable parity.
superstep=contracts/stategraph-portability/shared-superstep-scalar.ores
superstep_sha=054d4e9fe297c520513686feae076dc921f581ac
[ -f "$superstep" ] && [ ! -L "$superstep" ] ||
  die "shared superstep fixture missing or symlinked"
git ls-files --error-unmatch -- "$superstep" >/dev/null 2>&1 ||
  die "shared superstep fixture untracked"
[ "$(git hash-object "$superstep")" = "$superstep_sha" ] ||
  die "shared superstep fixture changed"
[ "$(git rev-parse "HEAD:$superstep")" = "$superstep_sha" ] ||
  die "shared superstep HEAD mismatch"

printf 'SG_PORTABILITY_SOURCE_ONLY_PASS requirements=9 source_files=10 head=%s tree=%s\n' \
  "$(git rev-parse HEAD)" "$(git rev-parse 'HEAD^{tree}')"
