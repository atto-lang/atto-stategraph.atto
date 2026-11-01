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

## Superstep continuation hardening (2026-10-31)

The additive `SuperstepGraph<S>` module supports strict, **in-memory only** `resume(GraphResult<S>, additional_steps)`. It resumes only budget-exhausted runs (`error_code == 7`) with a nonempty, unique, registered frontier and budget remaining below 100000 cumulative supersteps. All fields are caller supplied and untrusted; the operation never grants durable or cross-tenant authority. For serialized/signed checkpoints, graph generation fencing, tenant-scoped identity, CAS versioning, and an idempotent effects journal are mandatory next steps.

`compile()` now rejects any registered node missing an outgoing static edge or conditional route before execution, and the engine bounds aggregate callback invocations to 100000 per `invoke`/`resume` call. `GraphResult.error_code == 11` denotes the work budget and `12` denotes invalid resume provenance/shape, not cryptographic verification. Source property tests: `tests/supersteps/resume.ores`, `topology.ores`, `allowlist.ores`, `patch-validation.ores`. These add four independent native guests to the existing 46-check smoke fixture. None has a verified compiler pass until the exact-head CI jobs execute and record steps.

`ci/supersteps-cases.txt` is the manifest for five native programs; the new `ci/verify-supersteps-native.sh` requires checked-out commit and Git tree pin, clean tracked source, no ignored/untracked files, native compiler SHA256 and `--build-info`, time-bounded `--check` followed by guest execution and byte-exact output for every case. The existing `ci/native-cases.txt` remains the independent eight-case serial graph manifest. Static CI is never runtime proof, and zero-step Actions runs are admission failures.

## Additional v0 negative fixtures

The serial `StateGraph<S>` acceptance manifest was extended from 8 to **11** guest cases. `patch-admission.ores` exercises empty writes, invalid channel and duplicate reducer admission without state publication; `builder-entry.ores` checks mismatched, ambiguous and empty entry names; `step-budgets.ores` tests zero/excessive step budgets and exact one-step exhaustion. Both CI manifests must cover all respective tracked programs or fail closed; CI without recorded job steps remains unverified.

## CI execution classification update

For first-party GitHub Actions, bind the checked-out commit to `github.event.pull_request.head.sha || github.sha`; derive the expected Git tree from that Git object and verify the checkout commit and tree in the harness. `SG_EXPECTED_TREE_SHA`, if configured, is an additional external pin; for a private cross-org mirror it is mandatory to supply original source-tree identity from an explicitly approved, independent channel.

Evidence from PR #4 initial head `c3f9e5ad9a127e21fa17cad9a0383cf7e4ce06b8`: [source-only #41255826809](https://github.com/ores-truffle-oreslang/oreslang-sg-stategraph.ores/actions/runs/41255826809) executed 7 steps and passed, including the fake-compiler negative check. [v0 native #41255826877](https://github.com/ores-truffle-oreslang/oreslang-sg-stategraph.ores/actions/runs/41255826877) executed 5 steps per failed backend and failed **before** compiler execution because `ORESLANG_BIN` and its SHA256 are unset. [superstep native #41255826909](https://github.com/ores-truffle-oreslang/oreslang-sg-stategraph.ores/actions/runs/41255826909) executed 5 steps per backend but failed earlier at missing `EXPECTED_TREE_SHA`; the workflow change removes that first-party configuration dependency. The remaining native compiler binary provisioning is still mandatory. Do not count these as native test failures or passes.
