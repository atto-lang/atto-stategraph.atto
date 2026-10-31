# StateGraph for Oreslang (`sg`)

Native, typed workflow graph execution in **Oreslang source** (no Python/JS orchestration runtime). This repository implements a small, deterministic initial execution kernel and declares the boundaries of future LangGraph-style functionality.

## v0 implementation

- `sg.StateGraph<S>` owns an immutable graph definition with typed `Node<S>` callbacks and guarded `Edge<S>` transitions.
- Reserved `START` and `END` sentinels; `END` is terminal.
- `validate()` checks duplicate/reserved node names, invalid edge endpoints, missing START edges, and budgets before any callback runs.
- `run(initial)` applies one node at a time, examines edges using the candidate updated state, and requires **exactly one** matching edge.
- Bounded loops, deterministic status and step count, and return of the last committed state on routing errors.
- Immutable-by-contract state transformations; no implicit conversions or automatic flattening.

### API sketch (Oreslang)

```ores
import class StateGraph, Node, Edge, RunResult from "../../src/stategraph";

fnc always(String state): bool { return true; }
fnc update(String node, String state): String { return state + "-updated"; }

pub routine main(): void {
  val StateGraph<String> graph = new StateGraph<String>(
    arr[new Node<String>("work", update)],
    arr[
      new Edge<String>("START", "work", always),
      new Edge<String>("work", "END", always)
    ],
    8
  );
  val RunResult<String> result = graph.run("seed");
  stdio.stdout.write(result.status);
  return;
}
```

The complete runnable acceptance programs are in `tests/native/`.

## Deliberate limitations

The v0 kernel alone is **not** a feature-complete LangGraph replacement: no runtime actor workers, parallel node execution, async/actor node scheduling, checkpoint storage, interrupts, resume, retries, distributed execution, or hot-upgrade replay guarantees. Callback purity is required by contract and **not verified by the compiler**; callbacks with external effects can still execute before a later failure. This release does not provide transactional side-effect rollback.

Each `StateGraph<S>` definition is immutable. User callbacks are responsible for implementing node behavior. The graph does not access the host, infer authority from state strings, or grant capabilities.

## Validation

`sh ci/audit-source.sh` runs a source-only policy check; it is **not** a native guest execution result.

`sh ci/verify-native.sh` checks out the exact committed source, requires a pinned trusted compiler executable, runs `--check` on each guest, executes native `.ores` tests and compares their exact output. Missing compiler or missing executed steps fails closed. See [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md) for semantics and release gates.

LangGraph concepts used for comparison are documented at https://docs.langchain.com/oss/python/langgraph/overview ; this implementation is original Oreslang code, not a Python binding.

## Additional native source modules (draft extension)

- `src/builder.ores`: immutable batch-registration `GraphBuilder<S>`, explicit entry-point and budget, `validate()` plus `compile()` returning `BuildResult<S>`. This intentionally uses `with_nodes`/`with_edges` for whole declaration batches. A mutating or persistent single-node `add_node` has **not** yet been implemented or validated against the compiler collection API.
- `src/patches.ores`: typed `StatePatch<P>`, keyed `StateReducer<S,P>`, and two-pass `apply_batch<S,P>`. Duplicate patch channels, missing reducers and duplicate reducer bindings fail **before** any reducer executes; successful patches reduce in authored order. One batch uses one payload type `P`. This is not yet parallel supersteps or heterogeneous field reducers.
- Eight native guest fixtures are now listed in `ci/native-cases.txt`; none constitutes a native pass until compiler checks and executions are observed for the exact commit.

## Experimental typed superstep extension (PR #2)

The separate `src/supersteps.ores` module adds a **generic** `SuperstepGraph<S>` builder/executor alongside—not in place of—the merged `sg.StateGraph<S>` v0 kernel in `src/stategraph.ores`. The two implementations have distinct APIs; no migration or runtime-parity claim is made.

- `SuperstepGraph<S>` accepts a caller-provided `copy_state: Fnc<S(S)>` which **must** deep-copy owned state. Compiler-enforced ownership/purity has not been demonstrated.
- `StatePatch<S>` carries keyed state-transform callbacks, with declared reducer keys, exclusive-write conflict checks, and complete-superstep preflight before applying updates.
- Multiple active nodes see snapshots of one committed state; fan-out, deduplicated fan-in, conditional allowlisted routing on candidate state, bounded cycles, and all-or-nothing **graph-state publication** are modeled.
- Noncommutative reducer callbacks execute in deterministic authored order. Reusing a reducer key does not certify associativity, commutativity, or external side-effect rollback.
- Branching into END while other work remains fails closed. There is no checkpoint/resume or asynchronous actor scheduling yet.

### Example acceptance and verification

`tests/smoke.ores` targets `src/supersteps.ores` and covers reducer fan-in, exclusive-write conflict, missing reducer, post-merge routing, unauthorized route, bounded cycle, malformed topology, duplicate patch writes, mixed END work, and frozen builder. The extra workflow `.github/workflows/source-contract.yml` is **source-only** and does not compile or execute Oreslang.

`ci/verify-supersteps-native.sh` is a separate fail-closed native acceptance harness. It requires `EXPECTED_TREE_SHA` (full tree identity), `ORESLANG_BIN` (absolute trusted compiler path) and `ORESLANG_COMPILER_SHA256` (pinned compiler hash), then checks and executes `tests/smoke.ores` as a guest. A script in the repository is not evidence that it ran: native acceptance requires executed job steps, captured exit codes, exact SHA and compiler identity. No Graal, LLVM, Forge, .NET or Wasm native pass is asserted.

The original `ci/verify-native.sh` and its eight v0 guest fixtures remain untouched. A future integration PR can consolidate the typed v0 and superstep implementations after real compiler/backend verification.
