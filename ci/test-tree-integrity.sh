#!/bin/sh
# Self-contained negative tests. This uses a throwaway local Git repo, never
# the project source tree and never an Oreslang compiler.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
root="$(pwd -P)"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/fixture/ci"
cp "$root/ci/verify-exact-tree.sh" "$tmp/fixture/ci/verify-exact-tree.sh"
cd "$tmp/fixture"
git init -q
git config user.name "CI Source Policy"
git config user.email "ci@invalid.example"
git config core.filemode true
printf 'source\n' > README.md
printf 'ignored.txt\n' > .gitignore
git add README.md .gitignore ci/verify-exact-tree.sh
git commit -qm 'source-only fixture'
export EXPECTED_TREE_SHA="$(git rev-parse 'HEAD^{tree}')"
sh ci/verify-exact-tree.sh > "$tmp/pass" ||
  { cat "$tmp/pass" >&2; exit 1; }

fail_if_accepted() {
  label="$1"
  if sh ci/verify-exact-tree.sh > "$tmp/negative" 2>&1; then
    printf 'TREE_NEGATIVE_FALSE_PASS %s\n' "$label" >&2
    exit 1
  fi
  printf 'TREE_NEGATIVE_PASS %s\n' "$label"
}

printf 'modified\n' >> README.md
fail_if_accepted modified_blob
git restore -- README.md
printf 'new\n' > unexpected.txt
fail_if_accepted untracked_file
rm -f unexpected.txt
printf 'ignored\n' > ignored.txt
fail_if_accepted ignored_file
rm -f ignored.txt
ln -s README.md link
fail_if_accepted symlink
rm -f link
chmod +x README.md
fail_if_accepted mode_change
chmod -x README.md
EXPECTED_TREE_SHA=0000000000000000000000000000000000000000
export EXPECTED_TREE_SHA
fail_if_accepted wrong_tree
printf 'TREE_NEGATIVE_SUITE_PASS 6/6 source-only\n'
