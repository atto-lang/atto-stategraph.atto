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

This is **not** yet a feature-complete LangGraph replacement: no builder methods, node fan-out, reducers, parallel supersteps, async/actor node scheduling, checkpoint storage, interrupts, resume, retries, distributed execution, or hot-upgrade replay guarantees. Callback purity is required by contract and **not verified by the compiler**; callbacks with external effects can still execute before a later failure. This release does not provide transactional side-effect rollback.

Each `StateGraph<S>` definition is immutable. User callbacks are responsible for implementing node behavior. The graph does not access the host, infer authority from state strings, or grant capabilities.

## Validation

`sh ci/audit-source.sh` runs a source-only policy check; it is **not** a native guest execution result.

`sh ci/verify-native.sh` checks out the exact committed source, requires a pinned trusted compiler executable, runs `--check` on each guest, executes native `.ores` tests and compares their exact output. Missing compiler or missing executed steps fails closed. See [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md) for semantics and release gates.

LangGraph concepts used for comparison are documented at https://docs.langchain.com/oss/python/langgraph/overview ; this implementation is original Oreslang code, not a Python binding.
