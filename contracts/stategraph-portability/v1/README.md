# StateGraph portability conformance v1 — exact common Oreslang source

**Objective:** One `.ores` StateGraph implementation and application code must
compile and execute with equal observable behavior on Java/Graal, LLVM, Wasm,
Cranelift and .NET. Host adapters can provide only minimal compiler/runtime
primitives, **not** backend-specific graph implementations. No implicit casts,
null, reflection, operator overloading or native host-language graph rewrites.

## Current evidence and blockers

| Backend | Native source admission as documented | Full StateGraph guest execution |
| --- | --- | --- |
| Java/Graal | Broad Oreslang language reference; exact-guest verification still required | **UNVERIFIED** |
| LLVM | Documented partial source/actor/class and other lowering; requires full guest semantics | **UNVERIFIED** |
| Wasm | Experimental scalar wasm32 codegen path; compiler artifact not proven available | **UNVERIFIED** |
| Cranelift | Stage-0 checked-i64 function JIT; classes, modules, loops and actors explicitly rejected | **UNSUPPORTED / UNVERIFIED** |
| .NET | NativeAOT bootstrap and structured-function slices; full generic graph/actor lowering absent | **UNSUPPORTED / UNVERIFIED** |

**Do not conflate** contract-source checks, compiler parsing, typechecking,
native code generation, guest execution or verified concurrency semantics.
Neither Cranelift scalar execution nor Wasm scalar compilation establishes
support for GraphState<T>, typed callbacks, Array, Result, imports, actors or
the current StateGraph modules. Unsupported features must be rejected explicitly
until implemented, not silently emulated by Python, JavaScript, Rust or C#.

## Canonical portable probes (one authoritative source; backend copies NOT established)

The ten `.ores` files in this central StateGraph repository are authored probes; nine are
independently listed requirements, and `graph_support.ores` is the linked
helper module. The `manifest.txt` records each canonical Git blob SHA
to enable future exact-byte checks when a reviewed copy is explicitly authorized.\nThe compiler repositories currently contain separate backend-specific regression probes;\nthey have **not** established byte-identical copies of this complete canonical corpus.

Required categories:
1. Checked scalar arithmetic and source entry.
2. Module declarations and function resolution.
3. Generic immutable nominal state, constructors and field access.
4. Typed `Fnc` callback values and eager deterministic invocation.
5. Bounded typed mutable Array for frontiers/merges.
6. `Result<T,E>` explicit error/value handling.
7. Cross-file `import module` with project-root resolution.
8. Isolated actor with `state`, critical `handle_state`, typed mailbox, async await.
9. Generic reducer/patch callback types and construction.

The probes deliberately form a *progressive feature ladder*. Their authored
syntax should be compiler-validated and, where admissible, genuinely executed
before a backend is marked supported. For module/import probes, compile all
reachable source units under one verified package root, not a different
stubbed file. For actors, require runtime mailbox/continuation/cancellation
evidence, not just syntax recognition.

## Exact-head acceptance sequence PER backend

1. Require independent review and protected main. Record the **exact**
   source Graph library, stdlib, compiler, and test-fixture commit/tree/blob
   SHAs and approved compiler binary/container digest.
2. Confirm admitted runner with nonempty executed steps. Zero-step GitHub
   Actions failure is runner admission, *not* a compiler test result.
3. Run source-only `sh ci/verify-stategraph-portability.sh` to check pinned
   blobs and manifest. This is not guest execution.
4. Compile the scalar probe and actually execute it to observe **42**, with
   exact stdout/value; show negative fake-compiler and negative syntax cases
   fail without successful output.
5. Compile/typecheck each successive probe, then execute it under the
   backend's **actual** guest runtime. For an unsupported probe, record an
   explicit compiler error and leave that capability **missing**.
6. Compile and execute **the original, unchanged** `src/stategraph.ores`,
   `src/builder.ores`, `src/patches.ores`, `src/supersteps.ores` and
   pending `src/run_ledger.ores` through the same compiler. Also compile
   all the production `tests/native/*.ores`, `tests/smoke.ores`, and
   ledger tests and compare exact results/status/step count/output.
7. Adversarial parity: deterministic reducer folding, fan-in, invalid
   topology, actor cancellation/late receipts, bounded memory, ownership,
   no implicit conversions, and negative import/borrow diagnostics.
8. Capture test case counts and nonzero step IDs. Separate scalar, parser,
   typechecker, genuine guest, actor scheduling and NativeAOT/Wasm evidence.

For private source: this canonical corpus currently resides only in the\nStateGraph repository. Separate backend-specific probes were authored in each\ncompiler repository without copying the private StateGraph implementation.\nCross-organization private tree mirroring still requires specific authorization\nand a verifiable identical full Git tree; no public mirroring. These probes are neither a substitute for
the actual StateGraph implementation nor authorization for private transfer.

## Promotion policy

No status is called **parity achieved** unless *the exact same StateGraph
program sources* compile and execute under every target without backend-specific
source rewrites. The baseline scalar subset is a bootstrapping check only.
Keep implementation and compatibility PRs draft while gates fail.
