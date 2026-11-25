> **AI agent instructions (organization-wide):** Before working on code, issues, or pull requests, read and follow the [organization `AGENTS.md`](https://github.com/atto-lang/.github/blob/main/AGENTS.md), including its **merge-first stealth-development policy**. Honor any repository-local `AGENTS.md`, explicit holds, and GitHub-enforced rules.

# atto-stategraph.atto

State graph modeling and execution utilities implemented in AttoLang.

## Naming migration and language authority

This repository is maintained at [atto-lang/atto-stategraph.atto](https://github.com/atto-lang/atto-stategraph.atto); use `https://github.com/atto-lang/atto-stategraph.atto.git` for Git remotes and canonical `.atto` source examples. The normative language contract is [atto-spec](https://github.com/atto-lang/atto-spec), with executable guest evidence tracked by [atto-platform-conformance](https://github.com/atto-lang/atto-platform-conformance). Follow current ownership, borrowing, effects, actor, and syntax rules there; do not infer implemented features from a README or unexecuted CI.

## Scope

State transitions, graph evaluation, and declarative application state modeling.

## API and portability principles

- Specify numerical/semantic behavior before assuming support on every backend.
- Document input types, error behavior, shape and memory ownership requirements as applicable.
- Distinguish CPU execution, SIMD, GPU offload, and other target-specific capabilities.

## Verification

Use checked-in tests, documented tolerances, and exact-commit runtime evidence. Host-only or compilation tests are not equivalent to executed AttoLang guest tests. Record backend gaps explicitly.

## Development status

This describes the repository's intended purpose, not a verified list of implemented features. Refer to checked-in code and CI for current functionality and validated commands.

## Related

- [AttoLang](https://github.com/atto-lang)
- [ML conformance](https://github.com/atto-lang/atto-ml-conformance)
- [Language specification](https://github.com/atto-lang/atto-spec)

## Repository ownership and contribution routing

**Belongs here:** Typed state graph structures, transition evaluation, state machines and graph lifecycle utilities written in .atto.

**Belongs elsewhere:** Language actor state and effects belong in atto-spec/compiler backends; app-specific flows belong in demos.

**Security and portability boundary:** Require deterministic transition ordering, bounded graph traversal, cycle handling, cancellation and no stale actor-state references.

AttoLang is the canonical project name; new source, examples and documentation use `.atto` and the `atto-lang` repository organization. This README defines scope, not feature readiness.

**Acceptance:** name exact source SHA/tree, runtime/toolchain, positive and negative checks and execution receipt before claiming support. Host-only tests and empty CI steps do not prove guest execution.

## Legacy provenance and migration guardrails

The historical predecessor `ores-truffle-oreslang/oreslang-sg-stategraph.ores` is archived; the current `atto-lang/atto-stategraph.atto` has a separate numeric GitHub identity. Preserve supported legacy `.ores` inputs and historical package/CLI aliases until compiler-backed replacements are verified; new language source follows the canonical `.atto` [grammar](https://github.com/atto-lang/atto-spec/blob/main/spec/01-source-and-syntax.md) and [ownership contract](https://github.com/atto-lang/atto-spec/blob/main/spec/04-ownership-and-memory.md).

StateGraph data models, actor-owned state transitions and portable tests belong here; global deployment orchestration and host-only substitutes for guest proofs do not. [atto-lang](https://github.com/atto-lang) owns language, portable libraries and tooling; [atto-co](https://github.com/atto-co) separately governs managed hosting, deployment, tenant identity and billing. Further original-ID transfers or product carve-outs require separate owner authorization and independent security review.

Before an authorized transfer, record exact SHA/tree, numeric ID, source/target administrators, access, branch protections, releases, PRs, packages, dependencies, runners, secrets, apps, webhooks, Pages and rollback ownership. Verify identity, history and controls afterward, and retest consumer references. Never mirror private source without authorization. Empty or null steps are NOT_EXECUTED; host or structural checks cannot establish compiled guest execution or parity.
