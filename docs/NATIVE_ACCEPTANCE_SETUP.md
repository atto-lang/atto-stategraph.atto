# Native StateGraph acceptance and provisioning

This private repository currently has **working GitHub Actions runner admission** and
source-only policy passes, but the two native Oreslang backends are NOT installed
on the default GitHub-hosted runners. A repository variable containing a path
does not magically install a compiler on each ephemeral runner.

## Genuine acceptance requirements

Every candidate requires all **16** authored native guest programs:
- `ci/native-cases.txt`: 11 typed serial `StateGraph<S>` programs.
- `ci/supersteps-cases.txt`: one 46-assertion superstep smoke and four
  independent routing, patch, topology and continuation programs.
- Execute both suites on **Java/Graal** and **LLVM** independently. These are
  32 distinct compiler check/guest-run pairs across two compiler backends,
  not mere static source tests.

## Operator-controlled compiler provisioning

1. Select approved private Linux runners which already contain authentic,
   tested, non-symlinked Oreslang Java/Graal and LLVM compiler executables.
   If using ephemeral hosted runners, add an independently reviewed, pinned
   installation/build step for each compiler from a trusted immutable artifact.
   Do **not** download and run a mutable, unverified release URL.
2. Set repo Actions **variables** for each backend, with the real absolute
   paths and SHA-256 digests of those executables as seen inside the runner:
   `ORESLANG_GRAAL_BIN`, `ORESLANG_GRAAL_SHA256`,
   `ORESLANG_LLVM_BIN`, `ORESLANG_LLVM_SHA256`.
   Filesystem paths are not secrets; keep tokens/credentials out of scripts.
3. Verify compiler build attestation: `--build-info` must succeed and
   identify build mode and guest execution; then `--check` and actual
   execution must both succeed for every tracked guest. Confirm these flags
   really describe the Java and LLVM native binaries; do not fake outputs.
4. For first-party GitHub Actions, the event's exact PR head/push SHA
   identifies the checked-out commit; the workflow derives its Git tree
   from that pinned commit object. Optional `SG_EXPECTED_TREE_SHA` restricts
   the accepted Git tree further. For an explicitly **authorized private
   cross-organization mirror**, this external original-tree pin is mandatory,
   as is independent full Git-tree/blob/mode equality verification.
5. Run all jobs, then capture the run attempt, source SHA, tree SHA, compiler
   digest, job IDs, **real executed steps**, guest output markers, and any
   diagnostics from a first failing test. Zero-step jobs mean runner admission
   failure, not compiler failure; steps that stop before `--check` are
   provisioning/identity failures, not guest test failures.

## Local operator invocation on a trusted runner

From a clean checked-out Git repository pinned to a commit:

```sh
export EXPECTED_SOURCE_SHA="$(git rev-parse HEAD)"
export EXPECTED_TREE_SHA="$(git rev-parse HEAD^{tree})"
# Set ORESLANG_BIN to the actual approved compiler path.
# Set ORESLANG_COMPILER_SHA256 to sha256sum of that actual executable.
sh ci/verify-native.sh
sh ci/verify-supersteps-native.sh
```

Use the appropriate **backend-specific compiler** for each separate run.
Do not reuse Graal evidence to claim LLVM parity or vice versa.

## Known pre-native failure evidence

On PR #4 initial head `c3f9e5a...`: source-only Actions run
[`41255826809`](https://github.com/ores-truffle-oreslang/oreslang-sg-stategraph.ores/actions/runs/41255826809)
passed with 7 steps. The native v0 run
[`41255826877`](https://github.com/ores-truffle-oreslang/oreslang-sg-stategraph.ores/actions/runs/41255826877)
entered real steps but both compilers lacked `ORESLANG_BIN`. Superstep native
run [`41255826909`](https://github.com/ores-truffle-oreslang/oreslang-sg-stategraph.ores/actions/runs/41255826909)
reached steps but stopped at absent tree pin, remedied in the next code commit
for first-party CI. These are **not** native source/test verdicts.

## Review and promotion gates

- Do not merge experimental additions on source-only CI. Independent review
  is mandatory. `main.protected=false` was verified; tracked as
  [issue #3](https://github.com/ores-truffle-oreslang/oreslang-sg-stategraph.ores/issues/3).
- Resume is **in-memory, untrusted and caller-owned**. There is no durable
  checkpoint CAS, tenant-bound token, idempotent external effect outbox,
  actor cancellation, authenticated interrupt, or production replay contract.
- Native acceptance must come from actual compiler execution on the **exact
  source tree**, not a generic host interpreter, shell mock or zero-step run.
