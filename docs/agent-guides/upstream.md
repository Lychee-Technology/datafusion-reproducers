# Upstream Contribution Guide

Read this guide when preparing Apache DataFusion contributions, coordinating upstream investigations, or validating upstream fixes and releases.

## 1. Upstream First

The preferred resolution for DataFusion defects is an accepted upstream fix.

Keep external reproducers and permanent upstream tests separate:

| External Reproducer | Upstream Benchmark or Test |
|---|---|
| Cross-version comparisons | Current upstream implementation |
| Investigation-specific tooling | Focused, maintainable workload |
| Bisect and profiling | Long-term regression protection |
| Experimental fix evaluation | Permanent project infrastructure |
| Downstream validation | Upstream correctness verification |

Do not duplicate upstream work when an existing fix can be verified.

Follow the current DataFusion contributor guidelines and target repository instructions.

## 2. Contribution Lifecycle

### Stage 1 — Reproduction

Establish a standalone MRE and independently verified observations.

### Stage 2 — Version Comparison

Compare exact affected and unaffected releases.

Collect sufficient evidence to demonstrate the reported problem.

### Stage 3 — Upstream Issue

Check existing upstream issues and pull requests.

Prepare an English report containing:

- Descriptive, symptom-based title.
- Expected and actual behavior.
- Exact DataFusion versions and revisions.
- Minimal reproducible code.
- Reproduction commands.
- Relevant configuration and environment.
- Verified performance or correctness evidence.
- Immutable reproducer commit permalink.
- Related upstream issues.
- Explicitly identified hypotheses.

Do not present candidate causes as confirmed causes.

Do not delay an otherwise credible regression report solely because bisect or root cause analysis is incomplete.

### Stage 4 — Benchmark Contribution

When no suitable benchmark exists, prepare a focused benchmark-only patch.

Use existing upstream benchmark infrastructure.

Keep default workloads reasonably sized.

Provide instructions for running larger cases separately.

Do not mix unrelated optimizer behavior changes into a benchmark-only contribution.

### Stage 5 — Root Cause and Targeted Fix

Use [investigation.md](investigation.md) to establish the cause and select a minimal fix.

Include:

- Confirmed technical problem.
- Explanation of the change.
- Correctness tests.
- Before/after evidence.
- Complexity or operation-count analysis where relevant.
- Remaining limitations.

Prefer separate benchmark and fix PRs unless an approved scope or upstream maintainer decision justifies combining them.

### Stage 6 — Upstream Review

Respond to maintainer feedback using technical evidence.

Keep proposed changes focused.

Distinguish:

- Local experimental patch.
- Prepared contribution.
- Submitted PR.
- Approved PR.
- Merged fix.

Do not assume a PR is merged because it received an approving review.

### Stage 7 — Backport and Release Validation

Determine whether a backport is justified.

Prepare a backport request containing:

- Original regression impact.
- Upstream fix reference.
- Relevant release branch.
- Compatibility and correctness risks.
- Verification evidence.

Verify actual:

- Upstream merge commit.
- Release branch inclusion.
- Release-tag ancestry.
- Published dependency version.
- Reproducer behavior against the fixed revision.

A fix merged into main is not necessarily available in a released version.

Do not guarantee upstream release schedules.

### Stage 8 — Downstream Validation

Validate the original downstream workload against the verified upstream fix.

Track dependency upgrades and integration work in the appropriate downstream repository.

Do not silently substitute the external reproducer for downstream integration verification.

## 3. Upstream Issue Template

```markdown
## Describe the bug

## Expected behavior

## Actual behavior

## DataFusion versions

## Minimal reproduction

## Reproduction commands

## Environment and configuration

## Verified results

## Investigation status

## Related issues and pull requests

## Additional evidence
```

Use only applicable sections.

Include a stable commit permalink for external reproduction code.

## 4. Upstream PR Checklist

- [ ] Existing upstream work has been checked.
- [ ] Scope is focused.
- [ ] Related issue is linked.
- [ ] Target revision is identified.
- [ ] Benchmark or regression test is appropriate.
- [ ] Correctness has been verified.
- [ ] Before/after evidence is provided when applicable.
- [ ] Current upstream contribution requirements are followed.
- [ ] Licensing and source-header requirements are satisfied.
- [ ] Remaining risks are documented.

## 5. Licensing

When preparing DataFusion contributions:

- Follow DataFusion's own source-header conventions.
- Preserve applicable copyright and license notices.
- Preserve required NOTICE attribution.
- Do not copy proprietary downstream code.
- Do not misrepresent third-party code as original work.

## 6. Authorization

Preparing a contribution is not authorization to publish it.

Without explicit authorization, do not:

- Create upstream issues.
- Post upstream comments.
- Open upstream PRs.
- Request backports.
- Merge changes.
- Publish releases.
- Modify downstream repositories.

After an authorized action, record the actual resulting issue, PR, or commit link.

## 7. Resolution Criteria

Distinguish the following states:

1. Defect reproduced.
2. Root cause identified.
3. Candidate fix validated.
4. Upstream contribution submitted.
5. Upstream fix merged.
6. Fix released.
7. Downstream workload validated.

Do not treat an earlier state as proof of a later one.

Close investigation or resolution trackers only when their specific acceptance criteria and authorization requirements are satisfied.
