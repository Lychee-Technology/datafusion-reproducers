# Repository Workflow Guide

Read this guide when modifying repository files, managing GitHub work, recording evidence, or handing off a completed task.

Also follow the root AGENTS.md and [non-code-rules.md](non-code-rules.md) for repository-specific PR rules, Git conventions, and non-code artifact requirements.

## 1. Issue-driven Development

Before implementation:

1. Read the target issue and its comments.
2. Identify approved decisions.
3. Verify dependencies and prerequisites.
4. Inspect existing implementations.
5. Determine applicable acceptance criteria.
6. Load relevant task-specific guides.

Keep work focused on the approved issue.

Preserve unrelated changes.

Do not silently expand scope.

When a prerequisite is unresolved, record the blocker rather than bypassing it.

## 2. Git Workflow

Use task-specific branches by default.

Follow repository branch protections and existing development conventions.

Keep commits focused and reviewable.

Use descriptive commit messages, for example:

```text
feat: add deep expression planning reproducer
bench: record cross-version planning baselines
docs: document regression bisect results
test: add ordering correctness controls
fix: preserve isolated dependency resolution
```

Do not:

- Force-push shared branches.
- Rewrite shared history.
- Delete branches without authorization.
- Revert unrelated changes.
- Commit generated build outputs or private configuration.

## 3. Pull Requests

Each PR should explain:

- Problem being addressed.
- Related issue.
- Approved scope.
- Implementation approach.
- Verification performed.
- Actual results.
- Remaining limitations and risks.

Performance-related changes require relevant before/after evidence.

Avoid unrelated refactoring and formatting changes.

## 4. Issue Management

Keep issue tracking accurate.

When reporting implementation or investigation progress:

- Link actual commits or PRs.
- Provide acceptance evidence.
- Record unresolved blockers.
- Identify remaining dependencies.
- Distinguish implementation from verification.

Do not close an issue merely because an implementation PR exists.

Issue closure requires verified acceptance criteria and appropriate authorization.

Do not invent native GitHub dependency relationships, sub-issue relationships, labels, or status transitions.

## 5. Evidence Organization

Store evidence alongside the corresponding case.

Illustrative structure:

```text
repros/<case-slug>/
├── results/
│   ├── baseline.csv
│   ├── environment.md
│   ├── bisect.md
│   ├── analysis.md
│   └── experiments/
└── profiles/
```

Create only the files required by the investigation.

Every experiment should be traceable to:

- Exact reproducer revision.
- Exact DataFusion revision or dependency configuration.
- Workload definition.
- Execution command.
- Environment.
- Raw result.

Use [benchmarking.md](benchmarking.md) for measurement-specific requirements.

## 6. Historical Evidence

Preserve original observations.

Do not overwrite historical baselines to reflect improved performance.

Keep before-fix and after-fix results distinguishable.

Name evidence artifacts by version, revision, workload, and experiment identity, or provide an unambiguous manifest.

Derived summaries must be reproducible from raw observations where practical.

Clearly distinguish measured values, estimates, targets, and illustrative examples.

Use immutable commit permalinks when referring to published evidence.

## 7. Artifact Management

Do not commit:

- Cargo target directories.
- Compiled binaries.
- Large temporary profiling outputs.
- Core dumps.
- Unnecessary generated files.
- Local machine configuration.

Keep useful profiles compact and sanitized.

For large evidence artifacts stored elsewhere, provide stable references and reproducible generation instructions.

## 8. Documentation

Write repository-facing documentation in English, except where the existing [non-code-rules.md](non-code-rules.md) explicitly permits canonical Chinese documentation with the .cn.md suffix.

Use precise technical language.

Avoid unsupported claims and promotional wording.

The root README should remain a concise repository entry point and case index.

Case-specific investigation details belong in the corresponding case directory.

Keep reproduction commands, dependency versions, and evidence references synchronized with the implementation.

## 9. Licensing

The repository uses Apache License 2.0.

Preserve the existing root LICENSE.

Use accurate copyright notices where applicable.

Original source files may use:

```rust
// SPDX-License-Identifier: Apache-2.0
```

Do not invent copyright ownership.

Do not use ASF-specific contribution headers for independent original files unless applicable.

When copying or modifying upstream code:

- Preserve applicable copyright notices.
- Preserve applicable license notices.
- Preserve required NOTICE attribution.
- Identify modifications where required.

## 10. Public Repository Security

Treat committed content as public.

Never commit:

- Secrets or access tokens.
- SSH keys or credentials.
- Proprietary downstream source code.
- Customer information.
- Private datasets.
- Unnecessary personal information.

Sanitize profiles, logs, environment reports, and diagnostic output.

Inspect generated artifacts for accidental disclosure before publication.

## 11. Authorization Boundaries

Do not perform unauthorized external actions.

Explicit authorization is required for:

- Upstream issue, comment, or PR publication.
- Upstream backport requests.
- PR merges.
- Release or crate publication.
- Downstream repository modifications.
- Unrelated cross-repository writes.

Preparing an artifact does not authorize publishing it.

## 12. Acceptance Review

Before reporting completion:

- Re-read the issue acceptance criteria.
- Verify each criterion against actual evidence.
- Confirm prerequisite states where applicable.
- Identify unresolved requirements.
- Report checks that were not performed.

Do not conceal incomplete work behind a successful implementation summary.

## 13. Final Agent Handoff

Use the applicable sections, not a mechanical checklist. Follow [non-code-rules.md](non-code-rules.md) for reader-focused prose and publication.

```markdown
## Summary

## Issue and Scope

## Implementation

## Verification

## Benchmark Results

## Acceptance Criteria

## Changed Files

## Upstream Status

## Remaining Risks and Blockers

## Recommended Next Steps
```

For acceptance criteria, use accurate statuses:

- Satisfied.
- Partially satisfied.
- Not satisfied.
- Blocked.
- Not applicable.

Include:

- Commands actually executed.
- Actual test outcomes.
- Exact revisions tested.
- Evidence artifact locations.
- Relevant implementation or PR links.
- Actions requiring approval.

Include changed paths only when useful for evidence, review focus, or handoff; do not narrate the diff.

Do not report prepared, proposed, or unverified work as completed.
