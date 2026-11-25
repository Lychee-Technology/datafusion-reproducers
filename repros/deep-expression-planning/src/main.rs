// SPDX-License-Identifier: Apache-2.0

//! CLI: plan one workload repeatedly and report per-stage planning time.

use std::process::ExitCode;
use std::sync::mpsc;
use std::time::Duration;

use deep_expression_planning::{
    DATAFUSION_VERSION, Input, Mode, PlanShape, Stage, Workload, plan, render_plans,
};

const USAGE: &str = "\
Plan a deep computed-column query and time each planning stage (no execution).

Usage: deep-expression-planning [OPTIONS]

Workload:
  --depth N          levels of each computed expression, column included [25]
  --projections N    stacked projections, each adding --depth levels [1]
  --retain           keep every intermediate computed column in the output
  --key-only         output only the last computed column (control)
  --mode M           distinct | group-by | order-by | project [distinct]
  --input I          sorted | unsorted (declared ordering on `a`) [sorted]
  --partitions N     table partitions and target_partitions [2]

Measurement:
  --iterations N     measured planning runs [5]
  --warmup N         unmeasured runs before them [1]
  --timeout-secs N   stop with status `timeout` (exit 124) after N seconds [60]
  --format F         text | csv [text]
  --explain          print the SQL, plan shape and plans, then exit
  -h, --help         print this help
";

/// Planning recurses once per expression level; give it room for depth
/// 1000 and more without depending on the main thread's stack size.
const PLANNING_STACK: usize = 1 << 30;

struct Options {
    workload: Workload,
    iterations: usize,
    warmup: usize,
    timeout: Duration,
    csv: bool,
    explain: bool,
}

fn parse_args(mut args: impl Iterator<Item = String>) -> Result<Option<Options>, String> {
    let mut o = Options {
        workload: Workload::default(),
        iterations: 5,
        warmup: 1,
        timeout: Duration::from_secs(60),
        csv: false,
        explain: false,
    };
    while let Some(arg) = args.next() {
        let mut value = || args.next().ok_or_else(|| format!("{arg} needs a value"));
        let number = |v: String| {
            v.parse::<usize>()
                .map_err(|_| format!("{arg}: expected a non-negative integer, got {v:?}"))
        };
        match arg.as_str() {
            "-h" | "--help" => return Ok(None),
            "--depth" => o.workload.depth = number(value()?)?,
            "--projections" => o.workload.projections = number(value()?)?,
            "--retain" => o.workload.retain = true,
            "--key-only" => o.workload.key_only = true,
            "--partitions" => o.workload.partitions = number(value()?)?,
            "--mode" => {
                let v = value()?;
                o.workload.mode = Mode::parse(&v).ok_or_else(|| format!("unknown --mode {v:?}"))?;
            }
            "--input" => {
                let v = value()?;
                o.workload.input =
                    Input::parse(&v).ok_or_else(|| format!("unknown --input {v:?}"))?;
            }
            "--iterations" => o.iterations = number(value()?)?,
            "--warmup" => o.warmup = number(value()?)?,
            "--timeout-secs" => o.timeout = Duration::from_secs(number(value()?)? as u64),
            "--format" => {
                o.csv = match value()?.as_str() {
                    "csv" => true,
                    "text" => false,
                    v => return Err(format!("unknown --format {v:?}")),
                }
            }
            "--explain" => o.explain = true,
            _ => return Err(format!("unknown argument {arg:?}")),
        }
    }
    o.workload.validate()?;
    if o.iterations == 0 {
        return Err("--iterations must be at least 1".into());
    }
    Ok(Some(o))
}

/// What the planning thread reports. Plans stay on that thread: dropping a
/// deep plan recurses as deeply as building it.
enum Msg {
    Shape(PlanShape, String),
    Sample {
        stages: Vec<(Stage, Duration)>,
        rules: Vec<(String, Duration)>,
        total: Duration,
    },
    Error(String),
}

fn run_planning(o: &Options, tx: mpsc::Sender<Msg>) {
    let runtime = match tokio::runtime::Builder::new_current_thread().build() {
        Ok(rt) => rt,
        Err(e) => {
            let _ = tx.send(Msg::Error(format!("cannot start runtime: {e}")));
            return;
        }
    };
    for i in 0..o.warmup + o.iterations {
        let planned = match runtime.block_on(plan(&o.workload)) {
            Ok(p) => p,
            Err(e) => {
                let _ = tx.send(Msg::Error(e.to_string()));
                return;
            }
        };
        if i == 0 {
            let shape = PlanShape::of(&planned.logical, &planned.physical);
            let _ = tx.send(Msg::Shape(shape, render_plans(&planned)));
            if o.explain {
                return;
            }
        }
        if i >= o.warmup {
            let total = planned.planning_total();
            let _ = tx.send(Msg::Sample {
                stages: planned.stages.clone(),
                rules: planned.rules.clone(),
                total,
            });
        }
    }
}

fn ms(d: Duration) -> f64 {
    d.as_secs_f64() * 1e3
}

fn median_min_max(mut v: Vec<Duration>) -> (Duration, Duration, Duration) {
    v.sort();
    let n = v.len();
    let median = if n % 2 == 1 {
        v[n / 2]
    } else {
        (v[n / 2 - 1] + v[n / 2]) / 2
    };
    (median, v[0], v[n - 1])
}

fn describe(w: &Workload) -> String {
    format!(
        "depth={} projections={} retain={} key_only={} mode={} input={} partitions={}",
        w.depth,
        w.projections,
        w.retain,
        w.key_only,
        w.mode.name(),
        w.input.name(),
        w.partitions
    )
}

fn print_shape(shape: &PlanShape) {
    let ordering = shape.projection_input_ordering.as_deref().unwrap_or("none");
    let rows = [
        ("logical nodes", shape.logical_nodes.join(" > ")),
        (
            "logical expr depth",
            shape.logical_max_expr_depth.to_string(),
        ),
        ("physical nodes", shape.physical_nodes.join(" > ")),
        (
            "projection expr depth",
            shape.projection_max_expr_depth.to_string(),
        ),
        ("projection input order", ordering.to_string()),
        ("leaf partitions", format!("{:?}", shape.leaf_partitions)),
    ];
    for (label, value) in rows {
        println!("{:<24}{value}", format!("{label}:"));
    }
}

struct Csv<'a> {
    o: &'a Options,
}

impl Csv<'_> {
    fn header() {
        println!(
            "datafusion_version,mode,input,expression_depth,projection_depth,retain,key_only,\
             partitions,iteration,measurement_stage,elapsed_ms,timeout_ms,status"
        );
    }

    fn row(&self, iteration: &str, stage: &str, elapsed: Option<Duration>, status: &str) {
        let w = &self.o.workload;
        println!(
            "{DATAFUSION_VERSION},{},{},{},{},{},{},{},{iteration},{stage},{},{},{status}",
            w.mode.name(),
            w.input.name(),
            w.depth,
            w.projections,
            w.retain,
            w.key_only,
            w.partitions,
            elapsed.map(|d| format!("{:.3}", ms(d))).unwrap_or_default(),
            self.o.timeout.as_millis(),
        );
    }
}

fn main() -> ExitCode {
    let o = match parse_args(std::env::args().skip(1)) {
        Ok(Some(o)) => o,
        Ok(None) => {
            print!("{USAGE}");
            return ExitCode::SUCCESS;
        }
        Err(e) => {
            eprintln!("error: {e}\n\n{USAGE}");
            return ExitCode::from(2);
        }
    };

    if o.explain {
        println!("datafusion {DATAFUSION_VERSION}: {}", describe(&o.workload));
        println!("-- sql\n{}\n", o.workload.sql());
    } else if o.csv {
        Csv::header();
    } else {
        println!("datafusion {DATAFUSION_VERSION}: {}", describe(&o.workload));
        println!(
            "iterations={} warmup={} timeout={}s; planning only, nothing executed",
            o.iterations,
            o.warmup,
            o.timeout.as_secs()
        );
    }

    let (tx, rx) = mpsc::channel();
    let spawned = std::thread::Builder::new()
        .name("planning".into())
        .stack_size(PLANNING_STACK)
        .spawn({
            let o = Options {
                workload: o.workload.clone(),
                ..o
            };
            move || run_planning(&o, tx)
        });
    if let Err(e) = spawned {
        eprintln!("error: cannot start planning thread: {e}");
        return ExitCode::FAILURE;
    }

    let deadline = std::time::Instant::now() + o.timeout;
    let csv = Csv { o: &o };
    let mut totals = Vec::new();
    let mut stage_samples: Vec<Vec<Duration>> = vec![Vec::new(); Stage::ALL.len()];
    let mut rule_samples: Vec<(String, Vec<Duration>)> = Vec::new();
    let mut outside_rules = Vec::new();
    loop {
        let left = deadline.saturating_duration_since(std::time::Instant::now());
        match rx.recv_timeout(left) {
            Ok(Msg::Shape(shape, plans)) => {
                if o.explain {
                    print_shape(&shape);
                    println!();
                    print!("{plans}");
                    return ExitCode::SUCCESS;
                }
                if !o.csv {
                    print_shape(&shape);
                }
            }
            Ok(Msg::Sample {
                stages,
                rules,
                total,
            }) => {
                let iteration = totals.len().to_string();
                if o.csv {
                    for (stage, d) in &stages {
                        csv.row(&iteration, stage.name(), Some(*d), "ok");
                    }
                    for (rule, d) in &rules {
                        csv.row(&iteration, &format!("physical_rule:{rule}"), Some(*d), "ok");
                    }
                    csv.row(&iteration, "planning_total", Some(total), "ok");
                }
                for (i, (_, d)) in stages.iter().enumerate() {
                    stage_samples[i].push(*d);
                }
                let physical = stages
                    .iter()
                    .find(|(s, _)| *s == Stage::PhysicalPlan)
                    .map(|(_, d)| *d)
                    .unwrap_or_default();
                let in_rules: Duration = rules.iter().map(|(_, d)| *d).sum();
                outside_rules.push(physical.saturating_sub(in_rules));
                for (i, (rule, d)) in rules.into_iter().enumerate() {
                    match rule_samples.get_mut(i) {
                        Some((_, v)) => v.push(d),
                        None => rule_samples.push((rule, vec![d])),
                    }
                }
                totals.push(total);
            }
            Ok(Msg::Error(e)) => {
                if o.csv {
                    csv.row(&totals.len().to_string(), "planning_total", None, "error");
                }
                eprintln!("error: planning failed: {e}");
                return ExitCode::FAILURE;
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
            Err(mpsc::RecvTimeoutError::Timeout) => {
                if o.csv {
                    csv.row(&totals.len().to_string(), "planning_total", None, "timeout");
                }
                eprintln!(
                    "timeout: {} of {} measured runs finished within {}s",
                    totals.len(),
                    o.iterations,
                    o.timeout.as_secs()
                );
                // The planning thread cannot be interrupted; exiting ends it.
                std::process::exit(124);
            }
        }
    }

    if totals.len() < o.iterations {
        eprintln!("error: planning thread ended early");
        return ExitCode::FAILURE;
    }
    if !o.csv {
        println!(
            "\n{:<34} {:>12} {:>12} {:>12}",
            "stage", "median ms", "min ms", "max ms"
        );
        let line = |name: &str, v: &[Duration]| {
            let (med, min, max) = median_min_max(v.to_vec());
            println!(
                "{name:<34} {:>12.3} {:>12.3} {:>12.3}",
                ms(med),
                ms(min),
                ms(max)
            );
        };
        for (stage, v) in Stage::ALL.iter().zip(&stage_samples) {
            line(stage.name(), v);
        }
        line("  physical_plan outside rules (*)", &outside_rules);
        line("planning_total (excl. setup)", &totals);
        println!("(*) derived: physical_plan minus its rule timings (initial plan, checks)");
        let mut slowest: Vec<_> = rule_samples
            .iter()
            .map(|(rule, v)| (median_min_max(v.clone()).0, rule))
            .collect();
        slowest.sort_by_key(|(med, _)| std::cmp::Reverse(*med));
        println!("\nslowest physical optimizer rules (median ms):");
        for (med, rule) in slowest.iter().take(5) {
            println!("  {rule:<32} {:>12.3}", ms(*med));
        }
    }
    ExitCode::SUCCESS
}
