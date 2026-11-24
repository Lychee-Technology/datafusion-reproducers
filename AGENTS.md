# AGENTS.md

## Project Mission

This repository is an independent collection of standalone reproducible cases, correctness regressions, performance benchmarks, and investigation tools for Apache DataFusion.

Its goals are to:

- Reproduce DataFusion defects independently of downstream applications.
- Investigate correctness and performance regressions.
- Produce independently verifiable technical evidence.
- Facilitate high-quality upstream contributions.
- Validate upstream fixes and releases against original workloads.

This repository is maintained by Lychee Technology. It is not an official Apache Software Foundation project.

The primary deliverable is trustworthy evidence, not a general-purpose benchmarking framework.

## Core Principles

1. **Correctness First** — Never sacrifice query semantics for performance.
2. **Reproducibility First** — Every reported result must be independently reproducible.
3. **Evidence over Assumptions** — Distinguish reported observations, verified facts, hypotheses, and confirmed causes.
4. **Minimalism** — Prefer the smallest faithful reproducer and the smallest correct fix.
5. **Upstream First** — Prefer accepted upstream fixes over permanently maintained private patches.
6. **Scope Discipline** — Implement only the approved task and preserve unrelated work.

Never fabricate measurements, profiles, test results, commit SHAs, or upstream status.

## Progressive Disclosure

This file contains globally applicable instructions. Detailed instructions are organized into task-specific guides under `docs/agent-guides/`.

Read the applicable guides before starting the corresponding work.

| Task | Required Guide |
|---|---|
| Creating or modifying a reproducer | [reproducer.md](docs/agent-guides/reproducer.md) |
| Managing Rust and DataFusion dependencies | [reproducer.md](docs/agent-guides/reproducer.md) |
| Benchmarking or analyzing scaling | [benchmarking.md](docs/agent-guides/benchmarking.md) |
| Git bisect, profiling, or root cause analysis | [investigation.md](docs/agent-guides/investigation.md) |
| Designing or evaluating experimental fixes | [investigation.md](docs/agent-guides/investigation.md) |
| Writing code, tests, or validating correctness | [verification.md](docs/agent-guides/verification.md) |
| Preparing upstream issues, benchmarks, or PRs | [upstream.md](docs/agent-guides/upstream.md) |
| Backport, release, or downstream validation | [upstream.md](docs/agent-guides/upstream.md) |
| Repository changes, evidence, GitHub operations, or task handoff | [workflow.md](docs/agent-guides/workflow.md) |

Multiple guides may apply to the same task. Load their union when necessary.

Do not read every guide by default. Load additional guides when the task scope changes or a referenced procedure becomes relevant.

Also read the relevant issue, approved decisions, case README, and applicable nested AGENTS.md files.

## Repository Boundaries

- Keep standalone executable Cargo projects under `repros/<case-slug>/`.
- Each case owns its dependency versions, lockfile, toolchain, documentation, and evidence.
- Do not impose a shared Cargo workspace or a common DataFusion version.
- Keep DataFusion implementation changes in a separate upstream checkout or fork.
- Do not modify downstream production code as part of work in this repository.
- Do not build a permanent alternative DataFusion implementation.
- Use Apache-2.0 and preserve applicable third-party attribution.
- Write repository-facing documentation and comments in English.

Inspect the actual repository before assuming that planned files or infrastructure exist.

## Before Starting

1. Read the target issue, comments, approved decisions, dependencies, and acceptance criteria.
2. Inspect the current repository state.
3. Load the task-specific guides.
4. Identify prerequisites, deliverables, and verification requirements.
5. Check related reproductions and upstream work where applicable.

Do not bypass unresolved dependency gates.

Escalate material architectural decisions or conflicting requirements rather than silently making unapproved changes.

## Hard Constraints

- Do not introduce private data, credentials, or proprietary downstream code.
- Do not misrepresent a timeout, skipped experiment, or unexecuted test as a successful result.
- Do not weaken correctness guarantees, disable optimizer rules, or arbitrarily cap recursion as a final performance fix.
- Do not introduce brittle wall-clock assertions into routine CI.
- Do not perform broad architectural rewrites without approval.
- Do not publish upstream issues, comments, PRs, or backport requests without explicit authorization.
- Do not merge, release, publish crates, or perform unauthorized cross-repository writes.
- Do not close issues without verified acceptance criteria and appropriate authorization.
- Do not force-push or rewrite shared Git history.

## Definition of Done

A task is complete only when its acceptance criteria have been verified.

Report:

- Implemented scope and changed files.
- Commands actually executed and their outcomes.
- Evidence supporting each acceptance criterion.
- Exact revisions and artifact locations for performance claims.
- Remaining risks, blockers, and unverified assumptions.
- Actions requiring additional authorization.

A prepared patch, successful local test, open upstream PR, merged fix, released fix, and downstream-validated fix are distinct states.

Never treat one state as evidence of another.

## Non-code artifacts

Issues, PR descriptions, specs, plans, reviews, and every other non-code artifact give readers the context and judgment the diff cannot, not a narrated diff or filler,
and are published in full on GitHub. The full rules: docs/agent-guides/non-code-rules.md

## PR rules

- Do not merge a PR unless I explicitly ask you to.
- When reviewing a PR, post everything (findings, spec and standards checks, assessment, observations, verification, summary) as one comment on the PR.
- When I ask you to merge a PR, squash-merge by default unless I ask for something else.
- After a PR is merged, clean up local branches and worktrees, fast-forward main, then update and close related issues.

## Git conventions

Never include AI attribution in commit messages, PR titles, or PR descriptions, in any form. That means no

- `Co-Authored-By: Claude`
- `Generated with ...` footers
- sign-offs or footers naming an LLM or AI agent (OpenAI, GPT, Claude, Anthropic, and the like)
- `Claude-Session:` trailers or session URLs (`https://claude.ai/code/session_...`), even when a tool inserts them automatically

When squash-merging, write a clean commit message that describes only the change itself.
