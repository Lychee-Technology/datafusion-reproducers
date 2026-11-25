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
    for lock_probe in "repros/_probe/Cargo.lock" "repros/_probe/nested/Cargo.lock"; do
        if git -C "$REPO_ROOT" check-ignore -q "$lock_probe"; then
            fail ".gitignore must not ignore $lock_probe"
        fi
    done
    for target_probe in "repros/_probe/target/debug/probe" "repros/_probe/nested/target/debug/probe"; do
        if ! git -C "$REPO_ROOT" check-ignore -q "$target_probe"; then
            fail ".gitignore must ignore $target_probe build artifacts"
        fi
    done
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
inspect_case_manifests() {
    local case_dir="$1"
    local case_name="$2"
    python3 - "$case_dir" "$case_name" <<'PY'
from collections import defaultdict, deque
import os
from pathlib import Path
import sys
import tomllib

case_dir = Path(sys.argv[1]).resolve()
case_name = sys.argv[2]

manifest_paths = []
for root, dirs, files in os.walk(case_dir, topdown=True):
    dirs[:] = sorted(
        d for d in dirs
        if d not in {"target", ".git"} and not d.startswith("mutants.out")
    )
    if "Cargo.toml" in files:
        manifest_paths.append((Path(root) / "Cargo.toml").resolve())

manifest_paths.sort()
if not manifest_paths:
    print(f"Case '{case_name}' contains no Cargo.toml files under {case_dir}", file=sys.stderr)
    sys.exit(1)

manifests = {}
for mpath in manifest_paths:
    try:
        with open(mpath, "rb") as f:
            data = tomllib.load(f)
    except Exception as exc:
        print(f"Failed to parse {mpath}: {exc}", file=sys.stderr)
        sys.exit(1)
    if not isinstance(data.get("package"), dict) and not isinstance(data.get("workspace"), dict):
        print(f"{mpath}: must define [package] and/or [workspace]", file=sys.stderr)
        sys.exit(1)
    manifests[mpath.parent] = data

workspace_roots = {
    mdir for mdir, data in manifests.items()
    if isinstance(data.get("workspace"), dict)
}


def expand_patterns(ws_dir: Path, patterns) -> list[Path]:
    matched = []
    if not isinstance(patterns, list):
        return matched
    for raw in patterns:
        if not isinstance(raw, str) or not raw:
            continue
        pat = raw.rstrip("/")
        if not pat:
            matched.append(ws_dir)
            continue
        try:
            for p in ws_dir.glob(pat):
                if p.is_dir():
                    matched.append(p.resolve())
        except Exception:
            pass
        literal = (ws_dir / pat).resolve()
        if literal.is_dir():
            matched.append(literal)
    return matched


ws_members_cache = {}
ws_excludes_cache = {}
for wdir in workspace_roots:
    ws_table = manifests[wdir]["workspace"]
    ws_members_cache[wdir] = set(expand_patterns(wdir, ws_table.get("members", [])))
    ws_excludes_cache[wdir] = set(expand_patterns(wdir, ws_table.get("exclude", [])))


def is_excluded(mdir: Path, wdir: Path) -> bool:
    for excl in ws_excludes_cache[wdir]:
        if mdir == excl or excl in mdir.parents:
            return True
    return False


def iter_dep_entries(data: dict):
    for section in ("dependencies", "dev-dependencies", "build-dependencies"):
        table = data.get(section)
        if isinstance(table, dict):
            yield from table.items()
    target_table = data.get("target")
    if isinstance(target_table, dict):
        for cfg_table in target_table.values():
            if not isinstance(cfg_table, dict):
                continue
            for section in ("dependencies", "dev-dependencies", "build-dependencies"):
                table = cfg_table.get(section)
                if isinstance(table, dict):
                    yield from table.items()


def iter_direct_path_deps(mdir: Path, data: dict) -> list[Path]:
    paths = []
    for _, spec in iter_dep_entries(data):
        if isinstance(spec, dict) and isinstance(spec.get("path"), str) and spec["path"]:
            paths.append((mdir / spec["path"]).resolve())
    patch_table = data.get("patch")
    if isinstance(patch_table, dict):
        for src_table in patch_table.values():
            if not isinstance(src_table, dict):
                continue
            for spec in src_table.values():
                if isinstance(spec, dict) and isinstance(spec.get("path"), str) and spec["path"]:
                    paths.append((mdir / spec["path"]).resolve())
    return paths


def iter_workspace_inherited_path_deps(mdir: Path, wdir: Path) -> list[Path]:
    ws_deps = manifests[wdir]["workspace"].get("dependencies")
    if not isinstance(ws_deps, dict):
        return []
    paths = []
    for dep_key, dep_spec in iter_dep_entries(manifests[mdir]):
        if isinstance(dep_spec, dict) and dep_spec.get("workspace") is True:
            ws_spec = ws_deps.get(dep_key)
            if isinstance(ws_spec, dict) and isinstance(ws_spec.get("path"), str) and ws_spec["path"]:
                paths.append((wdir / ws_spec["path"]).resolve())
    return paths


def nearest_enclosing_workspace(mdir: Path) -> Path | None:
    ancestors = sorted(
        (w for w in workspace_roots if w in mdir.parents),
        key=lambda p: len(p.parts),
        reverse=True,
    )
    return ancestors[0] if ancestors else None


classifications = {}
member_counts = {wdir: 0 for wdir in workspace_roots}

# Phase 1a: explicit workspace roots and explicit workspace members.
for mdir, data in manifests.items():
    if mdir in workspace_roots:
        classifications[mdir] = ("workspace", mdir)
        continue

    pkg = data.get("package")
    if isinstance(pkg, dict) and "workspace" in pkg:
        ws_rel = pkg["workspace"]
        if not isinstance(ws_rel, str):
            print(f"{mdir / 'Cargo.toml'}: [package].workspace must be a string path", file=sys.stderr)
            sys.exit(1)
        target_ws = (mdir / ws_rel).resolve()
        if target_ws not in workspace_roots or (target_ws != case_dir and case_dir not in target_ws.parents):
            print(
                f"{mdir / 'Cargo.toml'}: [package].workspace points outside case or to non-workspace ({target_ws})",
                file=sys.stderr,
            )
            sys.exit(1)
        classifications[mdir] = ("member", target_ws)
        member_counts[target_ws] += 1
        continue

    owner = None
    # Nearest enclosing workspace ancestor wins if nested workspaces exist.
    ancestors = sorted(
        (w for w in workspace_roots if w in mdir.parents),
        key=lambda p: len(p.parts),
        reverse=True,
    )
    for wdir in ancestors:
        if is_excluded(mdir, wdir):
            continue
        if mdir in ws_members_cache[wdir]:
            owner = wdir
            break

    if owner is not None:
        classifications[mdir] = ("member", owner)
        member_counts[owner] += 1

# Phase 1b: implicit workspace members reached via path dependencies inside a workspace.
for wdir in sorted(workspace_roots):
    queue = deque()
    for mdir in sorted(manifests):
        entry = classifications.get(mdir)
        if entry == ("workspace", wdir) and isinstance(manifests[wdir].get("package"), dict):
            queue.append(mdir)
        elif entry == ("member", wdir):
            queue.append(mdir)

    while queue:
        cur = queue.popleft()
        deps = iter_direct_path_deps(cur, manifests[cur]) + iter_workspace_inherited_path_deps(cur, wdir)
        for dep_dir in deps:
            if (
                dep_dir in manifests
                and dep_dir not in workspace_roots
                and dep_dir not in classifications
                and nearest_enclosing_workspace(dep_dir) == wdir
                and not is_excluded(dep_dir, wdir)
            ):
                classifications[dep_dir] = ("member", wdir)
                member_counts[wdir] += 1
                queue.append(dep_dir)

# Phase 2: classify remaining manifests into standalone roots vs. non-workspace path-dep helpers.
# Path-dep helpers are rejected below; classifying them here lets the error name the
# helper instead of reporting a misleading missing Cargo.lock.
remaining = sorted(mdir for mdir in manifests if mdir not in classifications)
remaining_set = set(remaining)
incoming = defaultdict(set)
outgoing = defaultdict(set)
reached_from_workspace = set()

for mdir, data in manifests.items():
    deps = list(iter_direct_path_deps(mdir, data))
    if mdir in classifications:
        kind, owner = classifications[mdir]
        ws_dir = mdir if kind == "workspace" else owner
        if ws_dir is not None:
            deps.extend(iter_workspace_inherited_path_deps(mdir, ws_dir))
    for dep_dir in deps:
        if dep_dir != mdir and dep_dir in remaining_set:
            incoming[dep_dir].add(mdir)
            if mdir in remaining_set:
                outgoing[mdir].add(dep_dir)
            else:
                reached_from_workspace.add(dep_dir)


def mark_reachable_as_path_dep(seeds, protected_roots: set[Path]):
    q = deque(seeds)
    while q:
        cur = q.popleft()
        if cur in protected_roots or cur in classifications:
            continue
        classifications[cur] = ("path-dep", None)
        for nxt in sorted(outgoing[cur]):
            if nxt not in protected_roots and nxt not in classifications:
                q.append(nxt)


mark_reachable_as_path_dep(sorted(reached_from_workspace), set())

root_seeds = [m for m in remaining if m not in classifications and not incoming[m]]
standalone_roots = set(root_seeds)
for m in root_seeds:
    classifications[m] = ("standalone", None)
direct_targets = sorted({nxt for m in root_seeds for nxt in outgoing[m]})
mark_reachable_as_path_dep(direct_targets, standalone_roots)

while True:
    unclassified = [m for m in remaining if m not in classifications]
    if not unclassified:
        break
    chosen = min(
        unclassified,
        key=lambda m: (0 if (m / "Cargo.lock").is_file() else 1, len(m.parts), str(m)),
    )
    classifications[chosen] = ("standalone", None)
    standalone_roots.add(chosen)
    mark_reachable_as_path_dep(sorted(outgoing[chosen]), standalone_roots)

for wdir in sorted(workspace_roots):
    ws_table = manifests[wdir]["workspace"]
    has_pkg = isinstance(manifests[wdir].get("package"), dict)
    if not has_pkg:
        members_cfg = ws_table.get("members")
        if not isinstance(members_cfg, list) or not members_cfg or member_counts[wdir] == 0:
            print(
                f"{wdir / 'Cargo.toml'}: virtual [workspace] must declare non-empty members matching at least one discovered member crate",
                file=sys.stderr,
            )
            sys.exit(1)


def resolve_pkg_field(mdir: Path, field: str):
    pkg = manifests[mdir]["package"]
    val = pkg.get(field)
    if isinstance(val, dict) and val.get("workspace") is True:
        kind, owner = classifications[mdir]
        ws_dir = mdir if kind == "workspace" else owner
        if ws_dir is None:
            print(
                f"{mdir / 'Cargo.toml'}: [package].{field}.workspace = true used without an owning [workspace]",
                file=sys.stderr,
            )
            sys.exit(1)
        ws_pkg = manifests[ws_dir]["workspace"].get("package")
        if not isinstance(ws_pkg, dict):
            print(
                f"{mdir / 'Cargo.toml'}: [package].{field}.workspace = true requires [workspace.package] in {ws_dir / 'Cargo.toml'}",
                file=sys.stderr,
            )
            sys.exit(1)
        return ws_pkg.get(field)
    return val


def has_toolchain_in_ancestors(mdir: Path) -> bool:
    cur = mdir
    while True:
        if (cur / "rust-toolchain.toml").is_file():
            return True
        if cur == case_dir or cur.parent == cur:
            break
        cur = cur.parent
    return False


def would_adopt_as_implicit_member(root: Path, target: Path) -> bool:
    # If `root` declared [workspace], Cargo (and Phase 1b) would adopt every crate reachable
    # from it through path dependencies that live in its directory with no closer workspace
    # root in between. Dependents outside `root` do not prevent this.
    def inside(d: Path) -> bool:
        return root in d.parents and not any(
            root in w.parents and w in d.parents for w in workspace_roots
        )

    seen = {root}
    q = deque([root])
    while q:
        cur = q.popleft()
        for nxt in sorted(outgoing[cur]):
            if nxt in seen or not inside(nxt):
                continue
            if nxt == target:
                return True
            seen.add(nxt)
            q.append(nxt)
    return False


def helper_remedy(mdir: Path) -> str:
    # Only suggest a remedy that makes this helper a checked crate for its actual layout:
    # an enclosing root's [workspace] adopts a helper only if the helper lives in that
    # root's directory, is not excluded, and is reachable from that root through path
    # dependencies inside its directory.
    own_ws = "give this crate its own [workspace] table and Cargo.lock"
    enclosing = [r for r in standalone_roots | workspace_roots if r in mdir.parents]
    if not enclosing:
        return f"Because it is outside every root crate's directory, {own_ws}"
    nearest = max(enclosing, key=lambda p: len(p.parts))
    rel_root = nearest.relative_to(case_dir) / "Cargo.toml"
    if nearest in workspace_roots:
        if is_excluded(mdir, nearest):
            return f"Remove it from [workspace].exclude in {rel_root}, or {own_ws}"
        return f"Add it to [workspace].members in {rel_root}, or {own_ws}"
    if not would_adopt_as_implicit_member(nearest, mdir):
        return (
            f"Because {rel_root} does not reach it through path dependencies in its directory, "
            f"a [workspace] table there would not adopt it, so {own_ws}"
        )
    return (
        f"Add a [workspace] table to {rel_root} so this crate becomes an implicit member, "
        f"or {own_ws}"
    )


root_manifests = []
for mdir in sorted(manifests):
    data = manifests[mdir]
    mpath = mdir / "Cargo.toml"
    kind, _ = classifications[mdir]
    if kind == "path-dep":
        # Cargo runs fmt, clippy-driver, and tests only on workspace members, so a
        # non-member path dependency would compile but never be linted or tested.
        dependents = ", ".join(
            str((d / "Cargo.toml").relative_to(case_dir)) for d in sorted(incoming[mdir])
        )
        print(
            f"{mpath}: path-dependency crate (used by {dependents}) is not a member of any "
            "workspace in the case, so cargo fmt, clippy, and test would not check it. "
            f"{helper_remedy(mdir)}",
            file=sys.stderr,
        )
        sys.exit(1)

    if isinstance(data.get("package"), dict):
        publish = resolve_pkg_field(mdir, "publish")
        if publish is not False:
            print(
                f"{mpath}: [package].publish must resolve to false (found {publish!r})",
                file=sys.stderr,
            )
            sys.exit(1)

        license_val = resolve_pkg_field(mdir, "license")
        if license_val != "Apache-2.0":
            print(
                f"{mpath}: [package].license must resolve to \"Apache-2.0\" (found {license_val!r})",
                file=sys.stderr,
            )
            sys.exit(1)

    if kind in {"standalone", "workspace"}:
        if not (mdir / "Cargo.lock").is_file():
            rel = mdir.relative_to(case_dir)
            loc = "Cargo.lock" if rel == Path(".") else f"{rel}/Cargo.lock"
            print(
                f"Case '{case_name}' is missing required lockfile: {loc}",
                file=sys.stderr,
            )
            sys.exit(1)
        if not has_toolchain_in_ancestors(mdir):
            rel = mdir.relative_to(case_dir)
            label = case_name if rel == Path(".") else f"{case_name}/{rel}"
            print(
                f"[WARN] Case '{label}' has no rust-toolchain.toml; ensure toolchain is documented in README.md",
                file=sys.stderr,
            )
        root_manifests.append((kind, str(mdir)))

for kind, mdir_str in root_manifests:
    sys.stdout.buffer.write(kind.encode("utf-8") + b"\0" + mdir_str.encode("utf-8") + b"\0")
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
        if [[ "${CI:-}" == "true" || "${CI:-}" == "1" ]]; then
            if command -v rustup >/dev/null 2>&1; then
                echo "Installing missing rustup components: ${missing[*]}"
                rustup component add "${missing[@]}"
            else
                fail "Missing Cargo components (${missing[*]}) and rustup is not available"
            fi
        elif command -v rustup >/dev/null 2>&1; then
            fail "Missing Cargo components (${missing[*]}). Install them with: rustup component add ${missing[*]}"
        else
            fail "Missing Cargo components (${missing[*]}) and rustup is not available"
        fi
    fi
}

manifest_list_file="$(mktemp)"
cleanup_manifest_list() {
    rm -f "$manifest_list_file"
}
trap cleanup_manifest_list EXIT

for case_dir in "${cases[@]}"; do
    case_name="$(basename "$case_dir")"
    echo "Checking case: $case_name ($case_dir)"

    if [[ ! -f "$case_dir/README.md" ]]; then
        fail "Case '$case_name' is missing required file: README.md"
    fi

    inspect_case_manifests "$case_dir" "$case_name" > "$manifest_list_file"

    root_entries=()
    while IFS= read -r -d '' kind && IFS= read -r -d '' mdir; do
        root_entries+=("$kind" "$mdir")
    done < "$manifest_list_file"

    root_count=$(( ${#root_entries[@]} / 2 ))
    pass "Case '$case_name' metadata verified ($root_count root manifest(s), all nested Cargo.toml compliant: publish = false, license = Apache-2.0, Cargo.lock, README.md)"

    if [[ "$metadata_only" == false ]]; then
        for ((i = 0; i < ${#root_entries[@]}; i += 2)); do
            kind="${root_entries[i]}"
            mdir="${root_entries[i + 1]}"
            echo "Running Cargo checks ($kind): $mdir"
            (
                cd "$mdir"
                ensure_rust_components
                if [[ "$kind" == "workspace" ]]; then
                    cargo fmt --all --check
                    cargo clippy --workspace --locked --all-targets -- -D warnings
                    cargo test --workspace --locked
                    if [[ "$run_release" == true ]]; then
                        cargo build --workspace --release --locked
                    fi
                else
                    cargo fmt --check
                    cargo clippy --locked --all-targets -- -D warnings
                    cargo test --locked
                    if [[ "$run_release" == true ]]; then
                        cargo build --release --locked
                    fi
                fi
            )
        done
        pass "Case '$case_name' Rust checks passed ($root_count root manifest(s))"
    fi
done

pass "All ${#cases[@]} reproduction case(s) passed checks"
