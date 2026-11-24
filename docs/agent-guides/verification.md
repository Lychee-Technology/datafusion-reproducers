# Verification Guide

Read this guide when writing code, modifying tests, validating reproducers, or evaluating DataFusion fixes.

## 1. Correctness First

Performance improvements must preserve query semantics and optimizer correctness.

A faster but incorrect query plan is not acceptable.

A reproducer must verify the expected triggering conditions rather than merely execute successfully.

## 2. Rust Code Quality

- Follow idiomatic Rust conventions.
- Prefer straightforward and readable implementations.
- Avoid unnecessary dependencies, cloning, and allocations.
- Provide actionable error messages.
- Avoid unsafe code unless explicitly justified.
- Do not suppress compiler or Clippy warnings without a documented reason.
- Avoid optimizing unrelated reproducer code at the expense of clarity.

Shell scripts must:

- Quote paths correctly.
- Propagate failures.
- Bound expensive workloads.
- Distinguish build failures from measured regressions.
- Produce actionable diagnostic output.

## 3. Reproducer Verification

Verify applicable properties:

- Input data and schema.
- Expected logical and physical plan shape.
- Relevant expression structure.
- Input ordering.
- Partitioning.
- Optimizer configuration.
- Expected result or failure mode.

For correctness bugs, assert the expected result and capture the actual incorrect result.

For performance bugs, include a functional or structural check independent of wall-clock time.

Do not accept successful execution as proof that the intended workload was exercised.

## 4. Ordering and Equivalence Correctness

For changes involving ordering or equivalence inference, evaluate relevant cases covering:

| Area | Cases |
|---|---|
| Ordering direction | ASC, DESC |
| Null ordering | NULLS FIRST, NULLS LAST |
| Nullability | Nullable expressions |
| Monotonicity | Strict and non-strict monotonic functions |
| Volatility | Volatile functions and UDFs |
| Constants | Global and per-partition constants |
| Expressions | Aliases and casts |
| Partitioning | Single and multiple partitions |
| Repartition | Ordering preservation |
| Operators | GROUP BY and window functions |
| Inference | Different equivalence insertion orders |

Ensure that required sorts are not incorrectly eliminated.

Verify that any claimed ordering or grouping property remains valid.

## 5. Cache Correctness

For memoization and cache changes, establish:

- Cache ownership.
- Cache lifetime.
- Cache key semantics.
- Context dependencies.
- Invalidation conditions.
- Mutation and update behavior.
- Memory usage implications.

Do not cache context-dependent properties without a valid invalidation strategy.

Pay particular attention to changes in equivalence groups, pinned expressions, constants, ordering heads, and schema context.

## 6. Standard Verification Commands

Run applicable commands from the relevant case directory:

```bash
cargo fmt --check

cargo check --locked --all-targets

cargo clippy --locked --all-targets -- -D warnings

cargo test --locked

cargo build --release --locked
```

Run the documented small release-mode smoke reproduction separately.

Adapt commands to the actual case and toolchain.

These commands describe verification conventions, not a guarantee that every case or CI workflow already exists.

Report unavailable, skipped, or inapplicable checks with reasons.

## 7. Upstream Implementation Tests

For DataFusion implementation changes, run applicable upstream tests:

- Unit tests.
- Integration tests.
- SQL logic tests.
- Equivalence property tests.
- Sort fuzzers.
- Targeted regression tests.
- Existing relevant benchmarks.

Follow the instructions and supported commands in the target DataFusion checkout.

Do not claim comprehensive verification when only a subset has been executed.

## 8. CI Design

Routine CI should prioritize:

- Formatting.
- Compilation.
- Linting.
- Deterministic tests.
- Small smoke workloads.

Do not introduce hard wall-clock assertions such as:

```rust
assert!(elapsed.as_secs() < 1);
```

Prefer deterministic operation-count assertions when appropriate.

Run expensive benchmarks separately.

Do not weaken tests, delete failing assertions, or suppress relevant warnings merely to obtain green CI.

## 9. Verification Report

For every applicable acceptance criterion, provide a status:

- Satisfied.
- Partially satisfied.
- Not satisfied.
- Blocked.
- Not applicable.

Link each satisfied criterion to concrete evidence.

Record:

- Exact command executed.
- Actual outcome.
- Relevant source revision.
- Test or evidence location.
- Remaining limitations.

Never claim a check passed unless it was actually executed successfully.

Read [benchmarking.md](benchmarking.md) for performance verification.

Read [workflow.md](workflow.md) for final task handoff.
