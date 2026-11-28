# Environment of `results/verification.csv`

| Item | Value |
|---|---|
| Reproducer commit | `beac66b8acac78a1f224514c8193bc79333994a6` (clean tree for all built sources) |
| Command | `scripts/verify-versions.sh` from `repros/deep-expression-planning` |
| DataFusion 55 | crates.io `55.0.0`, all 31 `datafusion*` crates at 55.0.0 (tag commit `d5552342012888b7d1a3ab88d92e3d292fc0cde0`) |
| DataFusion 56 | crates.io `56.0.0`, all 31 `datafusion*` crates at 56.0.0 (tag commit `7e7ae72a820e2bf87da1205b96639fba334ed2f7`) |
| Build | `cargo build --release --locked`, default release profile plus `debug = "line-tables-only"`, no extra `RUSTFLAGS`; features `df55` or `df56` |
| Toolchain | rustc 1.97.1 (8bab26f4f 2026-07-14), cargo 1.97.1 (c980f4866 2026-06-30) |
| OS | Debian GNU/Linux 13 (trixie), Linux 7.0.14-30-pve x86_64, in a Proxmox guest |
| CPU | Intel Core i7-8700K @ 3.70 GHz; 12 host threads, 8 available to the guest (`nproc`) |
| Memory | 23 GiB |
| Session | defaults, except `target_partitions` = `--partitions` (2 unless stated) |
| Protocol | per workload: 1 warmup and 3 measured runs (depth 500: 1 run, no warmup); new session per run; per-invocation timeout as in the script |

Other processes were not controlled. Treat the values as one machine's evidence of the growth and the version gap, not as a portable baseline.
