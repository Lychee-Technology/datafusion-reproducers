// SPDX-License-Identifier: Apache-2.0

//! Workload generation and staged planning for the deep computed-column case.
//!
//! The workload follows the downstream LTSeq operation that exposed the
//! slowdown: `t.sort("a").derive(s = a + 1 + ... + 1).distinct()`. LTSeq lowers
//! it to one projection holding a left-deep chain of additions, under an
//! aggregate that groups by every column. This crate rebuilds that plan from
//! inline SQL over a tiny `MemTable` and times each planning stage. No query
//! is executed on the timed path.

#[cfg(all(feature = "df55", feature = "df56"))]
compile_error!("enable exactly one of the `df55` and `df56` features");
#[cfg(not(any(feature = "df55", feature = "df56")))]
compile_error!("enable one of the `df55` and `df56` features");

#[cfg(all(feature = "df55", not(feature = "df56")))]
pub use datafusion55 as datafusion;
#[cfg(feature = "df56")]
pub use datafusion56 as datafusion;

use std::fmt::Write as _;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use datafusion::arrow::array::Int64Array;
use datafusion::arrow::datatypes::{DataType, Field, Schema};
use datafusion::arrow::record_batch::RecordBatch;
use datafusion::common::tree_node::{TreeNode, TreeNodeRecursion};
use datafusion::config::ConfigOptions;
use datafusion::datasource::MemTable;
use datafusion::error::Result;
use datafusion::execution::SessionStateBuilder;
use datafusion::logical_expr::{Expr, LogicalPlan};
use datafusion::physical_expr::PhysicalExpr;
use datafusion::physical_optimizer::{PhysicalOptimizerContext, PhysicalOptimizerRule};
use datafusion::physical_plan::projection::ProjectionExec;
use datafusion::physical_plan::{ExecutionPlan, ExecutionPlanProperties, displayable};
use datafusion::prelude::{SessionConfig, SessionContext, col};

/// The DataFusion version this build is linked against.
pub const DATAFUSION_VERSION: &str = datafusion::DATAFUSION_VERSION;

/// The operator applied on top of the computed column(s).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    /// `SELECT DISTINCT` over the output columns: the original LTSeq
    /// `distinct()`, which groups by every column.
    Distinct,
    /// `GROUP BY` the output columns, with `count(*)`.
    GroupBy,
    /// `ORDER BY` the last computed column.
    OrderBy,
    /// Plain projection: control with no sort or grouping.
    Project,
}

impl Mode {
    pub const ALL: [Mode; 4] = [Mode::Distinct, Mode::GroupBy, Mode::OrderBy, Mode::Project];

    pub fn name(self) -> &'static str {
        match self {
            Mode::Distinct => "distinct",
            Mode::GroupBy => "group-by",
            Mode::OrderBy => "order-by",
            Mode::Project => "project",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|m| m.name() == s)
    }
}

/// Whether the table declares an ordering on `a`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Input {
    /// Every partition is sorted on `a ASC NULLS LAST` and the table says so.
    Sorted,
    /// The same rows, with no declared ordering.
    Unsorted,
}

impl Input {
    pub fn name(self) -> &'static str {
        match self {
            Input::Sorted => "sorted",
            Input::Unsorted => "unsorted",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        [Input::Sorted, Input::Unsorted]
            .into_iter()
            .find(|i| i.name() == s)
    }
}

/// One point in the workload space.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Workload {
    /// Levels of each computed expression, counting the column as one level:
    /// depth 3 is `a + 1 + 1`. This is LTSeq's count.
    pub depth: usize,
    /// Number of stacked projections; layer `k` computes `s{k}` from
    /// `s{k-1}` (layer 1 from `a`) with `depth` levels.
    pub projections: usize,
    /// Keep every intermediate `s{k}` in the output, not only the last one.
    pub retain: bool,
    /// Output only the last computed column, without its source column `a`
    /// and `b`. A control: the slowdown needs `a` next to the computed key.
    pub key_only: bool,
    pub mode: Mode,
    pub input: Input,
    /// Table partitions, also used as `target_partitions`.
    pub partitions: usize,
}

impl Default for Workload {
    fn default() -> Self {
        Self {
            depth: 25,
            projections: 1,
            retain: false,
            key_only: false,
            mode: Mode::Distinct,
            input: Input::Sorted,
            partitions: 2,
        }
    }
}

/// `base + 1 + 1 + ...`, `depth` levels deep (left-deep, as LTSeq builds it).
pub fn chain(base: &str, depth: usize) -> String {
    assert!(depth >= 1, "depth counts the column, so it is at least 1");
    let mut sql = String::with_capacity(base.len() + 4 * depth);
    sql.push_str(base);
    for _ in 1..depth {
        sql.push_str(" + 1");
    }
    sql
}

impl Workload {
    /// Validate the parameters; returns a message naming the bad one.
    pub fn validate(&self) -> std::result::Result<(), String> {
        if self.depth == 0 {
            return Err("--depth must be at least 1".into());
        }
        if self.projections == 0 {
            return Err("--projections must be at least 1".into());
        }
        if self.partitions == 0 {
            return Err("--partitions must be at least 1".into());
        }
        if self.key_only && self.retain {
            return Err("--key-only and --retain exclude each other".into());
        }
        Ok(())
    }

    /// Name of the last computed column.
    pub fn key(&self) -> String {
        format!("s{}", self.projections)
    }

    /// Columns of the final result, before the mode is applied.
    fn output_columns(&self) -> Vec<String> {
        if self.key_only {
            return vec![self.key()];
        }
        let mut cols = vec!["a".to_string(), "b".to_string()];
        let first = if self.retain { 1 } else { self.projections };
        cols.extend((first..=self.projections).map(|k| format!("s{k}")));
        cols
    }

    /// The SQL for this workload. Each projection is a derived table, so a
    /// projection depth of `p` gives `p` nested `SELECT`s.
    pub fn sql(&self) -> String {
        let mut from = "t".to_string();
        for k in 1..=self.projections {
            let mut cols = vec!["a".to_string(), "b".to_string()];
            // `s{k-1}` is only read by this layer, so it is forwarded only
            // when intermediate columns are retained.
            if self.retain {
                cols.extend((1..k).map(|j| format!("s{j}")));
            }
            let base = if k == 1 {
                "a".to_string()
            } else {
                format!("s{}", k - 1)
            };
            cols.push(format!("{} AS s{k}", chain(&base, self.depth)));
            from = format!("(SELECT {} FROM {from})", cols.join(", "));
        }
        let cols = self.output_columns().join(", ");
        let key = self.key();
        match self.mode {
            Mode::Distinct => format!("SELECT DISTINCT {cols} FROM {from}"),
            Mode::GroupBy => format!("SELECT {cols}, count(*) AS n FROM {from} GROUP BY {cols}"),
            Mode::OrderBy => format!("SELECT {cols} FROM {from} ORDER BY {key}"),
            Mode::Project => format!("SELECT {cols} FROM {from}"),
        }
    }
}

/// Rows of the generated table. Partition `p` holds `a = 2p+1, 2p+2` so
/// each partition is sorted on `a`; `b` repeats so `DISTINCT` has work.
pub fn table(workload: &Workload) -> Result<MemTable> {
    let schema = Arc::new(Schema::new(vec![
        Field::new("a", DataType::Int64, true),
        Field::new("b", DataType::Int64, true),
    ]));
    let partitions = (0..workload.partitions as i64)
        .map(|p| {
            let a = Int64Array::from(vec![2 * p + 1, 2 * p + 2]);
            let b = Int64Array::from(vec![p, p]);
            RecordBatch::try_new(Arc::clone(&schema), vec![Arc::new(a), Arc::new(b)])
                .map(|batch| vec![batch])
        })
        .collect::<std::result::Result<Vec<_>, _>>()?;
    let table = MemTable::try_new(schema, partitions)?;
    Ok(match workload.input {
        Input::Sorted => table.with_sort_order(vec![vec![col("a").sort(true, false)]]),
        Input::Unsorted => table,
    })
}

/// A session with default options apart from `target_partitions`, and the
/// table registered as `t`.
pub fn context(workload: &Workload) -> Result<SessionContext> {
    let config = SessionConfig::new().with_target_partitions(workload.partitions);
    let ctx = SessionContext::new_with_config(config);
    ctx.register_table("t", Arc::new(table(workload)?))?;
    Ok(ctx)
}

/// Planning stages, in the order they run.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Stage {
    /// Session creation and table registration.
    Setup,
    /// SQL text to AST.
    Parse,
    /// AST to unoptimized logical plan.
    SqlToLogical,
    /// Analyzer and logical optimizer rules (`SessionState::optimize`).
    LogicalOptimize,
    /// `SessionState::create_physical_plan`: the initial physical plan, every
    /// physical optimizer rule, and the planner's invariant and sanity checks.
    PhysicalPlan,
}

impl Stage {
    pub const ALL: [Stage; 5] = [
        Stage::Setup,
        Stage::Parse,
        Stage::SqlToLogical,
        Stage::LogicalOptimize,
        Stage::PhysicalPlan,
    ];

    pub fn name(self) -> &'static str {
        match self {
            Stage::Setup => "setup",
            Stage::Parse => "parse",
            Stage::SqlToLogical => "sql_to_logical",
            Stage::LogicalOptimize => "logical_optimize",
            Stage::PhysicalPlan => "physical_plan",
        }
    }
}

/// Timings of one planning run, and the plans it produced.
pub struct Planned {
    pub stages: Vec<(Stage, Duration)>,
    /// Time of each physical optimizer rule run, in order. These runs are
    /// part of [`Stage::PhysicalPlan`].
    pub rules: Vec<(String, Duration)>,
    pub logical: LogicalPlan,
    pub physical: Arc<dyn ExecutionPlan>,
}

impl Planned {
    /// Parse through physical planning; setup excluded.
    pub fn planning_total(&self) -> Duration {
        self.stages
            .iter()
            .filter(|(s, _)| *s != Stage::Setup)
            .map(|(_, d)| *d)
            .sum()
    }
}

type RuleLog = Arc<Mutex<Vec<(String, Duration)>>>;

/// A physical optimizer rule that records how long the rule it wraps takes.
/// It keeps the wrapped rule's name and schema check, so the planner treats
/// it as that rule.
#[derive(Debug)]
struct Timed {
    rule: Arc<dyn PhysicalOptimizerRule + Send + Sync>,
    log: RuleLog,
}

impl Timed {
    fn record<T>(&self, run: impl FnOnce() -> T) -> T {
        let start = Instant::now();
        let out = run();
        let elapsed = start.elapsed();
        if let Ok(mut log) = self.log.lock() {
            log.push((self.rule.name().to_string(), elapsed));
        }
        out
    }
}

impl PhysicalOptimizerRule for Timed {
    fn optimize(
        &self,
        plan: Arc<dyn ExecutionPlan>,
        config: &ConfigOptions,
    ) -> Result<Arc<dyn ExecutionPlan>> {
        self.record(|| self.rule.optimize(plan, config))
    }

    fn optimize_with_context(
        &self,
        plan: Arc<dyn ExecutionPlan>,
        context: &dyn PhysicalOptimizerContext,
    ) -> Result<Arc<dyn ExecutionPlan>> {
        self.record(|| self.rule.optimize_with_context(plan, context))
    }

    fn name(&self) -> &str {
        self.rule.name()
    }

    fn schema_check(&self) -> bool {
        self.rule.schema_check()
    }
}

/// Plan `workload` once, timing each stage. Nothing is executed.
///
/// Physical planning is one call to `SessionState::create_physical_plan`,
/// as `DataFrame::create_physical_plan` makes it. The session's default
/// physical optimizer rules are each wrapped in [`Timed`], in their default
/// order, to attribute that stage's time to rules.
pub async fn plan(workload: &Workload) -> Result<Planned> {
    let mut stages = Vec::with_capacity(Stage::ALL.len());
    let sql = workload.sql();

    let start = Instant::now();
    let ctx = context(workload)?;
    let log = RuleLog::default();
    let timed_rules = ctx
        .state()
        .physical_optimizers()
        .iter()
        .map(|rule| {
            Arc::new(Timed {
                rule: Arc::clone(rule),
                log: Arc::clone(&log),
            }) as Arc<dyn PhysicalOptimizerRule + Send + Sync>
        })
        .collect();
    let state = SessionStateBuilder::new_from_existing(ctx.state())
        .with_physical_optimizer_rules(timed_rules)
        .build();
    stages.push((Stage::Setup, start.elapsed()));

    let start = Instant::now();
    let dialect = state.config().options().sql_parser.dialect;
    let statement = state.sql_to_statement(&sql, &dialect)?;
    stages.push((Stage::Parse, start.elapsed()));

    let start = Instant::now();
    let unoptimized = state.statement_to_plan(statement).await?;
    stages.push((Stage::SqlToLogical, start.elapsed()));

    let start = Instant::now();
    let logical = state.optimize(&unoptimized)?;
    stages.push((Stage::LogicalOptimize, start.elapsed()));

    let start = Instant::now();
    let physical = state.create_physical_plan(&logical).await?;
    stages.push((Stage::PhysicalPlan, start.elapsed()));

    let rules = log
        .lock()
        .map(|mut l| std::mem::take(&mut *l))
        .unwrap_or_default();
    Ok(Planned {
        stages,
        rules,
        logical,
        physical,
    })
}

/// Levels of a logical expression, aliases excluded: `a + 1` has 2.
pub fn expr_depth(expr: &Expr) -> usize {
    let expr = match expr {
        Expr::Alias(alias) => alias.expr.as_ref(),
        e => e,
    };
    let mut deepest = 0;
    // `apply_children` visits only the direct children.
    let _ = expr.apply_children(|child| {
        deepest = deepest.max(expr_depth(child));
        Ok(TreeNodeRecursion::Continue)
    });
    deepest + 1
}

/// Levels of a physical expression: `a@0 + 1` has 2.
pub fn physical_expr_depth(expr: &Arc<dyn PhysicalExpr>) -> usize {
    1 + expr
        .children()
        .into_iter()
        .map(physical_expr_depth)
        .max()
        .unwrap_or(0)
}

/// What the optimized plans actually look like, independent of what the
/// workload asked for.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PlanShape {
    /// Logical node names, pre-order.
    pub logical_nodes: Vec<String>,
    /// Deepest expression anywhere in the optimized logical plan.
    pub logical_max_expr_depth: usize,
    /// Physical operator names, pre-order.
    pub physical_nodes: Vec<String>,
    /// Deepest expression in any `ProjectionExec`.
    pub projection_max_expr_depth: usize,
    /// Output ordering of the input of the outermost `ProjectionExec`, if any.
    pub projection_input_ordering: Option<String>,
    /// Output partitions of the leaf operators.
    pub leaf_partitions: Vec<usize>,
}

impl PlanShape {
    pub fn of(logical: &LogicalPlan, physical: &Arc<dyn ExecutionPlan>) -> Self {
        let mut logical_nodes = Vec::new();
        let mut logical_max_expr_depth = 0;
        let _ = logical.apply(|node| {
            let name = node.display().to_string();
            let name = name
                .split(':')
                .next()
                .unwrap_or_default()
                .trim()
                .to_string();
            logical_nodes.push(name);
            for e in node.expressions() {
                logical_max_expr_depth = logical_max_expr_depth.max(expr_depth(&e));
            }
            Ok(TreeNodeRecursion::Continue)
        });

        let mut shape = PlanShape {
            logical_nodes,
            logical_max_expr_depth,
            physical_nodes: Vec::new(),
            projection_max_expr_depth: 0,
            projection_input_ordering: None,
            leaf_partitions: Vec::new(),
        };
        shape.visit_physical(physical);
        shape
    }

    fn visit_physical(&mut self, plan: &Arc<dyn ExecutionPlan>) {
        self.physical_nodes.push(plan.name().to_string());
        if let Some(projection) = plan.downcast_ref::<ProjectionExec>() {
            for e in projection.expr() {
                self.projection_max_expr_depth = self
                    .projection_max_expr_depth
                    .max(physical_expr_depth(&e.expr));
            }
            if self.projection_input_ordering.is_none() {
                self.projection_input_ordering = projection
                    .input()
                    .output_ordering()
                    .map(|ordering| ordering.to_string());
            }
        }
        let children = plan.children();
        if children.is_empty() {
            self.leaf_partitions
                .push(plan.output_partitioning().partition_count());
        }
        for child in children {
            self.visit_physical(child);
        }
    }
}

/// The optimized logical and physical plans as text.
pub fn render_plans(planned: &Planned) -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        "-- optimized logical plan\n{}",
        planned.logical.display_indent()
    );
    let _ = writeln!(
        out,
        "-- physical plan\n{}",
        displayable(planned.physical.as_ref()).indent(true)
    );
    out
}
