# Oreslang StateGraph v0: semantics and release gates

## Execution model

Each `StateGraph<S>` is a compiled, single-lane graph description. `run` accepts `S` and returns `RunResult<S>`. `Node<S>` has an id and callback `Fnc<S(String, S)>`; `Edge<S>` has source, destination, and a typed `Fnc<bool(S)>` condition. The START transition sees the supplied initial state. Each subsequent node runs once when reached; the outgoing predicates see the resulting **candidate** state. Exactly one outgoing predicate must return true.

There is no dynamic string-eval dispatch: execution dispatches only to a validated node declared in the immutable graph. All reachable cycles are subject to `max_steps` (1..10000); the budget counts executions of user nodes, not START. It is a logical step bound, **not** a wall-clock deadline. Callback exceptions/cancellation/CPU stalls are not intercepted.

## Validation / error statuses

- `completed` - END reached, state and step count committed.
- `invalid_graph:invalid_budget` - zero, negative, or excessive budget.
- `invalid_graph:reserved_node`, `invalid_graph:duplicate_node` - invalid node registry.
- `invalid_graph:reserved_edge`, `invalid_graph:unknown_source`, `invalid_graph:unknown_target`, `invalid_graph:missing_start` - invalid graph structure.
- `unmatched_edge`, `ambiguous_edge` - no unique next step (fail closed).
- `step_limit` - failed before the next node call; returns latest committed state.

For missing/ambiguous routes a node may have run, but its candidate update is not returned as committed state. This **does not undo side effects** of a callback. Predicates are all evaluated for the current source to detect ambiguity, and they must be total, deterministic, and side-effect free. Unreachable nodes and cycles are allowed by v0 structural validation; deadlock/liveness audits belong to a later compiler validation pass.

## Security boundaries

State `S` must be owned by the executing task or immutable/sendable. No raw object references may cross actors. The API does not claim heap isolation, durable transactions, exactly-once effects, automatic security policies, network or LLM tool capabilities. If callbacks do I/O, caller provides authority; make effects idempotent or add an outbox when durability lands.

Graph definitions should be versioned and pinned per invocation. Never resume a checkpoint against changed definitions without schema migration, generation fencing, and a deterministic replay policy.

## Next native milestones

1. Compiler-check this exact head on Java/Graal and LLVM; resolve unsupported syntax against compiler, not by a host-language interpreter.
2. Define a native `StatePatch<S>` / reducer scheme with explicit conflict policy and a sealed write set; no mutable shared-state actor fan-out.
3. Actor-owned `GraphRun` coordinator with bounded mailbox, non-reentrant continuation accounting, structured cancellation and fair admission; add native async node execution.
4. Durable checkpoint adapter with tenant / graph / thread / generation keys, atomic step receipts, CAS versioning, idempotent outbox, and resume/interrupt semantics. Keep checkpoint authority separate from graph state.
5. Superstep fan-out/fan-in and per-channel reducers, deterministic conflict detection, retry policies and human review interrupts.

## CI evidence rules

Source lint is only source lint. Native acceptance requires: exact branch-head SHA, executable and digest attestation, `--check`, observed native execution of every listed `.ores` case, full step/job evidence. GitHub Actions jobs with zero steps are runner admission failures, not test results. No private-source mirroring to another organization without explicit authorization; any authorized mirror must verify exact source Git tree identity. Default CI never falls back to Python, JavaScript, or stubs.

## Builder and typed state patches (draft extension)

`GraphBuilder<S>` is functional/immutable. For portability until a compiler-proven list construction API exists, the public surface is `with_nodes(List<Node<S>>)`, `with_edges(List<Edge<S>>)`, `set_entry_point(String)`, and `set_step_budget(int)`. `compile()` returns a `BuildResult<S>` with status; callers MUST check `status == "compiled"` before running `result.graph`. The result always carries its graph value; a failed build value is not an admitted execution plan. The builder checks a single START entry edge pointing to the declared entry node.

`StatePatch<P>` carries a typed payload P and channel string; reducers `StateReducer<S,P>` are explicitly bound to channels. `apply_batch<S,P>` validates every write before calling any reducer. Duplicate writes to one channel always yield `write_conflict`; unknown channels and duplicate reducers fail closed. After preflight, reducers are pure functions `S,P -> S`; results are combined in declared write order. There is no automatic field reflection, implicit conversion, or mutable sharing. Reducer callbacks can still throw or have out-of-band effects; this API offers neither transactional rollback nor effect isolation.

Open blockers: real compiler support for `List`/generic Oreslang classes and import references, whole-file compilation, native test receipts for all eight cases, proper single-node add API, per-channel heterogeneous reducers, and proper actor-supervised work. These remain unverified while Actions jobs are zero-step.


## Bounded userland preflight and additional native regression cases

The serial StateGraph validates node/edge count before quadratic structural
scans (at most **1024 registered nodes** and **8192 edges**). The pure patch
engine rejects batches of more than **1024 writes** or **1024 reducers**
without calling guest merge callbacks and without publishing intermediate
state. The separate superstep engine retains its existing independent bounds.

Three extra native `.ores` cases check step budget boundaries 0/-1/10000/10001,
strict reducer ordering under noncommutative operations, empty patch behavior,
duplicate reducers and missing reducer schema. The native-case manifest now
requires **11** guest programs, but source presence is not guest execution.
Both genuine Graal and LLVM compilers must still compile the exact same
userland source; CI attempts with zero job steps do not establish acceptance.


## Serial StateGraph additional native guest edge cases

Four more userland Oreslang programs exercise a direct `START -> END`
without running callbacks, a deterministic START fork with unmatched
routing rollback, patch preflight failure precedence and atomicity, and
step-budget frontier publication between successive nodes. The manifest
requires **15** serial native Oreslang guests. These assertions are authored
and structurally inspectable, but do not claim compiler-backed passes until
a stepful Graal and LLVM guest receipt exists. The untouched userland program
sources remain the intended contract for Wasm, Cranelift and .NET as those
compilers gain the missing generic/functional/collection lowerings.


## Fail-closed entire reducer registry (pure Oreslang)

Patch application now rejects empty or duplicate *declared reducer* channel
names even when no pending writes reference those reducers. A malformed
reducer registry cannot be accepted simply because a batch was empty. The
new `invalid-reducer-registry.ores` and `reducer-declaration-order.ores`
cases verify this validation and ensure declaration order does not alter
userland patch order. The serial native suite now requires **17** programs.
This is authored source without compiler-backed guest receipts; every
backend must still run the same guest programs before parity claims.
