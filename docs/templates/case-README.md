# `<case-slug>`: <Short Symptom-Based Title>

> Replace bracketed/angle-bracketed placeholders and delete sections that do not apply.

## Problem Summary

Describe the observed defect or regression concisely (symptom, affected operator or stage, and impact). Distinguish verified observations from unverified reports or hypotheses.

## Related Upstream Links

- Upstream issue: *(none yet / link)*
- Upstream PR(s): *(none yet / link)*
- Related precedent: *(optional links)*

## Affected Versions & Exact Dependency Revisions

| Configuration | DataFusion Pin | Lockfile / Manifest | Status |
|---|---|---|---|
| Baseline / Unaffected | `=<version>` or `<full-sha>` | `Cargo.lock` | *(e.g., OK)* |
| Affected | `=<version>` or `<full-sha>` | `<manifest or lockfile>` | *(e.g., Reproduces)* |

State exact crate versions, Git commit SHAs, or local checkout patch status. Do not cite moving branch names without resolving the tested SHA.

## Environment & Prerequisites

- Rust toolchain: pinned in `rust-toolchain.toml` (or state exact `rustc --version` / `cargo --version`)
- OS / CPU / RAM: *(relevant when reporting timing measurements)*
- Session / Optimizer configuration: *(any non-default `SessionConfig` or optimizer settings)*

## One-Command Reproduction

Default lightweight verification:

```bash
cd repros/<case-slug>
cargo test --locked
cargo run --release --locked -- --help
```

Minimal reproduction command:

```bash
cd repros/<case-slug>
cargo run --release --locked -- <small-safe-args>
```

<details>
<summary>Workload parameters and extended / heavy runs</summary>

Document CLI flags, safe defaults, and explicit bounded commands for expensive workloads.

</details>

<details>
<summary>Minimal copy-pasteable snippet for upstream reporting</summary>

```rust
// SPDX-License-Identifier: Apache-2.0
// Minimal inline snippet or SQL/plan example when practical.
```

</details>

## Expected vs. Actual Outcome

- **Expected:** *(intended query result, plan shape, or scaling behavior)*
- **Actual:** *(observed failure, wrong result, plan shape, or timing)*
- **Verified Plan Shape:** *(summary of actual optimized logical/physical plan, confirming requested structure survived optimization)*

## Raw Evidence & Methodology

- **Stage isolated:** *(e.g., logical planning, physical planning, or end-to-end execution)*
- **Measurement protocol:** *(warmups, iterations, timeout threshold, release flags)*
- **Evidence artifacts:** *(links to `results/*.csv`, `results/environment.md`, `profiles/`, etc.)*

## Investigation Status & Fix Validation

- Current stage: *(Reproduced / Baseline collected / Root cause identified / Fix validated)*
- Fix validation: *(exact upstream commit SHA, release version, and before/after comparison once available)*

## Known Limitations

Document unsupported configurations, simplifying assumptions made during minimization, or open questions.
