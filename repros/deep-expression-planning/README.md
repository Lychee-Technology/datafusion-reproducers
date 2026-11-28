# `deep-expression-planning`: Planning time of a deep computed sort or group key

## Problem Summary

On DataFusion 56.0.0, physical planning of a `DISTINCT`, `GROUP BY` or `ORDER BY` whose key is a deeply nested computed column, next to the column it is computed from, grows much faster with the expression's depth than on 55.0.0. Nothing needs to execute: `create_physical_plan` alone is slow.

LTSeq reported it while moving to 56 ([Lychee-Technology/ltseq#296](https://github.com/Lychee-Technology/ltseq/issues/296), [PR #423](https://github.com/Lychee-Technology/ltseq/pull/423)): a sorted `distinct()` over `a + 1 + 1 + ...` took 88 s at 200 levels against 0.44 s on 55, and timed out at 500. Those LTSeq numbers are end-to-end and were not re-measured here. This case reproduces the planning slowdown without LTSeq; see [Verified Results](#verified-results).

## Related Upstream Links

- Upstream issue: *(none yet; filing needs authorization, tracked in #6)*
- Possibly related (not established as causes): apache/datafusion#24478 (projection equivalence recomputation), #26853, #26747, #24698, #27599
- Planning-performance precedents: apache/datafusion#13748, #17261, #19795

## Affected Versions & Exact Dependency Revisions

| Configuration | DataFusion pin | Release tag commit | Build | Status |
|---|---|---|---|---|
| Baseline | `datafusion = "=55.0.0"` (crates.io) | `d5552342012888b7d1a3ab88d92e3d292fc0cde0` | `--no-default-features --features df55` | Not affected |
| Affected | `datafusion = "=56.0.0"` (crates.io) | `7e7ae72a820e2bf87da1205b96639fba334ed2f7` | default (`df56`) | Reproduces |

Both pins resolve in the one committed `Cargo.lock` (arrow 59.3.3 / sqlparser 0.62.0 for 55, arrow 60.2.0 / sqlparser 0.63.0 for 56). A build compiles exactly one of them; enabling both or neither is a compile error. The tag commits are those of the upstream release tags; the measured code is the published crates.

`=55.0.0` pins only the `datafusion` facade. Its requirements on `datafusion-common`, `datafusion-physical-plan` and the other sub-crates are caret requirements, so a fresh resolution picks 55.3.0 for them and silently mixes two releases. The committed lockfile pins all 31 crates of each release to exactly 55.0.0 or 56.0.0, and `tests/lockfile.rs` fails if any other DataFusion version appears. Always build with `--locked`. If the lockfile has to be regenerated, repeat `cargo update -p <crate>@55.3.0 --precise 55.0.0` over the drifted crates until none is left (each pass frees the crates whose dependents are already back on 55.0.0).

## Environment & Prerequisites

- Rust 1.97.1, pinned in `rust-toolchain.toml`; if rustup does not install it automatically, run `rustup toolchain install 1.97.1`. DataFusion 56 needs Rust 1.95 or newer.
- No network services, datasets or credentials. The input is a generated `MemTable` with two `Int64` columns and two rows per partition.
- Session: `SessionConfig::new().with_target_partitions(<partitions>)`; every other option is the default.

## One-Command Reproduction

```bash
cd repros/deep-expression-planning
cargo run --release --locked                                  # DataFusion 56.0.0, depth 25
cargo run --release --locked --no-default-features --features df55 --target-dir target/df55   # 55.0.0
```

The second command uses its own target directory so the two builds do not replace each other's binary. Lightweight checks (no timing assertions):

```bash
cargo test --locked
cargo test --locked --no-default-features --features df55 --target-dir target/df55
```

<details>
<summary>Workload parameters and heavy runs</summary>

```text
--depth N          levels of each computed expression, column included [25]
--projections N    stacked projections, each adding --depth levels [1]
--retain           keep every intermediate computed column in the output
--key-only         output only the last computed column (control)
--mode M           distinct | group-by | order-by | project [distinct]
--input I          sorted | unsorted (declared ordering on `a`) [sorted]
--partitions N     table partitions and target_partitions [2]
--iterations N     measured planning runs [5]
--warmup N         unmeasured runs before them [1]
--timeout-secs N   stop with status `timeout` (exit 124) after N seconds [60]
--format F         text | csv [text]
--explain          print the SQL, plan shape and plans, then exit
```

Depth counts the column as one level, as LTSeq does: depth 3 is `a + 1 + 1`. The defaults plan in about 20 ms on 56. Heavy cases, each bounded by its timeout:

```bash
cargo run --release --locked -- --depth 200 --iterations 1 --warmup 0 --timeout-secs 120   # ~25 s on 56
cargo run --release --locked -- --depth 500 --iterations 1 --warmup 0 --timeout-secs 60    # times out on 56
scripts/verify-versions.sh            # the full 55/56 matrix below, into results/verification.csv
```

Planning runs on a thread with a 1 GiB stack (reserved, not committed), because planning recurses once per expression level. The CLI cannot interrupt planning, so on timeout it exits the process.

</details>

<details>
<summary>Minimal copy-pasteable example for the upstream report</summary>

[`examples/upstream_mre.rs`](examples/upstream_mre.rs) depends on nothing but `datafusion` and `tokio`; drop its `use deep_expression_planning::datafusion;` line when copying it out.

```bash
cargo run --release --locked --example upstream_mre -- 100
cargo run --release --locked --no-default-features --features df55 --target-dir target/df55 --example upstream_mre -- 100
```

The query it plans, with `depth - 1` additions, over a two-partition table declared sorted on `a`:

```sql
SELECT DISTINCT a, b, s FROM (SELECT a, b, a + 1 + 1 + ... + 1 AS s FROM t)
```

</details>

## How the Workload Was Derived

The original operation is LTSeq's deep-plan stack test, `py-ltseq/tests/test_expression_depth.py::test_operations_on_a_deep_plan_on_a_small_thread`, on the table `{"a": [1, 2, 3], "b": [1, 1, 2]}`:

```python
t.sort("a").derive(s=lambda r: r.a + 1 + 1 + ...).distinct().count()   # "sorted"
t.derive(s=lambda r: r.a + 1 + 1 + ...).distinct().count()             # "unsorted"
```

LTSeq (main at `291aa14`, DataFusion 55.0.0) lowers `derive` to one `DataFrame::select` holding a left-deep chain of `+`, and `distinct()` to `DataFrame::distinct`. Its optimized plans at depth 4:

```text
Aggregate: groupBy=[[?table?.a, ?table?.b, s]], aggr=[[]]
  Projection: ?table?.a, ?table?.b, ?table?.a + Int64(1) + Int64(1) + Int64(1) AS s
    Sort: ?table?.a ASC NULLS LAST, ?table?.__ltseq_position_0 ASC NULLS LAST      (sorted only)
      TableScan: ?table? projection=[a, b, __ltseq_position_0]
```

Physically, LTSeq's sorted input is a `SortExec` and `SortPreservingMergeExec` under an LTSeq-specific `StableOrderExec`, round-robin repartitioned to 8 partitions on that machine.

This case keeps the aggregate over every column, the single projection with the same left-deep expression, the nullable `Int64` columns, and an input whose ordering on `a` the planner knows. It replaces the LTSeq sort and its hidden position column with a `MemTable` declared sorted on `a ASC NULLS LAST`, and sets the partition count explicitly. With that change the sorted case still reproduces; the explicit `Sort` was not needed. The optimized plan here at depth 4 (`--explain --depth 4`):

```text
Aggregate: groupBy=[[t.a, t.b, s1]], aggr=[[]]
  Projection: t.a, t.b, t.a + Int64(1) + Int64(1) + Int64(1) AS s1
    TableScan: t projection=[a, b]

AggregateExec: mode=FinalPartitioned, gby=[a@0 as a, b@1 as b, s1@2 as s1], aggr=[], group_clustering_mode=Partial([0, 2])
  RepartitionExec: partitioning=Hash([a@0, b@1, s1@2], 2), input_partitions=2, preserve_order=true, sort_exprs=a@0 ASC NULLS LAST
    AggregateExec: mode=Partial, gby=[a@0 as a, b@1 as b, s1@2 as s1], aggr=[], group_clustering_mode=Partial([0, 2])
      ProjectionExec: expr=[a@0 as a, b@1 as b, a@0 + 1 + 1 + 1 as s1]
        DataSourceExec: partitions=2, partition_sizes=[1, 1], output_ordering=a@0 ASC NULLS LAST
```

The CLI prints the actual shape for every run, so the requested depth can be checked against what survived optimization: node names, the deepest expression in the logical plan and in any `ProjectionExec`, the ordering the projection's input provides, and the leaf partition count.

Each `--projections` layer is a derived table that computes `s{k}` from `s{k-1}`. Without `--retain`, the logical optimizer inlines the layers into one projection whose expression is about `projections × depth` levels deep; with `--retain`, every intermediate column is read twice and the layers stay separate. `--projections 4 --depth 25` is therefore one projection 97 levels deep, not four of 25.

## Measurement

The timed path is `plan()` in [`src/lib.rs`](src/lib.rs). For each run it builds a new session and registers the table (`setup`), then times, on one current-thread Tokio runtime:

| Stage | Call |
|---|---|
| `parse` | `SessionState::sql_to_statement` |
| `sql_to_logical` | `SessionState::statement_to_plan` |
| `logical_optimize` | `SessionState::optimize` (analyzer and optimizer rules) |
| `physical_plan` | `SessionState::query_planner().create_physical_plan` on the optimized plan: initial plan, physical optimizer rules, planner checks |

`DataFrame::create_physical_plan` goes through `SessionState::create_physical_plan`, which is `optimize` followed by the query planner. The two halves are timed as separate stages, so logical optimization runs once per run and is not billed to `physical_plan`; a smoke test counts the passes. Each default physical optimizer rule is wrapped, in its default order, in a shim that times the call and keeps the rule's name and schema check, so `physical_plan` is also broken down by rule. The text output derives "outside rules" as `physical_plan` minus the rule times; that remainder is the initial plan and the planner's invariant and sanity checks, which the public API does not let us time apart on 56. `planning_total` is the sum of the four stages. Nothing is executed on the timed path; one smoke test executes the query separately to check that the SQL means what this README says.

Results from different machines, or from debug builds, are not comparable to the numbers below.

## Verified Results

`planning_total` (parse through physical planning, setup excluded) in ms: median [min–max] of 3 release-build runs after 1 warmup. Raw samples, every stage and every physical rule: [`results/verification.csv`](results/verification.csv). Machine, revisions and protocol: [`results/environment.md`](results/environment.md). Produced by `scripts/verify-versions.sh` at reproducer commit `beac66b`.

Reported workload (`--mode distinct`, 2 partitions):

| Depth | Input | 55.0.0 | 56.0.0 | 56 / 55 |
|---|---|---|---|---|
| 25 | sorted | 1.9 [1.9–1.9] | 16.3 [16.3–16.6] | 9× |
| 50 | sorted | 4.7 [4.7–4.9] | 166.2 [158.9–166.3] | 35× |
| 100 | sorted | 15.0 [14.9–15.2] | 1875.8 [1864.4–1879.8] | 125× |
| 200 | sorted | 52.6 [52.3–52.9] | 24023.9 [23989.8–24084.5] | 457× |
| 500 | sorted | 309.9 (1 run) | timeout (> 120 s, 1 run) | — |
| 25 | unsorted | 1.8 [1.7–1.8] | 4.4 [4.4–4.4] | 2× |
| 50 | unsorted | 4.7 [4.7–4.7] | 31.9 [31.7–31.9] | 7× |
| 100 | unsorted | 14.8 [14.7–15.0] | 341.3 [337.6–379.3] | 23× |
| 200 | unsorted | 53.0 [51.5–53.2] | 4190.4 [4188.1–4218.8] | 79× |

Controls at depth 100, sorted input unless stated:

| Workload | 55.0.0 | 56.0.0 |
|---|---|---|
| `--mode group-by` (`GROUP BY a, b, s1`) | 13.7 | 1853.4 |
| `--mode order-by` (`ORDER BY s1`, `a` and `b` projected) | 14.6 | 1054.1 |
| `--mode project` (no sort or grouping) | 14.4 | 11.9 |
| `--key-only` (`DISTINCT s1` alone) | 14.9 | 10.5 |
| `--partitions 1` | 14.9 | 1455.2 |
| `--partitions 8` | 15.0 | 1853.6 |
| `--depth 25 --projections 4 --retain` (four separate 25-level projections) | 6.0 | 126.8 |

What this shows:

- **The reported regression reproduces.** At depth 200 the sorted `distinct` plans in 53 ms on 55.0.0 and 24.0 s on 56.0.0, and depth 500 does not finish within 120 s on 56.0.0 while 55.0.0 takes 0.31 s. LTSeq's end-to-end ratio (0.44 s vs 88 s, about 200×) is of the same order. LTSeq's times include execution, an explicit sort and 8 partitions on another machine, so neither the absolute times nor the ratio are expected to match.
- **Growth.** On 56.0.0 each doubling of depth multiplies the sorted time by 10.2, 11.3 and 12.8, an empirical exponent of about 3.3–3.7 between depths 25 and 200. On 55.0.0 the factors are 2.5, 3.2 and 3.5, so 55 also grows faster than linearly, but much more slowly. These are fits to four points, not a complexity bound.
- **Where the time goes.** On 56.0.0 nearly all of it is physical planning. At depth 100 sorted (medians), `EnsureRequirements` takes about 1.04 s, `OptimizeAggregateOrder` 0.20 s, and the work outside rules (initial plan and checks) 0.63 s. On 55.0.0 the whole physical stage takes 1.0 ms, and logical optimization (11.2 ms) dominates.
- **What triggers it.** Grouping or ordering on the computed column while its source column `a` is also in the output: `--key-only` and `--mode project` plan as fast on 56.0.0 as on 55.0.0, or faster. A declared ordering on `a` makes it about 5× worse, but the unsorted input is also affected. The partition count changes the time only moderately. The cost follows the depth of a single expression, not the depth of the plan: four separately retained 25-level projections cost far less than one 100-level expression.

## Investigation Status

- Reproduced on 56.0.0 and absent on 55.0.0 with a standalone case. The cross-version baseline (#4) and the bisect and profile (#5) are next.
- The rule timings point at `EnsureRequirements`, `OptimizeAggregateOrder` and the planner work outside rules; that is where the time is spent, not yet why. No root cause is claimed.
- Fix validation: none yet.

## Known Limitations

- One machine, one run of the matrix. The numbers show the shape of the growth and the size of the gap, not a portable baseline; #4 owns the cross-version baseline, including `branch-56` and `main`.
- The input ordering comes from a declared `MemTable` sort order instead of LTSeq's `Sort` and `StableOrderExec`, and the partition count is set explicitly (LTSeq's run had 8). Both still reproduce, but plans that only those operators produce are not covered.
- Only `+ 1` chains on `Int64` are tested. Other monotonic or non-monotonic functions, casts, `DESC` and `NULLS FIRST` orderings, and volatile expressions are not varied.
- The workload is SQL. LTSeq builds the same logical plan through the `DataFrame` API, so `parse` and `sql_to_logical` have no LTSeq counterpart; the slow stage, `physical_plan`, takes the same logical plan either way.
- Both versions share one `Cargo.lock`, so a dependency that both DataFusion versions accept resolves to the same version for both. A standalone 55.0.0 project resolved at another time could pick different patch versions.
- A timed-out run is abandoned, not interrupted: the CLI exits the process.
