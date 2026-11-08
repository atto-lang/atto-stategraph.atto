# Native Oreslang StateGraph (sg)

**Status: experimental draft; guest compiler execution not yet verified.**
This is the staged integration after PR #1 merged into main: the typed serial
StateGraph<S> API remains source-compatible, while PR #2 adds a typed
SuperstepGraph<S> with snapshot/patch/superstep semantics. The entire graph engine is authored
in Oreslang, not Python, JavaScript, Java, or an FFI orchestration layer.

## Typed API

The merged v0 API is sg.StateGraph<S> in src/stategraph.ores. This additive, draft execution engine is SuperstepGraph<S> in src/supersteps.ores, with caller-owned application state S. Both are typed, but the two execution APIs are intentionally separate until compiler acceptance and a compatibility migration.
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

## Verification and security

The additive superstep Oreslang smoke program lives in tests/smoke.ores. The merged v0 serial kernel retains its original tests/native fixtures and ci/verify-native.sh. It exercises 46
assertion gates: typed state and patch construction, two-node reducer merge,
fan-in coalescing, snapshot isolation, conflicting writes, bad reducer policies,
post-update routing, bad routes, bounded cycles, invalid graph definitions,
duplicate patch writes, ambiguous END handling and builder immutability.

Run sh ci/verify-supersteps-native.sh with EXPECTED_TREE_SHA (the Git SHA-1 **tree object**,
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
native actor worker scheduling, cancellation, typed errors, deep snapshot
semantics audit, durable checkpoint storage, interrupts, retries, streaming,
dynamic Send, subgraphs, and AI provider adapters. Do not promote this draft to
production before native guest evidence exists.

References: LangGraph StateGraph and Pregel superstep execution.

## Repository ownership and migration (2026-11-08)

This repo is currently `ores-truffle-oreslang/oreslang-sg-stategraph.ores`. The public language name is **AttoLang**; preserve `.ores` compatibility and old repo/package/CLI IDs until a separate compiler-backed and consumer-reviewed change proves replacement.

- **Belongs here:** StateGraph data model, actor-owned state transitions and portable tests.
- **Does not belong here:** global deployment orchestration or host-only false guest proofs.
- **Organization model:** [atto-lang](https://github.com/atto-lang) owns portable language libraries, compilers, tools, tests, core/std and examples. [atto-co](https://github.com/atto-co) separately owns managed hosting, tenant/deployment control, identity, billing and SaaS. Existing similarly named `atto-*` repos should be audited for overlap but are not necessarily transfers of this source identity.
- **Initial proposed move:** this original numeric GitHub repository ID and history into `atto-lang/oreslang-sg-stategraph.ores` retaining the old name. Current migration wave authorizes zero direct moves into `atto-co`. Future product carve-outs require new owner/security approval.

**Safe transfer:** announce in [issue #26](https://github.com/ores-truffle-oreslang/.github/issues/26), follow [private migration draft #25](https://github.com/ores-truffle-oreslang/.github/pull/25). Record exact source SHA/tree, ID, release tags, PRs, packages, dependencies, branch/ruleset protections, target visibility and rights, Actions/runners, App/webhook permissions, secrets, Pages, rollback authority, source/target admins and independent security review. Never mirror private source without explicit authorization. After an approved GitHub ownership transfer verify unchanged ID/tree/history, restore security policy, change consumers separately and run exact-head tests with **nonzero executed steps**. `steps=[]`/`null` is `NOT_EXECUTED`; host or structural tests cannot certify AttoLang guest execution, database safety or actor parity.
