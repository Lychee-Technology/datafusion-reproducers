# Reproducer Guide

Read this guide when creating or modifying a reproduction case, defining workloads, or managing Rust and DataFusion dependencies.

## 1. Case Structure

Each reproducer must be an independent Cargo project under:

```text
repros/<case-slug>/
├── README.md
├── Cargo.toml
├── Cargo.lock
├── rust-toolchain.toml
├── src/
├── tests/
├── sql/
├── scripts/
├── results/
└── profiles/
```

Create optional directories only when needed.

Each case must provide:

- An independent Cargo manifest.
- A committed Cargo.lock.
- A pinned Rust toolchain or documented reproducible equivalent.
- A case-specific README.
- Minimal source code and synthetic input.
- Lightweight smoke or correctness tests where feasible.

Do not require a shared Cargo workspace or common DataFusion version.

## 2. Naming

Use descriptive kebab-case names based on observed symptoms.

Good examples:

- `deep-expression-planning`
- `union-order-by-planning`
- `window-expression-scaling`
- `incorrect-null-ordering`

Avoid vague names or names that assume an unverified root cause.

## 3. Standalone Execution

A reproducer must not depend on:

- LTSeq or another downstream application.
- Proprietary source code.
- Private datasets.
- External databases or cloud services.
- Credentials.
- Undocumented environment configuration.

Prefer generated data, MemTable, EmptyTable, inline SQL, or direct logical/physical plan construction.

Use the smallest input that preserves the triggering conditions.

## 4. Faithfulness to the Original Workload

Recover and understand the original workload before minimizing it.

Preserve relevant characteristics:

- Expression structure and depth.
- Logical and physical plan shape.
- Projection depth and width.
- Input ordering and partitioning.
- Data types and nullability.
- Function monotonicity and volatility.
- Session and optimizer configuration.
- Relevant equivalence properties.

Inspect the actual optimized plan. Requested expression or projection depth may not survive optimization.

Verify that the minimized workload exhibits the same relevant behavior as the original.

If minimization removes the symptom, record that result as negative evidence.

Do not substitute a different defect without explicitly identifying it.

## 5. Execution Interface

Prefer a simple CLI when configurable workloads are needed.

An illustrative interface:

```bash
cargo run --release --locked -- \
    --depth 100 \
    --mode order-by
```

Expose only parameters that contribute to the investigation, such as:

- Expression depth.
- Projection depth.
- Retained intermediate columns.
- Operator mode.
- Input ordering.
- Partition count.
- Iterations.
- Output format.

Provide small, safe defaults.

Expensive workloads must require explicit selection and bounded execution.

Do not introduce a general-purpose CLI framework without a demonstrated need.

## 6. Dependency Management

### Published Releases

Pin DataFusion releases exactly:

```toml
[dependencies]
datafusion = "=56.0.0"
```

### Upstream Revisions

Pin Git dependencies by full commit SHA:

```toml
[dependencies]
datafusion = {
    git = "https://github.com/apache/datafusion.git",
    rev = "<full-commit-sha>"
}
```

Resolve moving branch names to immutable revisions before recording experimental results.

### Local Checkouts

Local DataFusion checkouts may be used for experiments.

Record:

- Upstream base commit.
- Dirty or clean working-tree state.
- Experimental patch identity.
- Resolved dependency source.

Clearly label results from modified checkouts.

### Dependency Consistency

Verify that DataFusion crates belong to the intended compatible dependency set.

Use `cargo tree` and `cargo metadata` when appropriate.

Do not accidentally compare mixed DataFusion versions or independently drifting dependencies.

Document unavoidable dependency differences as potential confounding variables.

### Lockfiles

Commit Cargo.lock for executable cases.

Preserve reproducible dependency resolution for each tested configuration.

Use separate manifests, generated configurations, isolated directories, or another documented approach for version comparisons.

Do not silently overwrite the canonical baseline lockfile.

### Package Metadata

```toml
[package]
publish = false
license = "Apache-2.0"
```

Reproducer crates are not intended for crates.io publication.

## 7. Case README

Document:

1. Problem summary.
2. Related upstream issues and PRs.
3. Affected DataFusion versions.
4. Prerequisites and toolchain.
5. Minimal reproduction commands.
6. Expected and actual behavior.
7. Workload parameters.
8. Verified results and methodology.
9. Investigation status.
10. Known limitations.
11. Fix validation, when available.

Provide a small copy-pasteable upstream example whenever practical.

Update the root README index when introducing a new case.

## 8. Acceptance Checklist

- [ ] Runs from a clean checkout.
- [ ] Requires no private dependencies or datasets.
- [ ] Preserves the relevant triggering conditions.
- [ ] Uses pinned, reproducible dependencies.
- [ ] Documents expected and actual behavior.
- [ ] Provides a lightweight verification command.
- [ ] Has clear limitations and known unsupported configurations.

For timing experiments, additionally read [benchmarking.md](benchmarking.md).

For code and correctness checks, read [verification.md](verification.md).
