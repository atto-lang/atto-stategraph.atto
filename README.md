# Native Oreslang StateGraph (sg)

**Status: experimental, merged source without verified native guest execution.**
This is the staged integration after PR #1 merged into main: the typed serial
StateGraph<S> API remains source-compatible, while PR #2 merged a typed
SuperstepGraph<S> with snapshot/patch/superstep semantics. The entire graph engine is authored
in Oreslang, not Python, JavaScript, Java, or an FFI orchestration layer.

## Typed API

The merged v0 API is sg.StateGraph<S> in src/stategraph.ores. This additive, experimental execution engine is SuperstepGraph<S> in src/supersteps.ores, with caller-owned application state S. Both are typed, but the two execution APIs are intentionally separate until compiler acceptance and a compatibility migration.
A required Fnc<S(S)> copy_state function must return a fully independent state
snapshot; use immutable value objects or deep-copy all mutable nested members.
The engine cannot statically enforce that user-supplied copy callbacks are pure.

Each node implements Fnc<StatePatch<S>(S)> and receives an independent snapshot
of the *same committed version* within a superstep. A patch consists of
GraphWrite<S> entries with keyed typed Fnc<S(S)> update functions.

- StatePatch<S>.set("key", function) performs a single-writer overwrite.
- add_reducer("key") admits StatePatch<S>.reduce("key", function).
- Writes to one reducer key are folded deterministically in frontier and patch
  order. Callers must supply associative/commutative reducer operations if they
  need order-independent behavior; algebraic laws are NOT checked.
- Every patch rejects duplicate write keys. Two nodes overwriting the same
  exclusive key in one superstep produce a conflict without publishing updates.
- Unregistered reducer operations or overwriting a reducer key are rejected.

### Example (Oreslang)

~~~ores
import class SuperstepGraph, StatePatch, GraphResult from "./src/supersteps";

define class Count as
  pub val int value;
end

fnc copy_count(Count state) -> Count {
  return new Count(state.value);
}
fnc increase(Count state) -> Count {
  return new Count(state.value + 1);
}
fnc step(Count state) -> StatePatch<Count> {
  val StatePatch<Count> patch = new StatePatch<Count>();
  patch.reduce("value", increase);
  return patch;
}

pub routine main() -> int {
  val SuperstepGraph<Count> graph = new SuperstepGraph<Count>(copy_count);
  graph.add_node("step", step);
  graph.add_reducer("value");
  graph.set_entry_point("step");
  graph.set_finish_point("step");
  if !graph.compile() then return 1; fi
  val GraphResult<Count> result = graph.invoke(new Count(5), 8);
  if !result.ok then return result.error_code; fi
  if result.state.value != 6 then return 2; fi
  return 0;
}
~~~

## Deterministic execution contract

- Named nodes, "__start__"/"__end__", regular edges, conditional branches
  with allowlisted choices, topology validation, and builder freeze.
- Fan-out executes each distinct named node once per superstep, sequentially
  in v1; all callbacks receive separate copies of the committed state.
- Pre-validate all patch write sets and reducer modes, apply them to a *candidate*
  snapshot, evaluate all conditional routes on post-update candidate snapshots,
  then publish the candidate in one graph-state commit.
- Duplicate edges, missing nodes, malformed routes, empty entry graphs, and
  ambiguous parallel END plus continuing work fail closed.
- Fan-in deduplicates destinations into the next superstep. Cycles require a
  1..100000 superstep budget, with a bounded pending frontier on exhaustion.
- Config limits: 1024 nodes, 8192 edges, 1024 conditional branches and 1024
  registered reducer keys; each node patch has at most 1024 keyed updates.

The runtime does not roll back external callback side effects, exceptions,
actor sends or database writes. Checked arithmetic is not part of the generic
patch engine. This is a sequential prototype (not actor-parallel or durable).

## In-memory continuation and strict admission

`SuperstepGraph<S>.resume(previous, additional_steps)` continues a run only when
`previous.error_code == 7` (step-budget exhaustion), `previous.ok == false`,
the pending frontier is nonempty, all distinct pending nodes are registered,
and the cumulative step budget remains bounded. It returns cumulative
`supersteps` and reuses the same compiled graph. This also rejects a
completed run, unknown/duplicate pending nodes and invalid budgets.

**Security limitation:** `GraphResult<S>` is caller-constructible; this is **not**
an authenticated checkpoint. The API cannot prove the previous state came from
the same graph or tenant, cannot attest a deep-copy callback, and cannot
make replay of external side effects safe. Use it only for caller-owned
in-memory workflows pinned to one immutable graph generation. Do not persist
or expose the result as a capability token.

Compiler-side topology validation now rejects nodes without any outgoing edge
or conditional route. The executor bounds total node callback invocations per
call to 100,000, in addition to the superstep budget, to mitigate high fan-out
work amplification.

## Error codes

| Code | Meaning |
|---|---|
| 0 | Completed through END |
| 1 | Not compiled |
| 2 | Bad superstep budget |
| 3 | Invalid/duplicate node patch |
| 4 | Mismatched reducer admission policy |
| 5 | Concurrent exclusive overwrite conflict |
| 6 | Conditional branch selected an undeclared destination |
| 7 | Step budget exhausted; pending frontier returned |
| 8 | Dead-end without END |
| 9 | END mixed with pending work in the same superstep |
| 10 | Reserved for invalid topology (compile() currently returns bool) |
| 11 | Node-execution work budget exhausted; no candidate state commit |
| 12 | Invalid/untrusted in-memory resume request or pending frontier |

## Verification and security

The superstep Oreslang smoke program lives in `tests/smoke.ores`, with four additional independent native guests in `tests/supersteps/`. The merged v0 serial kernel retains its original tests/native fixtures and ci/verify-native.sh. It exercises 46
assertion gates: typed state and patch construction, two-node reducer merge,
fan-in coalescing, snapshot isolation, conflicting writes, bad reducer policies,
post-update routing, bad routes, bounded cycles, invalid graph definitions,
duplicate patch writes, ambiguous END handling and builder immutability.

Run sh ci/verify-supersteps-native.sh with EXPECTED_SOURCE_SHA (the checked-out exact commit), EXPECTED_TREE_SHA (the Git SHA-1 **tree object**,
not the commit SHA), ORESLANG_BIN (absolute path to a trusted native compiler),
and ORESLANG_COMPILER_SHA256 (64 hex characters) set. It rejects missing or
mismatched tree/compiler identities, dirty files, symlinks, untracked source,
nonzero guest execution, and incorrect guest output. Success requires the real
guest to emit exactly SG_TYPED_SMOKE_PASS, then the harness prints SG_SUPERSTEPS_NATIVE_PASS.
A 'true' shell command cannot masquerade as a passing Oreslang guest.

.github/workflows/source-contract.yml is **static only**, not native guest
acceptance. The source GitHub organization may lack executable runner capacity.
For private mirrors: NEVER push the private source into a public repository,
never rely on cross-organization GITHUB_TOKEN checkout, and require equality of
the full Git tree hash and each tracked blob before claiming exact-source
execution. Different mirror commit IDs are acceptable only when the full
content-addressed tree identity is equal. Native acceptance requires executed
job steps and guest output, not merely a completed Actions run.

### Explicitly outstanding

An executed Java/GraalVM source compiler run, LLVM/.NET/Forge/Wasm acceptance,
native actor worker scheduling, cancellation, authenticated durable checkpoints, typed errors, deep snapshot
semantics audit, durable checkpoint storage, interrupts, retries, streaming,
dynamic Send, subgraphs, and AI provider adapters. Do not promote this draft to
production before native guest evidence exists.

References: LangGraph StateGraph and Pregel superstep execution.

## Expanded native acceptance inventory

The v0 serial engine now has **11 distinct native `.ores` guest fixtures**, including new negative tests for invalid/duplicate reducers, missing/invalid graph builder entries and minimum/maximum step budgets. The v1 superstep engine has **5 independent native guests** (the existing 46-gate smoke plus resume, topology, allowlist copy/route denial, and patch validation). Together the manifests account for **16 native guest programs**. These counts describe authored test programs, not observed native compiler passes. Real execution requires exact-source identity and actual job steps from both Graal and LLVM. See `ci/native-cases.txt` and `ci/supersteps-cases.txt`.

### Same-repository CI pinning and executed-step evidence (2026-10-31)

For first-party GitHub Actions jobs, `EXPECTED_SOURCE_SHA` is taken from the PR-head/push event and checkout is pinned to that exact commit. The workflow derives `EXPECTED_TREE_SHA` from that trusted commit object. An optional `SG_EXPECTED_TREE_SHA` repository variable can further restrict the accepted tree; if populated and different, CI fails. **Cross-organization mirrors must always receive the original source Git tree as an independently authorized external pin**; a mirror commit's self-derived tree alone is insufficient to establish that it matches private source.

A real GitHub-hosted runner has now executed the source-only checks, but the native jobs still refuse admission because `ORESLANG_GRAAL_BIN`/`ORESLANG_GRAAL_SHA256` and `ORESLANG_LLVM_BIN`/`ORESLANG_LLVM_SHA256` are not configured as executable trusted compiler paths/digests. This is a compiler-provisioning blocker, not an observed native source failure. See PR #4 for exact-head CI links. No native pass has been claimed.
