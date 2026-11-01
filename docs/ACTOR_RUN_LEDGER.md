# Actor-owned StateGraph run ledger — v0 contract

The Oreslang-native `src/run_ledger.ores` implements a **pure, immutable** state transition policy for a **single graph-run coordinator actor**. It is the ownership/continuation *substrate*, **not** a scheduler or actor runtime. The coordinator integration must only be called complete after an actor using `state { ... }`, `handle_state` and `critical` successfully compiles and executes on pinned backends.

## State machine and credits

Run identity is `RunKey(tenant, run_id, generation)`. The values are **correlation identifiers, not authentication or tenant authority**. A trusted supervisor must bind the externally authenticated tenant to this key and must authorize exactly one active coordinator per identity/generation. A caller can construct keys: the ledger cannot detect an authentic principal.

`create` returns a validated, immutable `RunState` with `phase=CREATED`, `version=1`, and configurable bounds (`max_steps` 1..100000, `max_pending` 1..1024). All subsequent state transitions require an exact key and expected version. `start` enters RUNNING.

`enqueue` admits one logical unit of work only if the run remains active, bounded credits exist, and the sum of completed + pending + active work stays below `max_steps`. **No messages are physically enqueued by this function**. A real coordinator must hold and drain a bounded, separately owned FIFO payload queue with strict conservation: queue count must equal the ledger's pending count at every admission and retirement point.

`claim` moves one pending credit to the single in-flight slot and returns an owner-generation-fenced `ClaimReceipt`. `publish` takes the exact active receipt once and counts a successful state publication. Duplicate, altered-issue-version, stale generation, foreign-run and post-cancellation publications fail closed. A claimed receipt includes the recorded claim-issue version; a receipt with the right serial but a different version is rejected. Receipt serials never wrap. The code prevents scheduling more than one logical node turn at once; it does **not** prevent external callbacks from executing simultaneously outside the coordinator.

`finish` requires no pending or active work; `cancel` and `fail` fence future publications, clearing credits and the active claim. These actions do **not** physically stop a running worker. The actor runtime must signal structured cancellation, await worker termination, and release reserved memory/mailbox credits before considering retirement complete. Cancellation is not a durable, exactly-once transaction.

## Ownership and required actor bridge

One `GraphRunCoordinator` actor owns both `RunState` and the actual pending message queue. On each event, enter a compiler-checked `critical` handle_state write scope, validate the caller's *real* authorization separately, produce the next immutable ledger state, and publish it together with the corresponding queue mutation. Never suspend while holding a mutable state loan; release the loan before doing `await`, `select`, actor send, checkpoint I/O, or arbitrary callback execution. The actor resumes only with a generation-fenced claim receipt, and it publishes graph state **only if** both the ledger transition and corresponding graph-state validation succeed. If the graph callback throws, do not call `publish`; fail/cancel and drain with structured ownership.

### Lifecycle

```text
CREATED --start--> RUNNING --enqueue--> pending credit
    RUNNING --claim--> exactly one active receipt
    RUNNING --publish(receipt)--> committed step count increases
    RUNNING --finish(quiescent)--> COMPLETED
    CREATED/RUNNING --cancel--> CANCELLED (publication fenced)
    RUNNING --fail--> FAILED (publication fenced)
```

All events use optimistic version preconditions and reject malformed externally constructed snapshots, including inconsistent in-flight/claim-version pairs. A different tenant, run, generation or stale version cannot mutate an already owned snapshot. The user-facing strings in `RunKey` do not grant capabilities. No implicit conversions, operator overloading, reflection, raw pointers, blocking I/O or Python/JS runtimes are needed.

## Interop with current StateGraph engines

Keep `sg.StateGraph<S>` (serial), `SuperstepGraph<S>` (in-memory supersteps), and the ledger separate until exact-head native compiler evidence exists. `SuperstepGraph<S>.invoke` executes callbacks synchronously and may advance multiple steps. Treat it as **one atomic logical work item** when called from the graph actor; claiming per-node or per-superstep receipts requires a future incremental step API. `GraphResult<S>` from an untrusted or canceled worker is only a candidate: the coordinator must check the claim, generation, version and graph definition pin before publishing. Retain the original state on any failed check.

## Experimental native actor adapter (not accepted or proven executable)

`examples/experimental/graph_run_coordinator.ores` now sketches a concrete `define isolated actor GraphRunCoordinator` with a single `state { ... }` schema, synchronous `self.handle_state(critical |owned| -> { ... })` transitions and output messages **outside** the critical state-loan scope. It also contains a demo entry routine probing early publish rejection, start, enqueue, claim, cancel, late publish rejection, and explicit stop. It intentionally uses fixed fixture strings and the actor state has no credential or durable authority. This source is an **experimental compiler-admission target**: it is excluded from the 3-test accepted manifest because the exact actor syntax and implementation must be validated on real Java/Graal and LLVM compilers. Until it compiles and executes, do not call it a working actor implementation.

Do not add parallel workers or claim synchronized queue reservation on the basis of this adapter alone: the ledger is a credit counter, not a physical FIFO. The next actor stage must add real typed bounded pending-message storage and keep its count in lockstep with the ledger.

## Regression / evidence matrix

Three new native Oreslang fixtures in `tests/run-ledger.ores`, `tests/run-cancellation.ores`, `tests/run-budget.ores` cover successful state transitions, duplicate/foreign/stale receipts, cancellation-fenced publications, bounded queue credits and logical step budgets. Their **source presence is not a native test pass**. The exact-head `ci/verify-run-ledger-native.sh` checks source SHA/tree, dirty/untracked/ignored/symlink admission, pinned/compiler build-info and executes all three with bounded `--check` and exact stdout.

All source-only checks must be distinguished from real Java/Graal/LLVM native guest results. Current GitHub-hosted runners don't automatically contain approved Oreslang compiler binaries: operators must provision trusted compiler binaries in a reachable, immutable path and pin their SHA256. See [issue #3](https://github.com/ores-truffle-oreslang/oreslang-sg-stategraph.ores/issues/3). Do not transfer private code to another organization's runner without specific authorization and exact-tree verification.

## Next features

- Compiler-supported, **actor-owned** `state`/critical `handle_state` bridge, checked under both compiler backends.
- Bounded mailbox payloads, generation-safe cancellation fencing across suspension, actual supervisor/worker DONE evidence and fair work admission.
- Versioned serialized checkpoint/outbox, replay receipt provenance, tenant-controlled authorization, human interrupts and actor-parallel work with deterministic reducers.


## Extended native regression matrix (source-authored)

The native manifest now enumerates **14** independently executable `.ores` guest programs: the original three plus eleven new fixtures:
`run-identity`, `run-versions`, `run-receipts`, `run-credits`,
`run-terminals`, `run-cancel-created`, `run-failure-active`,
`run-malformed`, `run-boundaries`, `run-generations`, and
`run-issue-version`.

These exercise cross-tenant and cross-generation isolation, optimistic
concurrency, receipt replay and issue-version tampering, fair logical credits,
terminal idempotence, cancellation from CREATED, failure with queued and active
work, malformed public snapshot rejection, exactly bounded steps, incarnation
reuse and later publication after other queue admissions. Each program returns
a unique nonzero exit status on its first failed condition and emits an exact
success marker only on success. The test manifest is now required to cover the
complete tracked `tests/run-*.ores` set; missing/duplicate tests reject in
both source-only and native harnesses.

The ledger guard additionally rejects forged CREATED snapshots, inconsistent
active-receipt serial/claim versions, impossible in-flight totals and versions
that predate a started run. This is structural validation, **not** an
unforgeable capability: a malicious caller who can construct arbitrary
`RunState` and `ClaimReceipt` values can still fabricate valid-looking
records. The actor owner must keep those records private and authorize
messages before invoking transitions. Treat compiler-backed execution and
independent review as hard gates; GitHub Actions source-only success is not
guest evidence.
