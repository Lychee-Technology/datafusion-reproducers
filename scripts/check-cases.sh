#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/check-cases.sh [OPTIONS] [CASE_DIR...]

Validate repository invariants and standalone reproduction cases under repros/.

Options:
  --metadata-only   Check repository invariants and case metadata without running cargo
  --release         Also run `cargo build --release --locked` for each case
  -h, --help        Show this help message and exit

Environment:
  REPO_ROOT         Override repository root directory (defaults to parent of scripts/)
EOF
}

pass() {
    printf '[PASS] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

metadata_only=false
run_release=false
explicit_cases=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --metadata-only)
            metadata_only=true
            shift
            ;;
        --release)
            run_release=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            while [[ $# -gt 0 ]]; do
                explicit_cases+=("$1")
                shift
            done
            ;;
        -*)
            fail "Unknown option: $1"
            ;;
        *)
            explicit_cases+=("$1")
            shift
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if [[ ! -d "$REPO_ROOT" ]]; then
    fail "REPO_ROOT does not exist or is not a directory: $REPO_ROOT"
fi

# 1. Repository-level invariants
if [[ -f "$REPO_ROOT/Cargo.toml" ]]; then
    fail "Root Cargo.toml must not exist; cases under repros/ must remain independent crates"
fi
pass "No root Cargo.toml workspace"

if [[ ! -f "$REPO_ROOT/LICENSE" ]]; then
    fail "Missing root LICENSE file at $REPO_ROOT/LICENSE"
fi
if ! grep -Fq "Apache License" "$REPO_ROOT/LICENSE" || ! grep -Fq "Version 2.0" "$REPO_ROOT/LICENSE"; then
    fail "Root LICENSE must be Apache License Version 2.0"
fi
pass "Root LICENSE verified as Apache-2.0"

if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git -C "$REPO_ROOT" check-ignore -q "repros/_probe/Cargo.lock"; then
        fail ".gitignore must not ignore repros/<case-slug>/Cargo.lock"
    fi
    if ! git -C "$REPO_ROOT" check-ignore -q "repros/_probe/target/debug/probe"; then
        fail ".gitignore must ignore repros/<case-slug>/target/ build artifacts"
    fi
    pass ".gitignore tracks per-case Cargo.lock and ignores target/ artifacts"
else
    warn "Skipping git check-ignore verification ($REPO_ROOT is not a Git work tree)"
fi

# 2. Discover cases
cases=()
if [[ ${#explicit_cases[@]} -gt 0 ]]; then
    for raw_case in "${explicit_cases[@]}"; do
        if [[ -d "$raw_case" ]]; then
            cases+=("$(cd "$raw_case" && pwd)")
        elif [[ -d "$REPO_ROOT/$raw_case" ]]; then
            cases+=("$(cd "$REPO_ROOT/$raw_case" && pwd)")
        else
            fail "Specified case directory does not exist: $raw_case"
        fi
    done
elif [[ -d "$REPO_ROOT/repros" ]]; then
    shopt -s nullglob
    raw_dirs=("$REPO_ROOT/repros"/*/)
    shopt -u nullglob
    if [[ ${#raw_dirs[@]} -gt 0 ]]; then
        while IFS= read -r dir; do
            cases+=("${dir%/}")
        done < <(printf '%s\n' "${raw_dirs[@]}" | LC_ALL=C sort)
    fi
fi

if [[ ${#cases[@]} -eq 0 ]]; then
    echo "No reproduction cases found under repros/; repository checks passed."
    exit 0
fi

# 3. Validate tooling requirements once
if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 is required to validate case Cargo.toml metadata"
fi
if ! python3 -c 'import tomllib' >/dev/null 2>&1; then
    fail "python3 with stdlib tomllib (Python 3.11+) is required to validate Cargo.toml"
fi

if [[ "$metadata_only" == false ]] && ! command -v cargo >/dev/null 2>&1; then
    fail "cargo is required when running without --metadata-only"
fi

# 4. Per-case checks
validate_manifest() {
    local manifest_path="$1"
    python3 - "$manifest_path" <<'PY'
import sys
import tomllib

manifest_path = sys.argv[1]
try:
    with open(manifest_path, "rb") as f:
        data = tomllib.load(f)
except Exception as exc:
    print(f"Failed to parse {manifest_path}: {exc}", file=sys.stderr)
    sys.exit(1)

pkg = data.get("package")
if not isinstance(pkg, dict):
    print(f"Missing [package] table in {manifest_path}", file=sys.stderr)
    sys.exit(1)

publish = pkg.get("publish")
if publish is not False:
    print(
        f"{manifest_path}: [package].publish must be explicitly set to false (found {publish!r})",
        file=sys.stderr,
    )
    sys.exit(1)

license_val = pkg.get("license")
if license_val != "Apache-2.0":
    print(
        f"{manifest_path}: [package].license must be \"Apache-2.0\" (found {license_val!r})",
        file=sys.stderr,
    )
    sys.exit(1)
PY
}

ensure_rust_components() {
    local missing=()
    if ! cargo fmt --version >/dev/null 2>&1; then
        missing+=("rustfmt")
    fi
    if ! cargo clippy --version >/dev/null 2>&1; then
        missing+=("clippy")
    fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        if command -v rustup >/dev/null 2>&1; then
            echo "Installing missing rustup components: ${missing[*]}"
            rustup component add "${missing[@]}"
        else
            fail "Missing Cargo components (${missing[*]}) and rustup is not available"
        fi
    fi
}

for case_dir in "${cases[@]}"; do
    case_name="$(basename "$case_dir")"
    echo "Checking case: $case_name ($case_dir)"

    for req_file in Cargo.toml Cargo.lock README.md; do
        if [[ ! -f "$case_dir/$req_file" ]]; then
            fail "Case '$case_name' is missing required file: $req_file"
        fi
    done

    if [[ ! -f "$case_dir/rust-toolchain.toml" ]]; then
        warn "Case '$case_name' has no rust-toolchain.toml; ensure toolchain is documented in README.md"
    fi

    validate_manifest "$case_dir/Cargo.toml"
    pass "Case '$case_name' metadata verified (publish = false, license = Apache-2.0, Cargo.lock, README.md)"

    if [[ "$metadata_only" == false ]]; then
        (
            cd "$case_dir"
            ensure_rust_components
            cargo fmt --check
            cargo clippy --locked --all-targets -- -D warnings
            cargo test --locked
            if [[ "$run_release" == true ]]; then
                cargo build --release --locked
            fi
        )
        pass "Case '$case_name' Rust checks passed"
    fi
done

pass "All ${#cases[@]} reproduction case(s) passed checks"
