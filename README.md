# DataFusion Reproducers

Standalone reproducible cases, correctness controls, cross-version baselines, and investigation tools for Apache DataFusion defects and performance regressions.

> **Independent repository notice:** This repository is maintained by Lychee Technology. It is not an official Apache Software Foundation (ASF) project and is independent of downstream applications.

## Case Index

No reproduction cases are committed yet. Each new case added under `repros/<case-slug>/` must add a row here.

| Case | Symptom | Affected Versions | Status | Upstream |
|---|---|---|---|---|
| *(none yet)* | — | — | — | — |

## Repository Structure

```text
.
├── CONTRIBUTING.md                 # Case lifecycle, verification, and upstream submission conventions
├── LICENSE                         # Apache License 2.0
├── README.md                       # Repository overview and case index
├── docs/
│   ├── agent-guides/               # Detailed contributor and investigation procedures
│   └── templates/
│       └── case-README.md          # Standard per-case README template
├── repros/                         # Independent per-case Cargo projects (created when cases are added)
│   └── <case-slug>/
└── scripts/
    └── check-cases.sh              # Local and CI repository/case convention checks
```

There is intentionally no root `Cargo.toml` or shared Cargo workspace. Each directory under `repros/<case-slug>/` owns its own `Cargo.toml`, `Cargo.lock`, toolchain configuration, and DataFusion dependency pins so adding or updating one case never alters another case's dependencies.

## Quick Start

### Run an existing case

```bash
cd repros/<case-slug>
cargo run --release --locked
```

See each case's `README.md` for required CLI flags, dependency revisions, and expected vs. actual output.

### Run repository and case checks

```bash
./scripts/check-cases.sh
```

Useful options:

- `./scripts/check-cases.sh --release` — also verify `cargo build --release --locked` for each case.
- `./scripts/check-cases.sh --metadata-only` — validate repository invariants and case manifests without running Cargo.
- `./scripts/check-cases.sh repros/<case-slug>` — check a single case directory.

### Add a new case

1. Read [CONTRIBUTING.md](CONTRIBUTING.md) and copy [docs/templates/case-README.md](docs/templates/case-README.md) into `repros/<case-slug>/README.md`.
2. Create an independent Cargo crate under `repros/<case-slug>/` with `publish = false`, `license = "Apache-2.0"`, exact DataFusion pins, and a committed `Cargo.lock`.
3. Add a row to the [Case Index](#case-index) above and run `./scripts/check-cases.sh`.

## License & Attribution

This repository is licensed under the Apache License, Version 2.0 ([LICENSE](LICENSE)).

- Original source files use `// SPDX-License-Identifier: Apache-2.0` (or `# SPDX-License-Identifier: Apache-2.0`).
- Any code copied or adapted from Apache DataFusion or other third-party sources must retain original copyright, license, and applicable `NOTICE` attributions.
- No CLA or DCO sign-off is required.
