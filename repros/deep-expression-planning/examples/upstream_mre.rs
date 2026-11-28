// SPDX-License-Identifier: Apache-2.0

//! Self-contained example for an upstream report. Outside this repository,
//! delete the `use deep_expression_planning::datafusion;` line and depend on
//! `datafusion` and `tokio` (feature `rt`) directly.
//!
//! cargo run --release --locked --example upstream_mre -- 100

use deep_expression_planning::datafusion;

use std::sync::Arc;
use std::time::Instant;

use datafusion::arrow::array::Int64Array;
use datafusion::arrow::datatypes::{DataType, Field, Schema};
use datafusion::arrow::record_batch::RecordBatch;
use datafusion::datasource::MemTable;
use datafusion::error::Result;
use datafusion::prelude::{SessionConfig, SessionContext, col};

async fn run(depth: usize) -> Result<()> {
    let schema = Arc::new(Schema::new(vec![
        Field::new("a", DataType::Int64, true),
        Field::new("b", DataType::Int64, true),
    ]));
    let batch = |a: [i64; 2], b: [i64; 2]| {
        RecordBatch::try_new(
            Arc::clone(&schema),
            vec![
                Arc::new(Int64Array::from(a.to_vec())),
                Arc::new(Int64Array::from(b.to_vec())),
            ],
        )
    };
    // Two partitions, each sorted on `a`, and declared as such.
    let table = MemTable::try_new(
        Arc::clone(&schema),
        vec![vec![batch([1, 2], [0, 0])?], vec![batch([3, 4], [1, 1])?]],
    )?
    .with_sort_order(vec![vec![col("a").sort(true, false)]]);

    let ctx = SessionContext::new_with_config(SessionConfig::new().with_target_partitions(2));
    ctx.register_table("t", Arc::new(table))?;

    // a + 1 + 1 + ... : `depth` levels, counting `a`.
    let s = std::iter::once("a")
        .chain(std::iter::repeat_n("1", depth - 1))
        .collect::<Vec<_>>()
        .join(" + ");
    let sql = format!("SELECT DISTINCT a, b, s FROM (SELECT a, b, {s} AS s FROM t)");

    let df = ctx.sql(&sql).await?; // parse + logical plan
    let start = Instant::now();
    let _plan = df.create_physical_plan().await?; // optimize + physical plan; nothing runs
    println!(
        "datafusion {}: depth {depth}: create_physical_plan took {:?}",
        datafusion::DATAFUSION_VERSION,
        start.elapsed()
    );
    Ok(())
}

fn main() -> Result<()> {
    let depth: usize = std::env::args()
        .nth(1)
        .map(|d| {
            d.parse::<std::num::NonZeroUsize>()
                .expect("depth must be a positive integer")
                .get()
        })
        .unwrap_or(100);
    // Planning recurses once per expression level.
    std::thread::Builder::new()
        .stack_size(256 << 20)
        .spawn(move || {
            tokio::runtime::Builder::new_current_thread()
                .build()?
                .block_on(run(depth))
        })?
        .join()
        .expect("planning thread panicked")
}
