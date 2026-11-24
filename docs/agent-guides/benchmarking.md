# Benchmarking Guide

Read this guide when measuring performance, comparing versions, analyzing scaling behavior, or evaluating performance improvements.

## 1. Measurement Boundary

Explicitly identify the operation being measured:

- SQL parsing.
- SQL-to-logical-plan conversion.
- Logical optimization.
- Initial physical plan creation.
- Physical optimization.
- Query execution.
- End-to-end processing.

Do not describe end-to-end latency as planning latency.

EXPLAIN ANALYZE alone is not sufficient evidence of planning latency because it also executes the query.

Keep compilation, dependency downloads, and unrelated initialization outside the measured interval.

Where APIs permit, measure individual planning stages separately.

## 2. Build Configuration

Use optimized builds:

```bash
cargo build --release --locked
```

Record:

- Rust and Cargo versions.
- Target architecture.
- Cargo features.
- Build profile.
- Compiler flags.
- DataFusion dependency revisions.
- Session and optimizer configuration.

Do not present debug-build measurements as release-build performance.

Use comparable build configurations across versions.

## 3. Experimental Controls

Keep these conditions consistent:

- Hardware and operating system.
- Input data.
- Query workload.
- Session configuration.
- Partition count.
- Measurement boundary.
- Build configuration.
- Timeout policy.

Document unavoidable differences.

Use warmup runs and repeated samples where practical.

Report median and variability rather than only the fastest result.

Build each configuration before starting timed measurements.

## 4. Independent Workload Dimensions

Distinguish:

| Dimension | Meaning |
|---|---|
| Expression depth | Depth of an expression tree |
| Plan depth | Number of nested plan nodes |
| Expression width | Number of retained expressions |
| Ordering count | Number of known or required orderings |
| Equivalence class size | Number of equivalent expressions |
| Partition count | Number of physical partitions |

Do not assume that these dimensions are interchangeable.

Vary one relevant dimension at a time when isolating complexity.

Inspect actual optimized plan shapes rather than assuming the requested workload structure survives optimization.

## 5. Control Workloads

Include relevant controls:

- Small and shallow expressions.
- Queries without ORDER BY or GROUP BY.
- Sorted and unordered inputs.
- Single and multiple partitions.
- Monotonic and non-monotonic functions.
- Workloads not expected to benefit from the proposed fix.

Control workloads must help distinguish the suspected mechanism from unrelated performance effects.

## 6. Timeouts

Bound potentially expensive experiments.

Use explicit result statuses:

```text
ok
timeout
error
skipped
unsupported
```

Record the timeout threshold and termination reason.

Never convert incomplete experiments into successful measurements.

Do not invent elapsed times for timeouts.

Keep known expensive workloads out of default CI.

## 7. Cross-Version Comparisons

For version regressions, compare:

1. Known-good release.
2. Known-bad release.
3. Relevant maintained release branch, where available.
4. Current upstream main.

Record exact release versions, commit SHAs, and dependency resolution.

Do not assume that a reported regression remains present on main.

Use the same reproducer and comparable configuration across versions.

Follow [reproducer.md](reproducer.md) for dependency isolation.

## 8. Scaling Analysis

Use multiple workload sizes.

Where appropriate:

- Measure geometric or otherwise informative size sequences.
- Record raw observations.
- Count algorithmic operations.
- Distinguish fixed overhead from size-dependent work.
- Account for timeout-censored observations.
- Compare before/after scaling trends.
- Analyze memory usage and allocation behavior.

An empirical scaling exponent is not proof of formal asymptotic complexity.

Do not describe observed cubic growth as proven O(n³) complexity without supporting algorithmic analysis.

Do not extrapolate beyond measured data without clearly identifying the result as an estimate.

## 9. Performance Evidence

Store raw data in a machine-readable format such as CSV or JSON.

Recommended fields include:

```text
experiment_id
datafusion_version
datafusion_commit
reproducer_commit
workload
mode
expression_depth
projection_depth
expression_width
partitions
iteration
measurement_stage
elapsed_ms
timeout_ms
status
```

Store environment and configuration metadata alongside the results.

Every reported measurement must be traceable to:

- An exact workload.
- An exact source revision.
- A dependency configuration.
- A measurement command.
- An execution environment.

Keep original samples and derive summaries reproducibly.

Follow [workflow.md](workflow.md) for evidence storage and publication.

## 10. Fix Evaluation

Use identical or explicitly comparable conditions for baseline and candidate fixes.

Report:

- Absolute before/after timings.
- Relative improvement.
- Scaling behavior.
- Small-workload performance.
- Relevant memory or allocation changes.
- Remaining regressions.
- Correctness test outcomes.

Record unsuccessful experiments.

Do not select only favorable results.

## 11. CI Policy

Do not introduce brittle wall-clock assertions into routine CI.

Prefer:

- Deterministic correctness tests.
- Structural plan assertions.
- Stable operation-count checks where appropriate.
- Dedicated performance benchmarks.
- Explicitly selected extended workloads.

Performance targets are engineering objectives, not automatically CI acceptance thresholds.

Read [investigation.md](investigation.md) when measurements indicate a regression requiring root cause analysis.
