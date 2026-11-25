// SPDX-License-Identifier: Apache-2.0

//! Structural checks that the workload reaches DataFusion's planner in the
//! intended shape. No assertion depends on elapsed time.

use std::process::Command;

use deep_expression_planning::datafusion::arrow::array::{Array, Int64Array};
use deep_expression_planning::datafusion::arrow::compute::concat_batches;
use deep_expression_planning::{Input, Mode, PlanShape, Planned, Workload, context, plan};

// Shallow enough for a 2 MiB debug test thread.
const DEPTH: usize = 8;

fn block_on<F: std::future::Future>(f: F) -> F::Output {
    tokio::runtime::Builder::new_current_thread()
        .build()
        .expect("runtime")
        .block_on(f)
}

fn planned(w: &Workload) -> (Planned, PlanShape) {
    let planned = block_on(plan(w)).expect("planning succeeds");
    let shape = PlanShape::of(&planned.logical, &planned.physical);
    (planned, shape)
}

fn workload(mode: Mode, input: Input) -> Workload {
    Workload {
        depth: DEPTH,
        mode,
        input,
        ..Workload::default()
    }
}

#[test]
fn sql_is_the_ltseq_lowering_of_sort_derive_distinct() {
    let w = Workload {
        depth: 4,
        ..Workload::default()
    };
    assert_eq!(
        w.sql(),
        "SELECT DISTINCT a, b, s1 FROM (SELECT a, b, a + 1 + 1 + 1 AS s1 FROM t)"
    );
}

#[test]
fn requested_depth_survives_optimization_in_every_mode() {
    for mode in Mode::ALL {
        for input in [Input::Sorted, Input::Unsorted] {
            let (_, shape) = planned(&workload(mode, input));
            let ctx = format!("{mode:?}/{input:?}: {shape:?}");
            assert_eq!(shape.logical_max_expr_depth, DEPTH, "{ctx}");
            assert_eq!(shape.projection_max_expr_depth, DEPTH, "{ctx}");
            assert_eq!(shape.leaf_partitions, vec![2], "{ctx}");
        }
    }
}

#[test]
fn distinct_plans_as_an_aggregate_over_one_projection() {
    let (_, shape) = planned(&workload(Mode::Distinct, Input::Sorted));
    assert_eq!(
        shape.logical_nodes,
        ["Aggregate", "Projection", "TableScan"],
        "{shape:?}"
    );
    let aggregates = shape
        .physical_nodes
        .iter()
        .filter(|n| *n == "AggregateExec")
        .count();
    assert_eq!(aggregates, 2, "partial and final aggregate: {shape:?}");
}

#[test]
fn operators_match_the_mode() {
    let nodes = |mode| planned(&workload(mode, Input::Unsorted)).1.physical_nodes;
    assert!(nodes(Mode::GroupBy).contains(&"AggregateExec".to_string()));
    assert!(nodes(Mode::OrderBy).contains(&"SortExec".to_string()));
    let project = nodes(Mode::Project);
    assert!(
        !project
            .iter()
            .any(|n| n == "AggregateExec" || n == "SortExec"),
        "{project:?}"
    );
}

#[test]
fn only_sorted_input_gives_the_projection_an_ordering() {
    let ordering = |input| {
        planned(&workload(Mode::Distinct, input))
            .1
            .projection_input_ordering
    };
    assert_eq!(
        ordering(Input::Sorted).as_deref(),
        Some("a@0 ASC NULLS LAST")
    );
    assert_eq!(ordering(Input::Unsorted), None);
}

#[test]
fn partition_count_reaches_the_scan() {
    for partitions in [1, 3] {
        let w = Workload {
            partitions,
            ..workload(Mode::Distinct, Input::Sorted)
        };
        assert_eq!(planned(&w).1.leaf_partitions, vec![partitions]);
    }
}

#[test]
fn unretained_projections_merge_and_retained_ones_stay() {
    let projections = 3;
    let count = |retain| {
        let w = Workload {
            projections,
            retain,
            ..workload(Mode::Distinct, Input::Sorted)
        };
        let (_, shape) = planned(&w);
        let n = shape
            .logical_nodes
            .iter()
            .filter(|n| *n == "Projection")
            .count();
        (n, shape.logical_max_expr_depth)
    };
    // The optimizer inlines each layer into the next: one projection whose
    // expression has every layer's additions.
    assert_eq!(count(false), (1, projections * (DEPTH - 1) + 1));
    // A retained column is read twice, so the layers are not inlined.
    assert_eq!(count(true), (projections, DEPTH));
}

#[test]
fn key_only_drops_the_source_column() {
    let w = Workload {
        key_only: true,
        ..workload(Mode::Distinct, Input::Sorted)
    };
    assert!(
        w.sql().starts_with("SELECT DISTINCT s1 FROM"),
        "{}",
        w.sql()
    );
    let (_, shape) = planned(&w);
    assert_eq!(shape.projection_max_expr_depth, DEPTH);
}

#[test]
fn every_physical_rule_is_timed_in_order() {
    let w = workload(Mode::Distinct, Input::Sorted);
    let (planned, _) = planned(&w);
    let ctx = context(&w).expect("context");
    let expected: Vec<String> = ctx
        .state()
        .physical_optimizers()
        .iter()
        .map(|r| r.name().to_string())
        .collect();
    let timed: Vec<String> = planned.rules.iter().map(|(n, _)| n.clone()).collect();
    assert_eq!(timed, expected);
}

#[test]
fn query_returns_the_expected_rows_when_executed() {
    // Executed outside any timed path: checks that the SQL means what the
    // README says.
    let w = Workload {
        depth: 3,
        ..workload(Mode::Distinct, Input::Sorted)
    };
    let batches = block_on(async {
        let ctx = context(&w)?;
        let sql = format!("SELECT a, s1 FROM ({}) ORDER BY a", w.sql());
        ctx.sql(&sql).await?.collect().await
    })
    .expect("query runs");
    let batch = concat_batches(&batches[0].schema(), &batches).expect("concat");
    let column = |i: usize| {
        let c = batch.column(i);
        let c = c.as_any().downcast_ref::<Int64Array>().expect("Int64");
        c.values().to_vec()
    };
    assert_eq!(column(0), [1, 2, 3, 4]);
    assert_eq!(column(1), [3, 4, 5, 6]);
}

#[test]
fn cli_explains_and_reports_csv() {
    let bin = env!("CARGO_BIN_EXE_deep-expression-planning");
    let explain = Command::new(bin)
        .args(["--explain", "--depth", "3"])
        .output()
        .expect("run CLI");
    assert!(explain.status.success(), "{explain:?}");
    let text = String::from_utf8_lossy(&explain.stdout);
    assert!(text.contains("SELECT DISTINCT a, b, s1 FROM (SELECT a, b, a + 1 + 1 AS s1 FROM t)"));
    assert!(text.contains("projection expr depth:  3"), "{text}");

    let csv = Command::new(bin)
        .args(["--depth", "3", "--iterations", "2", "--warmup", "0"])
        .args(["--format", "csv"])
        .output()
        .expect("run CLI");
    assert!(csv.status.success(), "{csv:?}");
    let text = String::from_utf8_lossy(&csv.stdout);
    let totals: Vec<_> = text
        .lines()
        .filter(|l| l.contains(",planning_total,"))
        .collect();
    assert_eq!(totals.len(), 2, "{text}");
    assert!(totals.iter().all(|l| l.ends_with(",ok")), "{text}");

    let bad = Command::new(bin)
        .args(["--mode", "nope"])
        .output()
        .expect("run CLI");
    assert_eq!(bad.status.code(), Some(2));
}
