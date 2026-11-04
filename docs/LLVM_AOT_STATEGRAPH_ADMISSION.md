# LLVM StateGraph AOT acceptance — no interpreter shortcut

Status: **unverified native guest**. This document describes an admission gate,
not a passed cross-backend parity result.

## Audit finding

The former LLVM jobs called `ci/verify-native.sh` and
`ci/verify-supersteps-native.sh` with `ORESLANG_LLVM_BIN`. Those scripts
expect a language launcher accepting `--check` and **directly executing**
an Oreslang source file. The actual LLVM backend compiler is a
**source-to-LLVM-IR compiler**: its successful output is IR, not guest stdout.
That mismatch cannot establish actual LLVM guest parity. A wrapper could
produce misleading source-only receipts without testing a guest executable.

## Fixed gate (draft PR)

`ci/verify-supersteps-llvm-aot.sh` is the separate LLVM path. Both serial
(`SG_NATIVE_SUITE=serial`, 8 tests) and supersteps (default, 4 tests) use it.

The gate:
1. Validates HEAD, full Git tree and every tracked source byte/mode through
   `ci/verify-exact-tree.sh`. A private mirror is **not authorized** by this
   harness or by an approved-looking path; see the source repository's
   protected policy before any cross-organization transfer.
2. Demands an absolute, non-symlink, executable LLVM Oreslang compiler and
   an absolute, non-symlink Clang binary; both SHA256 digests are pinned.
3. Optionally accepts exactly one independently approved, SHA256-pinned
   **static native runtime archive**. Without it, a guest requiring native
   Array/String/record/stdio helpers must fail linkage, not silently
   replace the runtime with a host-level mock.
4. Reads a fixed, tracked source manifest; refuses unexpected/duplicate test
   paths, symlinks, changed source bytes, missing cases or oversized fixtures.
5. Runs the real compiler with `--target=host` to produce nonempty LLVM IR
   containing an OS main definition, then builds a native executable using
   pinned Clang, executes it with a timeout, and requires **exact guest stdout**
   with no stderr and exit status zero.
6. Emits `SG_LLVM_AOT_PASS` **only** after all required guest executions succeed.

No Python, JVM, or Oreslang interpreter is a fallback for the LLVM path.
No C++ imitation of StateGraph semantics counts toward this gate.

## Required independent provisioning

- `ORESLANG_LLVM_BIN`: absolute path to an authentic source-built LLVM compiler
- `ORESLANG_COMPILER_SHA256`: lowercase 64-character binary digest
- `SG_CLANG_BIN`: absolute path to a pinned Clang binary
- `SG_CLANG_SHA256`: Clang digest
- `SG_LLVM_RUNTIME_ARCHIVE` and `SG_LLVM_RUNTIME_SHA256`: paired optional
  reviewed archive/digest when generated IR needs runtime support
- `EXPECTED_SOURCE_SHA` and `EXPECTED_TREE_SHA`: immutable checked-out
  commit and full tree identities

The workflow repository variables must point to **real, pre-provisioned**
compiler/runtime artifacts on the runner. An ephemeral GitHub-hosted runner
does not gain a compiler merely because an environment variable was set.

## Remaining LLVM compiler parity gaps

The existing LLVM compiler documents support for scalar arithmetic, strings,
`Option`/`Result` with primitive payloads, bounded scalar classes and
local `Array<int>`/`Array<String>`. The complete StateGraph needs:

- `StateGraph<S>`, `SuperstepGraph<S>` and nested generic nominal
  specialization with sound layout, ownership and method dispatch;
- class-valued `Array<GraphNode<S>>`, `Array<StatePatch<S>>`,
  arrays as class fields, and owned cross-call returns;
- first-class `Fnc<StatePatch<S>(S)>` and `Fnc<S(S)>` stored in classes,
  closure captures, function pointer ABI and lifetime checks;
- snapshot copying, deterministic reducer barriers and checked effect
  isolation (including rejected undeclared field mutations);
- `GraphResult<S>` with non-scalar payloads and guest stdio, routing,
  errors/overflow and cancellation semantics consistent with Java/Graal;
- actual native actor scheduling, checkpoint persistence and replay later.

The shared scalar-superstep contract with Git blob
`0c1213cbedaf439e8f554627cf2174f4f2684d94` is an **incremental
scalar semantics probe**, not the production graph implementation.
It must execute identically on Java/Graal and LLVM with exact-head evidence.
Even if it passes, full StateGraph parity remains unproven.

## Evidence requirements

A successful CI job must have assigned runner, executed checkout/build/compile/
link/run steps, checked source identity, compiler SHA256, Clang SHA256, exact
guest statuses and output; the compiler itself must have been built from a
reviewed immutable source. A run with zero job steps is runner admission
failure, **not** a compiler test. Keep changes draft until these receipts and
independent review exist.

The LLVM repository's deny-by-default
`docs/security/CI_PRIVATE_SOURCE_MIRRORING.md` remains authoritative for
all private LLVM-source exports; this work does not authorize new mirrors.
