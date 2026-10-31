# Oreslang StateGraph (sg)

A native **Oreslang-source** implementation of StateGraph-style stateful orchestration. The graph runtime has no Python, Java, JavaScript or FFI dependency.

**Status (2026-10-31): experimental v1, compiler/guest execution NOT YET verified.** The linked CI workflow performs static source checks only.

## Runtime features

- Named nodes with Fnc<StatePatch(GraphState)> callbacks, regular edges, and reserved "__start__"/"__end__" sentinels.
- Conditional routing with Fnc<String(GraphState)> callbacks and explicit allowlisted destinations.
- Compile-time validation of node and edge references; builder mutations reject changes after successful compile().
- Bulk-synchronous execution: isolated per-node state snapshots, partial state patches, merge barriers, and route evaluation on the post-merge state.
- Default single-writer overwrite keys (StatePatch.set), registered integer sum reducers (add_sum_reducer and StatePatch.add), fail-closed conflicts without partial state commits.
- Fan-out, deduplicated fan-in, bounded cycles, returned state snapshots and error codes.

## Example

~~~ores
import class StateGraph, GraphState, StatePatch, GraphResult from "../src/stategraph";

fnc increment(GraphState state) -> StatePatch {
  val StatePatch patch = new StatePatch();
  patch.add("count", 1);
  return patch;
}

pub routine main() -> int {
  val StateGraph sg = new StateGraph();
  sg.add_node("increment", increment);
  sg.add_sum_reducer("count");
  sg.set_entry_point("increment");
  sg.set_finish_point("increment");
  if !sg.compile() then return 1; fi
  val GraphState initial = new GraphState();
  initial.put("count", 0);
  val GraphResult result = sg.invoke(initial, 8);
  if !result.ok then return result.error_code; fi
  if result.state.get("count").unwrap() != 1 then return 2; fi
  return 0;
}
~~~

## Error contract

| error_code | Description |
| --- | --- |
| 0 | Completed through END |
| 1 | Not compiled |
| 2 | Invalid step budget |
| 3 | Invalid or duplicate node patch |
| 4 | Update does not match channel reducer |
| 5 | Multiple overwrite writers in one superstep |
| 6 | Router returned undeclared destination |
| 7 | Step limit reached; pending frontier returned |
| 8 | Dead-end without END |

## Limitations and verification

This first slice has String-to-int state keys/values, an additive reducer and a **sequential** deterministic executor. The snapshot barrier could later dispatch node tasks to native Oreslang actors, but worker parallelism is not yet implemented. Node callbacks' external side effects cannot be rolled back; the atomicity guarantee is restricted to GraphState. There is no tested overflow recovery, cancellation, checkpoint resume, durable persistence, streaming, typed heterogeneous state, generic reducers, interrupt/resume, human approval, error retries, LLM adapter or Send-style dynamic fan-out.

Builder limits: 1024 nodes, 8192 regular edges, 1024 conditional branches; caller step limits must be 1..100000. Conditional route lists are copied at registration; any destination not allowlisted fails closed.

The behavioral contract lives in tests/smoke.ores (0 exit means pass): fan-out/fan-in, reducer merges, overwrite conflicts, snapshot isolation, post-merge routing, undeclared routes, cycles, invalid graphs, builder freezing and duplicate patches. This test source has not been observed executing on a native compiler. Before claiming production readiness, compile and execute it on the exact source commit with Java/Truffle, then separately verify LLVM, .NET, Wasm and Forge backend acceptance. In particular verify Array<GraphNode>, Array<StatePatch>, first-class Fnc members, Option<int>, synthesized constructors and mutable-receiver dispatch.

Reference semantics: https://reference.langchain.com/python/langgraph/graph/state/StateGraph and https://reference.langchain.com/python/langgraph/pregel/main.


## Native acceptance harness

ci/verify-native.sh is a **fail-closed** acceptance harness: it requires an exact Git tree hash and a pinned native compiler binary, checks the source/test blobs are tracked and clean, runs the compiler in --check mode and runs tests/smoke.ores as an Oreslang guest process under a bounded timeout. A success marker (SG_NATIVE_PASS) is printed only if both guest commands exit 0. For an exact-tree private mirror, the head commit hash may differ from the source commit but the complete Git tree hash and all corresponding blob hashes must match.

Configure EXPECTED_TREE_SHA (40-character source tree object ID), ORESLANG_BIN (absolute path to trusted compiler executable) and ORESLANG_COMPILER_SHA256 (64-character SHA-256 checksum), then run: sh ci/verify-native.sh. This is deliberately not a green-by-default CI shim: missing binaries, missing pin, wrong tree, untracked source or execution failure must fail.

The source-only GitHub Actions workflow cannot establish guest execution. If jobs are queued with zero steps, the missing runner execution is itself a blocker, not a pass.
