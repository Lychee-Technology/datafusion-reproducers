# Investigation Guide

Read this guide when isolating a defect, performing git bisect, profiling an algorithm, or evaluating experimental fixes.

## 1. Investigation Principles

An investigation must distinguish:

- Reported observations.
- Independently reproduced observations.
- Candidate causes.
- Confirmed causes.
- Proposed fixes.
- Experimentally validated fixes.

Do not attempt to prove a predetermined hypothesis.

Check current upstream issues and PRs for existing investigations or fixes.

## 2. Root Cause Workflow

1. Recover the original workload.
2. Establish a faithful standalone reproducer.
3. Identify known-good and known-bad revisions.
4. Compare current upstream and relevant release branches.
5. Isolate the affected subsystem.
6. Identify dominant cost centers or incorrect behavior.
7. Establish a causal relationship.
8. Evaluate targeted experimental changes.
9. Prepare a minimal upstream recommendation.

Read [reproducer.md](reproducer.md) and [benchmarking.md](benchmarking.md) for reproduction and measurement requirements.

## 3. Git Bisect

Use automated git bisect when practical.

Example:

```bash
git bisect start
git bisect bad <known-bad-revision>
git bisect good <known-good-revision>
git bisect run /absolute/path/to/check-regression.sh
```

The classification script must use:

- Exit 0: known-good behavior.
- Exit 1: known-bad behavior.
- Exit 125: untestable revision.

Use a calibrated classification threshold.

Repeat noisy measurements when necessary.

Do not classify compilation failures, unsupported APIs, or unrelated errors as performance regressions.

After identifying a candidate first bad commit:

- Compare the commit against its parent.
- Repeat representative measurements.
- Inspect the relevant code changes.
- Verify release-tag ancestry.
- Document skipped commits and ambiguous ranges.

Do not attribute a regression to a PR solely because it merged during the relevant release cycle.

## 4. Profiling

Use suitable tools such as:

- samply.
- Linux perf.
- Flamegraphs.
- Focused microbenchmarks.
- Temporary operation-count instrumentation.

Identify actual dominant cost centers before designing optimizations.

For expression and equivalence-property investigations, consider measuring:

- Expression tree node visits.
- Expression normalization calls.
- Expression property inference calls.
- Fixed-expression checks.
- Structural hashing and equality costs.
- Equivalence class lookups.
- Ordering inference candidates.
- Unique implied orderings.
- Cache reconstruction counts.
- Repeated allocations.
- Physical optimizer rule execution.

Distinguish expensive structural expression hashing from hash-table lookup complexity.

Prefer operation counts when investigating algorithmic scaling.

Keep temporary instrumentation out of production patches unless independently justified.

## 5. Root Cause Confirmation

A root cause requires evidence connecting the suspected mechanism to the observed problem.

Supporting evidence may include:

- A reproducible first bad commit.
- Before/after commit comparison.
- CPU profiles.
- Operation-count measurements.
- Isolated microbenchmarks.
- A targeted experimental patch.
- A demonstrated causal relationship.

A hotspot alone does not necessarily establish the original regression cause.

If evidence is inconclusive, state that explicitly.

## 6. Experimental Fix Location

DataFusion implementation changes belong in a separate DataFusion checkout or fork.

This repository may contain:

- Experiment scripts.
- Exact patch commit references.
- Small documented experimental patches.
- Before/after measurements.
- Reproduction instructions.

Do not turn this repository into a maintained alternative DataFusion implementation.

## 7. Independent Fix Evaluation

Evaluate candidate changes independently before combining them.

For each candidate, record:

- Exact baseline commit.
- Experimental patch or commit.
- Technical hypothesis.
- Expected improvement.
- Actual results.
- Correctness results.
- Remaining limitations.

Record unsuccessful experiments as well as successful ones.

Do not attribute the improvement of a combined patch to individual changes without isolated evidence.

## 8. Preferred Optimization Strategies

Prefer the smallest evidence-supported change.

Potential strategies include:

- Eliminating redundant computation.
- Hash-based deduplication.
- Scope-local memoization.
- Incremental cache updates.
- Dependency-aware worklist computation.
- Improved indexing.
- Avoiding repeated expression tree traversal.

These are candidate techniques, not default implementation requirements.

Only introduce a technique when the measured problem justifies it.

## 9. Architectural Changes

Do not introduce the following without supporting evidence and explicit approval:

- Global caches.
- Broad public API changes.
- Expression interning frameworks.
- New equivalence systems.
- Large optimizer rewrites.
- General-purpose inference engines.

When proposing architectural changes, document:

- Current limitations.
- Alternative solutions.
- Correctness implications.
- Complexity implications.
- Memory costs.
- Implementation and maintenance risks.
- Migration requirements.
- Recommended approach.

## 10. Prohibited Final Fixes

Do not claim a problem is fixed by:

- Arbitrarily limiting expression depth.
- Disabling optimizer rules.
- Silently dropping required ordering properties.
- Weakening correctness guarantees.
- Ignoring errors.
- Skipping problematic workloads.
- Changing benchmark inputs to conceal regressions.
- Hardcoding results.

Clearly identified diagnostic experiments may temporarily change behavior, but those changes must not be presented as final fixes.

## 11. Investigation Deliverables

Produce applicable artifacts:

- Minimal reproducer reference.
- Version comparison.
- First bad commit or inconclusive bisect report.
- CPU profiles.
- Operation-count analysis.
- Scaling analysis.
- Candidate fix comparisons.
- Correctness verification.
- Recommended minimal fix.
- Remaining uncertainties.

For correctness requirements, read [verification.md](verification.md).

For upstream submission preparation, read [upstream.md](upstream.md).
