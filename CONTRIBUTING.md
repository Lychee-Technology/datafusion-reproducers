# Contributing

This repository collects standalone, independently verifiable reproducers and investigation evidence for Apache DataFusion.

## Core Principles

1. **Correctness first** — Never weaken query semantics or optimizer invariants for speed.
2. **Reproducibility first** — Every reported result must run cleanly from a fresh checkout with pinned dependencies.
3. **Evidence over assumptions** — Distinguish raw observations, verified facts, hypotheses, and confirmed causes.
4. **Minimalism** — Use the smallest input and plan structure that faithfully triggers the defect.
5. **Upstream first** — Keep DataFusion fixes in a separate upstream checkout or fork, not as a permanent implementation here.

Never commit proprietary downstream code, private datasets, customer data, credentials, or access tokens.

## Independent Case Structure

Place each reproduction case in its own directory under `repros/<case-slug>/`, named in kebab-case after the observed symptom (for example, `deep-expression-planning` or `incorrect-null-ordering`):

```text
repros/<case-slug>/
├── README.md              # Required (start from docs/templates/case-README.md)
├── Cargo.toml             # Required (standalone package, publish = false, license = "Apache-2.0")
├── Cargo.lock             # Required (committed for reproducible dependency resolution)
├── rust-toolchain.toml    # Recommended (or document the exact toolchain in README.md)
├── src/                   # Minimal reproducer source
├── tests/                 # Optional deterministic smoke/correctness tests
├── sql/                   # Optional standalone SQL inputs
├── scripts/               # Optional case-specific helper scripts
├── results/               # Optional sanitized measurement logs/tables
└── profiles/              # Optional compact, sanitized profiles
```

Create optional directories only when needed.

### Isolation and Dependency Rules

- **No root workspace:** Do not add a root `Cargo.toml` or share a single DataFusion version across cases. Adding or updating one case must never modify another case's `Cargo.lock`.
- **No crates.io publication:** Every `Cargo.toml` under a case directory (including nested version-comparison manifests, explicit or implicit workspace members, and local path-dependency helper crates) must resolve to:
  ```toml
  [package]
  publish = false
  license = "Apache-2.0"
  ```
  Every standalone root manifest or case-internal workspace root must commit its own `Cargo.lock` (workspace members and local path-dependency helper crates resolve through their owning root's `Cargo.lock`).
- **Exact DataFusion pins:** Pin published releases with `=x.y.z` (for example `datafusion = "=56.0.0"`) and Git revisions with a full commit SHA (`rev = "<40-char-sha>"`).
- **Standalone inputs:** Use generated data, `MemTable`, `EmptyTable`, inline SQL, or direct logical/physical plan construction. Do not depend on downstream applications or external services.
- **Safe defaults:** Default CLI flags and `cargo test` cases must run quickly and safely. Require explicit flags for heavy or extended workloads, and never add brittle wall-clock timing assertions (`assert!(elapsed < ...)`) to routine tests or CI.

## Case Lifecycle

Track investigation progress explicitly without collapsing distinct stages:

1. **Reproduced** — Minimal standalone reproducer confirms the symptom on pinned DataFusion version(s).
2. **Cross-version baseline** — Affected and unaffected versions/SHAs are measured with raw samples and environment metadata.
3. **Root cause / bisect** — First bad commit or profiled hotspot is identified (or inconclusive findings are recorded).
4. **Upstream report / fix prepared** — Issue text, benchmark patch, or fix PR is prepared in an external DataFusion checkout.
5. **Upstream submitted** — Issue or PR is opened upstream (requires explicit maintainer authorization).
6. **Upstream merged / released** — Exact merge SHA, branch backport status, and release tag are verified.
7. **Downstream validated** — Original downstream workload is re-verified against the fixed release.

Preserve historical raw evidence (`results/`). Never overwrite baseline measurements to reflect later improvements.

## Verification & Review

Before opening a pull request, run:

```bash
./scripts/check-cases.sh
```

To also verify release compilation for cases:

```bash
./scripts/check-cases.sh --release
```

CI runs `./scripts/check-cases.sh` automatically on pushes to `main` and pull requests. Local runs require `rustfmt` and `clippy` to be installed for the active toolchain (when missing locally, the script prints the `rustup component add` command and fails rather than modifying your toolchain; in CI with `CI=true`, missing components are installed automatically). It checks:

- Repository invariants (no root `Cargo.toml`, valid Apache-2.0 `LICENSE`, `.gitignore` excludes `target/` while tracking `Cargo.lock`).
- Per-case metadata (`README.md`, every `Cargo.toml` under the case excluding `target/` resolving `publish = false` and `license = "Apache-2.0"`, and a committed `Cargo.lock` for each standalone root manifest or case-internal workspace root, not explicit/implicit workspace members or path-dependency helper crates).
- Per-case Rust checks when cases exist (`cargo fmt --check`, `cargo clippy --locked --all-targets -- -D warnings`, `cargo test --locked` for each standalone root manifest, and `--all` / `--workspace` for case-internal workspaces).

Before submitting a PR:

- Confirm the case reproduces cleanly from a fresh checkout using its documented one-command instructions.
- Verify triggering conditions structurally or functionally (for example, inspect optimized logical/physical plan shapes and correctness controls) rather than relying only on successful exit.
- Sanitize any logs, environment notes, or profiles so no private paths or secrets are exposed.
- Update the Case Index table in the root [README.md](README.md) when adding or updating a case.
- Follow [docs/agent-guides/non-code-rules.md](docs/agent-guides/non-code-rules.md) for issue and PR descriptions.

## Upstream Submission Conventions

- Keep external reproducers in this repository separate from permanent upstream tests or benchmarks in `apache/datafusion`.
- Check existing `apache/datafusion` issues and PRs for duplicates before preparing an upstream report.
- Include a stable commit permalink to the reproducer, exact DataFusion versions/SHAs, minimal copy-pasteable reproduction code, reproduction commands, environment/configuration details, and verified expected vs. actual results.
- Do not open upstream issues, post upstream comments, open upstream PRs, or request backports without explicit maintainer authorization.

## Licensing & Attribution

- Preserve the root Apache-2.0 [LICENSE](LICENSE).
- Add an SPDX header to original source files:
  - Rust: `// SPDX-License-Identifier: Apache-2.0`
  - Shell / YAML: `# SPDX-License-Identifier: Apache-2.0`
- Do not add ASF-specific contribution headers to independent original files.
- When copying or modifying upstream DataFusion or other third-party code, preserve original copyright and license headers, retain applicable `NOTICE` attributions, and note modifications where required.
- No CLA or DCO sign-off is required; contributions are submitted under the terms of Apache License 2.0 Section 5.
