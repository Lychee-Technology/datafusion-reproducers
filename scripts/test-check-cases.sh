#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

export CARGO_NET_OFFLINE=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK_SCRIPT="$REPO_ROOT/scripts/check-cases.sh"

TMP_ROOT="$(mktemp -d)"
cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

pass() {
    printf '[TEST PASS] %s\n' "$*"
}

fail() {
    printf '[TEST FAIL] %s\n' "$*" >&2
    exit 1
}

sha256_file() {
    python3 - "$1" <<'PY'
import hashlib
import sys

with open(sys.argv[1], "rb") as f:
    print(hashlib.sha256(f.read()).hexdigest())
PY
}

replace_in_file() {
    local file="$1"
    local old="$2"
    local new="$3"
    python3 - "$file" "$old" "$new" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
old, new = sys.argv[2], sys.argv[3]
text = path.read_text(encoding="utf-8")
if old not in text:
    print(f"replace_in_file: {old!r} not found in {path}", file=sys.stderr)
    sys.exit(1)
path.write_text(text.replace(old, new), encoding="utf-8")
PY
}

delete_line_prefix() {
    local file="$1"
    local prefix="$2"
    python3 - "$file" "$prefix" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
prefix = sys.argv[2]
lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
kept = [line for line in lines if not line.startswith(prefix)]
if len(kept) == len(lines):
    print(f"delete_line_prefix: no line starting with {prefix!r} in {path}", file=sys.stderr)
    sys.exit(1)
path.write_text("".join(kept), encoding="utf-8")
PY
}

run_check() {
    local repo_dir="$1"
    shift
    env -u CI REPO_ROOT="$repo_dir" "$CHECK_SCRIPT" "$@"
}

expect_fail() {
    local desc="$1"
    local expected_substr="$2"
    local repo_dir="$3"
    shift 3
    local out_file="$TMP_ROOT/last_err.log"
    if env -u CI REPO_ROOT="$repo_dir" "$CHECK_SCRIPT" "$@" >"$out_file" 2>&1; then
        cat "$out_file" >&2
        fail "Expected failure for: $desc"
    fi
    if ! grep -Fq -- "$expected_substr" "$out_file"; then
        cat "$out_file" >&2
        fail "Failure output for '$desc' did not contain expected text: $expected_substr"
    fi
    pass "Rejected as expected: $desc"
}

init_temp_repo() {
    local dir="$1"
    rm -rf "$dir"
    mkdir -p "$dir"
    cp "$REPO_ROOT/LICENSE" "$dir/LICENSE"
    cp "$REPO_ROOT/.gitignore" "$dir/.gitignore"
    git -C "$dir" init -q
}

write_valid_rust_pkg() {
    local pkg_dir="$1"
    local pkg_name="$2"
    local extra_toml="${3:-}"
    local dep_line="${4:-}"
    mkdir -p "$pkg_dir/src"
    cat >"$pkg_dir/Cargo.toml" <<EOF
[package]
name = "$pkg_name"
version = "0.1.0"
edition = "2021"
publish = false
license = "Apache-2.0"
$extra_toml

[dependencies]
$dep_line
EOF
    cat >"$pkg_dir/src/main.rs" <<'EOF'
// SPDX-License-Identifier: Apache-2.0

fn main() {
    println!("ok");
}

#[cfg(test)]
mod tests {
    #[test]
    fn smoke() {
        assert_eq!(1 + 1, 2);
    }
}
EOF
}

write_dep_crate() {
    local dep_dir="$1"
    local version="$2"
    mkdir -p "$dep_dir/src"
    cat >"$dep_dir/Cargo.toml" <<EOF
[package]
name = "mock-dep"
version = "$version"
edition = "2021"
publish = false
license = "Apache-2.0"
EOF
    cat >"$dep_dir/src/lib.rs" <<EOF
// SPDX-License-Identifier: Apache-2.0

pub fn dep_version() -> &'static str {
    "$version"
}
EOF
}

write_valid_rust_lib() {
    local pkg_dir="$1"
    local pkg_name="$2"
    local extra_toml="${3:-}"
    local dep_line="${4:-}"
    local body="${5-}"
    if [[ -z "$body" ]]; then
        body='pub fn helper_val() -> i32 {
    42
}'
    fi
    mkdir -p "$pkg_dir/src"
    cat >"$pkg_dir/Cargo.toml" <<EOF
[package]
name = "$pkg_name"
version = "0.1.0"
edition = "2021"
publish = false
license = "Apache-2.0"
$extra_toml

[dependencies]
$dep_line
EOF
    cat >"$pkg_dir/src/lib.rs" <<EOF
// SPDX-License-Identifier: Apache-2.0

$body

#[cfg(test)]
mod tests {
    #[test]
    fn smoke() {
        assert_eq!(1 + 1, 2);
    }
}
EOF
}

gen_lockfile() {
    local manifest_dir="$1"
    (cd "$manifest_dir" && cargo generate-lockfile --offline >/dev/null 2>&1)
}

echo "=== 1. Zero-case repository checks ==="
r0="$TMP_ROOT/repo-zero"
init_temp_repo "$r0"
run_check "$r0" >/dev/null
pass "0-case repository without repros/ passes"
mkdir -p "$r0/repros"
run_check "$r0" >/dev/null
pass "0-case repository with empty repros/ passes"

echo "=== 2. Repository-level invariant checks ==="
r_inv="$TMP_ROOT/repo-inv"
init_temp_repo "$r_inv"
printf '[workspace]\nmembers = []\n' >"$r_inv/Cargo.toml"
expect_fail "root Cargo.toml present" "Root Cargo.toml must not exist" "$r_inv"
rm -f "$r_inv/Cargo.toml"

printf 'MIT License\n' >"$r_inv/LICENSE"
expect_fail "non-Apache-2.0 LICENSE" "Root LICENSE must be Apache License Version 2.0" "$r_inv"
cp "$REPO_ROOT/LICENSE" "$r_inv/LICENSE"

printf 'Cargo.lock\n' >>"$r_inv/.gitignore"
expect_fail ".gitignore ignoring Cargo.lock" ".gitignore must not ignore" "$r_inv"
cp "$REPO_ROOT/.gitignore" "$r_inv/.gitignore"

printf '# empty\n' >"$r_inv/.gitignore"
expect_fail ".gitignore not ignoring target/" ".gitignore must ignore" "$r_inv"

echo "=== 3. Independent multi-case isolation, --release, and single-case filter ==="
deps_dir="$TMP_ROOT/mock-deps"
write_dep_crate "$deps_dir/v1" "0.1.0"
write_dep_crate "$deps_dir/v2" "0.2.0"

r_iso="$TMP_ROOT/repo-iso"
init_temp_repo "$r_iso"
mkdir -p "$r_iso/repros/case-alpha"
printf '# case-alpha\n' >"$r_iso/repros/case-alpha/README.md"
write_valid_rust_pkg "$r_iso/repros/case-alpha" "case-alpha" "" "mock-dep = { path = \"$deps_dir/v1\" }"
gen_lockfile "$r_iso/repros/case-alpha"
alpha_sha_before="$(sha256_file "$r_iso/repros/case-alpha/Cargo.lock")"

mkdir -p "$r_iso/repros/case-beta"
printf '# case-beta\n' >"$r_iso/repros/case-beta/README.md"
write_valid_rust_pkg "$r_iso/repros/case-beta" "case-beta" "" "mock-dep = { path = \"$deps_dir/v2\" }"
gen_lockfile "$r_iso/repros/case-beta"

run_check "$r_iso" --release >/dev/null
alpha_sha_after="$(sha256_file "$r_iso/repros/case-alpha/Cargo.lock")"
if [[ "$alpha_sha_before" != "$alpha_sha_after" ]]; then
    fail "case-alpha/Cargo.lock changed after adding case-beta"
fi
pass "Multi-case --release passes and preserves case-alpha/Cargo.lock"

run_check "$r_iso" "repros/case-alpha" >/dev/null
pass "Single-case path argument passes"

echo "=== 4. Nested standalone manifest checks (reviewer regression) ==="
r_nested="$TMP_ROOT/repo-nested"
init_temp_repo "$r_nested"
mkdir -p "$r_nested/repros/cmp/v55"
printf '# cmp\n' >"$r_nested/repros/cmp/README.md"
write_valid_rust_pkg "$r_nested/repros/cmp" "cmp-root"
gen_lockfile "$r_nested/repros/cmp"

# Compliant nested package + stray non-compliant Cargo.toml under target/
write_valid_rust_pkg "$r_nested/repros/cmp/v55" "cmp-v55"
gen_lockfile "$r_nested/repros/cmp/v55"
mkdir -p "$r_nested/repros/cmp/target/stray" "$r_nested/repros/cmp/v55/target/stray"
printf '[package]\nname = "stray"\nversion = "0.1.0"\npublish = true\nlicense = "MIT"\n' >"$r_nested/repros/cmp/target/stray/Cargo.toml"
printf '[package]\nname = "stray2"\nversion = "0.1.0"\npublish = true\nlicense = "MIT"\n' >"$r_nested/repros/cmp/v55/target/stray/Cargo.toml"
run_check "$r_nested" >/dev/null
pass "Compliant root + nested manifest passes while excluding target/ Cargo.toml"

# Nested publish = true
replace_in_file "$r_nested/repros/cmp/v55/Cargo.toml" 'publish = false' 'publish = true'
expect_fail "nested manifest with publish = true" "v55/Cargo.toml: [package].publish must resolve to false (found True)" "$r_nested"

# Nested omitted publish
delete_line_prefix "$r_nested/repros/cmp/v55/Cargo.toml" 'publish = '
expect_fail "nested manifest with omitted publish" "v55/Cargo.toml: [package].publish must resolve to false (found None)" "$r_nested"

# Nested license = MIT
write_valid_rust_pkg "$r_nested/repros/cmp/v55" "cmp-v55"
replace_in_file "$r_nested/repros/cmp/v55/Cargo.toml" 'license = "Apache-2.0"' 'license = "MIT"'
expect_fail "nested manifest with license = MIT" 'v55/Cargo.toml: [package].license must resolve to "Apache-2.0" (found '\''MIT'\'')' "$r_nested"

# Nested missing Cargo.lock
write_valid_rust_pkg "$r_nested/repros/cmp/v55" "cmp-v55"
rm -f "$r_nested/repros/cmp/v55/Cargo.lock"
expect_fail "nested standalone manifest missing Cargo.lock" "missing required lockfile: v55/Cargo.lock" "$r_nested"
gen_lockfile "$r_nested/repros/cmp/v55"

# Nested unformatted code
printf '// SPDX-License-Identifier: Apache-2.0\nfn main(){println!("bad");}\n' >"$r_nested/repros/cmp/v55/src/main.rs"
expect_fail "nested manifest with unformatted src/main.rs" "v55/src/main.rs" "$r_nested"

# Nested clippy warning
cat >"$r_nested/repros/cmp/v55/src/main.rs" <<'EOF'
// SPDX-License-Identifier: Apache-2.0

fn main() {
    let x = 1;
    if x == x {
        println!("clippy");
    }
}
EOF
expect_fail "nested manifest with clippy warning" "clippy::eq_op" "$r_nested"

# Nested failing unit test
cat >"$r_nested/repros/cmp/v55/src/main.rs" <<'EOF'
// SPDX-License-Identifier: Apache-2.0

fn main() {
    println!("ok");
}

#[cfg(test)]
mod tests {
    #[test]
    fn fails() {
        assert_eq!(1, 2);
    }
}
EOF
expect_fail "nested manifest with failing unit test" "tests::fails ... FAILED" "$r_nested"

echo "=== 5. Nested-only case (no root Cargo.toml) and zero-manifest case ==="
r_nonly="$TMP_ROOT/repo-nested-only"
init_temp_repo "$r_nonly"
mkdir -p "$r_nonly/repros/versions/v55" "$r_nonly/repros/versions/v56"
printf '# versions\n' >"$r_nonly/repros/versions/README.md"
write_valid_rust_pkg "$r_nonly/repros/versions/v55" "versions-v55"
write_valid_rust_pkg "$r_nonly/repros/versions/v56" "versions-v56"
gen_lockfile "$r_nonly/repros/versions/v55"
gen_lockfile "$r_nonly/repros/versions/v56"
run_check "$r_nonly" >/dev/null
pass "Nested-only case (v55 + v56 without root Cargo.toml) passes"

r_empty_case="$TMP_ROOT/repo-empty-case"
init_temp_repo "$r_empty_case"
mkdir -p "$r_empty_case/repros/empty-case"
printf '# empty\n' >"$r_empty_case/repros/empty-case/README.md"
expect_fail "case directory with zero Cargo.toml files" "contains no Cargo.toml files" "$r_empty_case"

echo "=== 6. Case-internal Cargo workspace checks ==="
r_ws="$TMP_ROOT/repo-ws"
init_temp_repo "$r_ws"
mkdir -p "$r_ws/repros/ws-case/crates/member-a"
printf '# ws-case\n' >"$r_ws/repros/ws-case/README.md"
cat >"$r_ws/repros/ws-case/Cargo.toml" <<'EOF'
[workspace]
resolver = "2"
members = ["crates/*"]
exclude = ["excluded-pkg"]

[workspace.package]
license = "Apache-2.0"
publish = false
EOF
cat >"$r_ws/repros/ws-case/crates/member-a/Cargo.toml" <<'EOF'
[package]
name = "member-a"
version = "0.1.0"
edition = "2021"
publish.workspace = true
license.workspace = true
EOF
mkdir -p "$r_ws/repros/ws-case/crates/member-a/src"
cat >"$r_ws/repros/ws-case/crates/member-a/src/lib.rs" <<'EOF'
// SPDX-License-Identifier: Apache-2.0

pub fn add(a: i32, b: i32) -> i32 {
    a + b
}

#[cfg(test)]
mod tests {
    use super::add;

    #[test]
    fn adds() {
        assert_eq!(add(2, 3), 5);
    }
}
EOF
gen_lockfile "$r_ws/repros/ws-case"

# Excluded package requires its own Cargo.lock and standalone compliance
write_valid_rust_pkg "$r_ws/repros/ws-case/excluded-pkg" "excluded-pkg"
expect_fail "workspace-excluded package missing Cargo.lock" "missing required lockfile: excluded-pkg/Cargo.lock" "$r_ws"
gen_lockfile "$r_ws/repros/ws-case/excluded-pkg"

run_check "$r_ws" --release >/dev/null
pass "Case-internal virtual workspace (with inherited metadata and excluded standalone pkg) passes"

# Workspace member override publish = true fails
cat >"$r_ws/repros/ws-case/crates/member-a/Cargo.toml" <<'EOF'
[package]
name = "member-a"
version = "0.1.0"
edition = "2021"
publish = true
license.workspace = true
EOF
expect_fail "workspace member overriding publish = true" "member-a/Cargo.toml: [package].publish must resolve to false (found True)" "$r_ws"

# Workspace member override license = MIT fails
cat >"$r_ws/repros/ws-case/crates/member-a/Cargo.toml" <<'EOF'
[package]
name = "member-a"
version = "0.1.0"
edition = "2021"
publish.workspace = true
license = "MIT"
EOF
expect_fail "workspace member overriding license = MIT" 'member-a/Cargo.toml: [package].license must resolve to "Apache-2.0" (found '\''MIT'\'')' "$r_ws"

# Restore member, break workspace.package publish = true
cat >"$r_ws/repros/ws-case/crates/member-a/Cargo.toml" <<'EOF'
[package]
name = "member-a"
version = "0.1.0"
edition = "2021"
publish.workspace = true
license.workspace = true
EOF
replace_in_file "$r_ws/repros/ws-case/Cargo.toml" 'publish = false' 'publish = true'
expect_fail "workspace.package publish = true inherited by member" "member-a/Cargo.toml: [package].publish must resolve to false (found True)" "$r_ws"
replace_in_file "$r_ws/repros/ws-case/Cargo.toml" 'publish = true' 'publish = false'

# Workspace member unformatted code fails
printf '// SPDX-License-Identifier: Apache-2.0\npub fn add(a:i32,b:i32)->i32{a+b}\n' >"$r_ws/repros/ws-case/crates/member-a/src/lib.rs"
expect_fail "workspace member with unformatted src/lib.rs" "member-a/src/lib.rs" "$r_ws"

# Workspace member clippy warning fails
cat >"$r_ws/repros/ws-case/crates/member-a/src/lib.rs" <<'EOF'
// SPDX-License-Identifier: Apache-2.0

pub fn add(a: i32, b: i32) -> i32 {
    if a == a {
        a + b
    } else {
        0
    }
}
EOF
expect_fail "workspace member with clippy warning" "clippy::eq_op" "$r_ws"

echo "=== 7. Missing README, missing root Cargo.lock, and --metadata-only checks ==="
r_meta="$TMP_ROOT/repo-meta"
init_temp_repo "$r_meta"
mkdir -p "$r_meta/repros/meta-case"
write_valid_rust_pkg "$r_meta/repros/meta-case" "meta-case"
gen_lockfile "$r_meta/repros/meta-case"
expect_fail "case missing README.md" "is missing required file: README.md" "$r_meta"

printf '# meta-case\n' >"$r_meta/repros/meta-case/README.md"
rm -f "$r_meta/repros/meta-case/Cargo.lock"
expect_fail "case missing Cargo.lock" "is missing required lockfile: Cargo.lock" "$r_meta"
gen_lockfile "$r_meta/repros/meta-case"

# Unformatted Rust code passes under --metadata-only, while bad metadata still fails
printf '// SPDX-License-Identifier: Apache-2.0\nfn main(){println!("unformatted");}\n' >"$r_meta/repros/meta-case/src/main.rs"
run_check "$r_meta" --metadata-only >/dev/null
pass "--metadata-only skips Cargo checks on valid metadata"
replace_in_file "$r_meta/repros/meta-case/Cargo.toml" 'publish = false' 'publish = true'
expect_fail "--metadata-only still rejects publish = true" "meta-case/Cargo.toml: [package].publish must resolve to false (found True)" "$r_meta" --metadata-only

echo "=== 8. ensure_rust_components local vs. CI behavior ==="
r_shim="$TMP_ROOT/repo-shim"
init_temp_repo "$r_shim"
mkdir -p "$r_shim/repros/shim-case"
printf '# shim-case\n' >"$r_shim/repros/shim-case/README.md"
write_valid_rust_pkg "$r_shim/repros/shim-case" "shim-case"
gen_lockfile "$r_shim/repros/shim-case"

shim_bin="$TMP_ROOT/shim-bin"
shim_log="$TMP_ROOT/rustup.log"
mkdir -p "$shim_bin"
cat >"$shim_bin/cargo" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "fmt" && "${2:-}" == "--version" ]]; then
    exit 1
fi
if [[ "${1:-}" == "clippy" && "${2:-}" == "--version" ]]; then
    exit 0
fi
exit 0
EOF
cat >"$shim_bin/rustup" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$shim_log"
exit 0
EOF
chmod +x "$shim_bin/cargo" "$shim_bin/rustup"

local_err="$TMP_ROOT/shim_local.err"
if env -u CI PATH="$shim_bin:$PATH" REPO_ROOT="$r_shim" "$CHECK_SCRIPT" >"$local_err" 2>&1; then
    cat "$local_err" >&2
    fail "Expected local run with missing rustfmt to fail without mutating toolchain"
fi
if [[ -e "$shim_log" ]]; then
    fail "Local run invoked rustup unexpectedly: $(cat "$shim_log")"
fi
if ! grep -Fq "rustup component add rustfmt" "$local_err"; then
    cat "$local_err" >&2
    fail "Local failure message did not include install command"
fi
pass "Local run fails without mutating toolchain and prints install command"

env CI=true PATH="$shim_bin:$PATH" REPO_ROOT="$r_shim" "$CHECK_SCRIPT" >/dev/null
if [[ ! -f "$shim_log" ]] || ! grep -Fq "component add rustfmt" "$shim_log"; then
    fail "CI=true run did not invoke rustup component add rustfmt"
fi
pass "CI=true run installs missing rustup components"

echo "=== 9. Path-dependency helper crates of standalone roots (Layouts 1a, 1b, cycle) ==="
r_helper="$TMP_ROOT/repo-helper"
init_temp_repo "$r_helper"
mkdir -p "$r_helper/repros/helper-case/src"
printf '# helper-case\n' >"$r_helper/repros/helper-case/README.md"
write_valid_rust_lib "$r_helper/repros/helper-case/helper/subhelper" "subhelper" "" "" 'pub fn sub_val() -> i32 {
    1
}'
write_valid_rust_lib "$r_helper/repros/helper-case/helper" "helper" "" 'subhelper = { path = "subhelper" }' 'pub fn helper_val() -> i32 {
    subhelper::sub_val() + 1
}'
cat >"$r_helper/repros/helper-case/Cargo.toml" <<'EOF'
[package]
name = "helper-case"
version = "0.1.0"
edition = "2021"
publish = false
license = "Apache-2.0"

[dependencies]
helper = { path = "helper" }
EOF
cat >"$r_helper/repros/helper-case/src/main.rs" <<'EOF'
// SPDX-License-Identifier: Apache-2.0

fn main() {
    println!("{}", helper::helper_val());
}

#[cfg(test)]
mod tests {
    #[test]
    fn uses_helper() {
        assert_eq!(helper::helper_val(), 2);
    }
}
EOF
gen_lockfile "$r_helper/repros/helper-case"
# cargo fmt/clippy/test skip non-member path dependencies, so helpers outside any workspace are rejected
expect_fail "non-member path-dependency helper of a standalone root" "helper/Cargo.toml: path-dependency crate (used by Cargo.toml) is not a member of any workspace" "$r_helper"
expect_fail "non-member path-dependency helper rejected in --metadata-only mode" "helper/Cargo.toml: path-dependency crate (used by Cargo.toml) is not a member of any workspace" "$r_helper" --metadata-only
expect_fail "in-directory helper remedy names the enclosing root" "Add a [workspace] table to Cargo.toml so this crate becomes an implicit member" "$r_helper"

# Declaring [workspace] in the root makes in-directory helpers (and their transitive helpers) implicit members
printf '\n[workspace]\n' >>"$r_helper/repros/helper-case/Cargo.toml"
gen_lockfile "$r_helper/repros/helper-case"
run_check "$r_helper" >/dev/null
pass "Root package with [workspace] and nested transitive path-dependency helpers (without helper Cargo.lock) passes"

# Helpers that are implicit members are covered by fmt, clippy, and test
helper_lib="$r_helper/repros/helper-case/helper/src/lib.rs"
cp "$helper_lib" "$TMP_ROOT/helper_lib.rs.orig"
printf '// SPDX-License-Identifier: Apache-2.0\npub fn helper_val()->i32{subhelper::sub_val()+1}\n' >"$helper_lib"
expect_fail "implicit-member helper of a root package with unformatted src/lib.rs" "helper/src/lib.rs" "$r_helper"

cat >"$helper_lib" <<'EOF'
// SPDX-License-Identifier: Apache-2.0

pub fn helper_val() -> i32 {
    if 1 == 1 {
        subhelper::sub_val() + 1
    } else {
        0
    }
}
EOF
expect_fail "implicit-member helper of a root package with clippy warning" "clippy::eq_op" "$r_helper"

cat >"$helper_lib" <<'EOF'
// SPDX-License-Identifier: Apache-2.0

pub fn helper_val() -> i32 {
    subhelper::sub_val() + 1
}

#[cfg(test)]
mod tests {
    #[test]
    fn fails() {
        assert_eq!(1, 2);
    }
}
EOF
expect_fail "implicit-member helper of a root package with failing unit test" "tests::fails ... FAILED" "$r_helper"
cp "$TMP_ROOT/helper_lib.rs.orig" "$helper_lib"

# Path-dependency helpers still enforce publish = false, license = Apache-2.0, and workspace inheritance rules
replace_in_file "$r_helper/repros/helper-case/helper/Cargo.toml" 'publish = false' 'publish = true'
expect_fail "path-dependency helper with publish = true" "helper/Cargo.toml: [package].publish must resolve to false (found True)" "$r_helper"

replace_in_file "$r_helper/repros/helper-case/helper/Cargo.toml" 'publish = true' 'publish = false'
replace_in_file "$r_helper/repros/helper-case/helper/Cargo.toml" 'license = "Apache-2.0"' 'license = "MIT"'
expect_fail "path-dependency helper with license = MIT" 'helper/Cargo.toml: [package].license must resolve to "Apache-2.0" (found '\''MIT'\'')' "$r_helper"

replace_in_file "$r_helper/repros/helper-case/helper/Cargo.toml" 'license = "MIT"' 'license = "Apache-2.0"'
replace_in_file "$r_helper/repros/helper-case/helper/Cargo.toml" 'publish = false' 'publish.workspace = true'
expect_fail "path-dependency helper using publish.workspace = true without [workspace.package]" "helper/Cargo.toml: [package].publish.workspace = true requires [workspace.package] in $r_helper/repros/helper-case/Cargo.toml" "$r_helper"

# Layout 1b: sibling version crates sharing a common path-dependency helper
r_shared="$TMP_ROOT/repo-shared"
init_temp_repo "$r_shared"
mkdir -p "$r_shared/repros/shared-case/v55/src" "$r_shared/repros/shared-case/v56/src"
printf '# shared-case\n' >"$r_shared/repros/shared-case/README.md"
write_valid_rust_lib "$r_shared/repros/shared-case/shared" "shared"
write_valid_rust_pkg "$r_shared/repros/shared-case/v55" "shared-v55" "" 'shared = { path = "../shared" }'
write_valid_rust_pkg "$r_shared/repros/shared-case/v56" "shared-v56" "" 'shared = { path = "../shared" }'
gen_lockfile "$r_shared/repros/shared-case/v55"
gen_lockfile "$r_shared/repros/shared-case/v56"
expect_fail "shared helper outside any workspace" "shared/Cargo.toml: path-dependency crate (used by v55/Cargo.toml, v56/Cargo.toml) is not a member of any workspace" "$r_shared"
expect_fail "shared helper remedy only suggests its own workspace" "Because it is outside every root crate's directory, give this crate its own [workspace] table and Cargo.lock" "$r_shared"
if grep -Fq "Add a [workspace] table" "$TMP_ROOT/last_err.log"; then
    cat "$TMP_ROOT/last_err.log" >&2
    fail "Shared helper remedy must not suggest adding [workspace] to a depending root"
fi
pass "Shared helper remedy omits the in-directory [workspace] suggestion"

# Following the in-directory remedy on one sibling does not adopt ../shared, so the same remedy is repeated
cp "$r_shared/repros/shared-case/v55/Cargo.toml" "$TMP_ROOT/v55_Cargo.toml.orig"
cp "$r_shared/repros/shared-case/v55/Cargo.lock" "$TMP_ROOT/v55_Cargo.lock.orig"
printf '\n[workspace]\n' >>"$r_shared/repros/shared-case/v55/Cargo.toml"
gen_lockfile "$r_shared/repros/shared-case/v55"
expect_fail "shared helper of a sibling that has [workspace]" "Because it is outside every root crate's directory, give this crate its own [workspace] table and Cargo.lock" "$r_shared"
cp "$TMP_ROOT/v55_Cargo.toml.orig" "$r_shared/repros/shared-case/v55/Cargo.toml"
cp "$TMP_ROOT/v55_Cargo.lock.orig" "$r_shared/repros/shared-case/v55/Cargo.lock"

# A helper shared across roots cannot be a member of both, so it becomes its own workspace root with a Cargo.lock
printf '\n[workspace]\n' >>"$r_shared/repros/shared-case/shared/Cargo.toml"
expect_fail "shared helper with [workspace] but no Cargo.lock" "missing required lockfile: shared/Cargo.lock" "$r_shared"
gen_lockfile "$r_shared/repros/shared-case/shared"
run_check "$r_shared" >/dev/null
pass "Sibling standalone crates sharing a helper that is its own workspace root pass"

printf '// SPDX-License-Identifier: Apache-2.0\npub fn helper_val()->i32{42}\n' >"$r_shared/repros/shared-case/shared/src/lib.rs"
expect_fail "shared helper workspace root with unformatted src/lib.rs" "shared/src/lib.rs" "$r_shared"
write_valid_rust_lib "$r_shared/repros/shared-case/shared" "shared" $'\n[workspace]'

# Standalone roots cannot inherit workspace metadata
replace_in_file "$r_shared/repros/shared-case/v55/Cargo.toml" 'publish = false' 'publish.workspace = true'
expect_fail "standalone root using publish.workspace = true" "v55/Cargo.toml: [package].publish.workspace = true used without an owning [workspace]" "$r_shared"
replace_in_file "$r_shared/repros/shared-case/v55/Cargo.toml" 'publish.workspace = true' 'publish = false'

replace_in_file "$r_shared/repros/shared-case/shared/Cargo.toml" 'publish = false' 'publish = true'
expect_fail "shared path-dependency helper with publish = true" "shared/Cargo.toml: [package].publish must resolve to false (found True)" "$r_shared"

# Layout 1c: a helper inside one root's directory that a sibling root also uses.
# Adding [workspace] to the enclosing root adopts it even though a sibling depends on it too.
r_xroot="$TMP_ROOT/repo-xroot"
init_temp_repo "$r_xroot"
mkdir -p "$r_xroot/repros/xroot-case"
printf '# xroot-case\n' >"$r_xroot/repros/xroot-case/README.md"
write_valid_rust_lib "$r_xroot/repros/xroot-case/a/helper" "helper"
write_valid_rust_pkg "$r_xroot/repros/xroot-case/a" "xroot-a" "" 'helper = { path = "helper" }'
write_valid_rust_pkg "$r_xroot/repros/xroot-case/b" "xroot-b" "" 'helper = { path = "../a/helper" }'
gen_lockfile "$r_xroot/repros/xroot-case/a"
gen_lockfile "$r_xroot/repros/xroot-case/b"
expect_fail "helper in one root's directory also used by a sibling" "a/helper/Cargo.toml: path-dependency crate (used by a/Cargo.toml, b/Cargo.toml) is not a member of any workspace" "$r_xroot" --metadata-only
expect_fail "cross-root helper remedy names the enclosing root" "Add a [workspace] table to a/Cargo.toml so this crate becomes an implicit member" "$r_xroot" --metadata-only
if grep -Fq "Because" "$TMP_ROOT/last_err.log"; then
    cat "$TMP_ROOT/last_err.log" >&2
    fail "Cross-root helper remedy must not claim the enclosing root's [workspace] cannot adopt it"
fi
pass "Cross-root helper remedy omits the own-workspace-only reason"

# Following that remedy makes the helper an implicit member of a/ and the case passes
printf '\n[workspace]\n' >>"$r_xroot/repros/xroot-case/a/Cargo.toml"
gen_lockfile "$r_xroot/repros/xroot-case/a"
gen_lockfile "$r_xroot/repros/xroot-case/b"
run_check "$r_xroot" >/dev/null
pass "Helper adopted by its enclosing root's [workspace] and also used by a sibling root passes"

# A helper in a root's directory that only a sibling uses is not adopted by that root's [workspace]
replace_in_file "$r_xroot/repros/xroot-case/a/Cargo.toml" 'helper = { path = "helper" }' ''
replace_in_file "$r_xroot/repros/xroot-case/a/Cargo.toml" $'\n[workspace]\n' ''
expect_fail "helper in a root's directory used only by a sibling" "a/helper/Cargo.toml: path-dependency crate (used by b/Cargo.toml) is not a member of any workspace" "$r_xroot" --metadata-only
expect_fail "sibling-only helper remedy only suggests its own workspace" "Because a/Cargo.toml does not reach it through path dependencies in its directory, a [workspace] table there would not adopt it, so give this crate its own [workspace] table and Cargo.lock" "$r_xroot" --metadata-only

# Dev-dependency cycle between root package with [workspace] (with Cargo.lock) and helper (without Cargo.lock)
r_cycle="$TMP_ROOT/repo-cycle"
init_temp_repo "$r_cycle"
mkdir -p "$r_cycle/repros/cycle-case/src" "$r_cycle/repros/cycle-case/helper/src"
printf '# cycle-case\n' >"$r_cycle/repros/cycle-case/README.md"
cat >"$r_cycle/repros/cycle-case/Cargo.toml" <<'EOF'
[package]
name = "cycle-case"
version = "0.1.0"
edition = "2021"
publish = false
license = "Apache-2.0"

[dependencies]
helper = { path = "helper" }

[workspace]
EOF
cat >"$r_cycle/repros/cycle-case/src/lib.rs" <<'EOF'
// SPDX-License-Identifier: Apache-2.0

pub fn root_val() -> i32 {
    7
}
EOF
cat >"$r_cycle/repros/cycle-case/src/main.rs" <<'EOF'
// SPDX-License-Identifier: Apache-2.0

fn main() {
    println!("{}", helper::helper_val());
}

#[cfg(test)]
mod tests {
    #[test]
    fn works() {
        assert_eq!(helper::helper_val(), 42);
    }
}
EOF
cat >"$r_cycle/repros/cycle-case/helper/Cargo.toml" <<'EOF'
[package]
name = "helper"
version = "0.1.0"
edition = "2021"
publish = false
license = "Apache-2.0"

[dev-dependencies]
cycle-case = { path = ".." }
EOF
cat >"$r_cycle/repros/cycle-case/helper/src/lib.rs" <<'EOF'
// SPDX-License-Identifier: Apache-2.0

pub fn helper_val() -> i32 {
    42
}

#[cfg(test)]
mod tests {
    #[test]
    fn uses_root() {
        assert_eq!(cycle_case::root_val(), 7);
    }
}
EOF
gen_lockfile "$r_cycle/repros/cycle-case"
run_check "$r_cycle" --metadata-only >/dev/null
run_check "$r_cycle" >/dev/null
pass "Dev-dependency cycle between root package and helper passes"

echo "=== 10. Workspace implicit path-dependency members and excluded path deps (Layout 2) ==="
r_wsimplicit="$TMP_ROOT/repo-ws-implicit"
init_temp_repo "$r_wsimplicit"
mkdir -p "$r_wsimplicit/repros/ws-implicit/crates/a/src"
printf '# ws-implicit\n' >"$r_wsimplicit/repros/ws-implicit/README.md"
cat >"$r_wsimplicit/repros/ws-implicit/Cargo.toml" <<'EOF'
[workspace]
resolver = "2"
members = ["crates/a"]
exclude = ["ext-helper"]

[workspace.package]
license = "Apache-2.0"
publish = false

[workspace.dependencies]
ws-helper = { path = "ws-helper" }
EOF
cat >"$r_wsimplicit/repros/ws-implicit/crates/a/Cargo.toml" <<'EOF'
[package]
name = "a"
version = "0.1.0"
edition = "2021"
publish.workspace = true
license.workspace = true

[dependencies]
helper = { path = "../../helper" }
ws-helper = { workspace = true }
ext-helper = { path = "../../ext-helper" }
EOF
cat >"$r_wsimplicit/repros/ws-implicit/crates/a/src/lib.rs" <<'EOF'
// SPDX-License-Identifier: Apache-2.0

pub fn total() -> i32 {
    helper::helper_val() + ws_helper::ws_val() + ext_helper::ext_val()
}

#[cfg(test)]
mod tests {
    #[test]
    fn computes_total() {
        assert_eq!(super::total(), 13);
    }
}
EOF

# Implicit member via direct path dep -> transitive implicit member
mkdir -p "$r_wsimplicit/repros/ws-implicit/helper/src" "$r_wsimplicit/repros/ws-implicit/transitive/src"
cat >"$r_wsimplicit/repros/ws-implicit/helper/Cargo.toml" <<'EOF'
[package]
name = "helper"
version = "0.1.0"
edition = "2021"
publish.workspace = true
license.workspace = true

[dependencies]
transitive = { path = "../transitive" }
EOF
cat >"$r_wsimplicit/repros/ws-implicit/helper/src/lib.rs" <<'EOF'
// SPDX-License-Identifier: Apache-2.0

pub fn helper_val() -> i32 {
    transitive::t_val() + 1
}

#[cfg(test)]
mod tests {
    #[test]
    fn helper_ok() {
        assert_eq!(super::helper_val(), 4);
    }
}
EOF
cat >"$r_wsimplicit/repros/ws-implicit/transitive/Cargo.toml" <<'EOF'
[package]
name = "transitive"
version = "0.1.0"
edition = "2021"
publish.workspace = true
license.workspace = true
EOF
cat >"$r_wsimplicit/repros/ws-implicit/transitive/src/lib.rs" <<'EOF'
// SPDX-License-Identifier: Apache-2.0

pub fn t_val() -> i32 {
    3
}
EOF

# Implicit member via [workspace.dependencies] path + workspace = true
mkdir -p "$r_wsimplicit/repros/ws-implicit/ws-helper/src"
cat >"$r_wsimplicit/repros/ws-implicit/ws-helper/Cargo.toml" <<'EOF'
[package]
name = "ws-helper"
version = "0.1.0"
edition = "2021"
publish.workspace = true
license.workspace = true
EOF
cat >"$r_wsimplicit/repros/ws-implicit/ws-helper/src/lib.rs" <<'EOF'
// SPDX-License-Identifier: Apache-2.0

pub fn ws_val() -> i32 {
    4
}
EOF

# Excluded path dependency: not a workspace member, so it is rejected until it becomes its own workspace root
write_valid_rust_lib "$r_wsimplicit/repros/ws-implicit/ext-helper" "ext-helper" "" "" 'pub fn ext_val() -> i32 {
    5
}'

gen_lockfile "$r_wsimplicit/repros/ws-implicit"
expect_fail "excluded path dependency outside any workspace" "ext-helper/Cargo.toml: path-dependency crate (used by crates/a/Cargo.toml) is not a member of any workspace" "$r_wsimplicit"
expect_fail "excluded helper remedy points at the workspace exclude list" "Remove it from [workspace].exclude in Cargo.toml, or give this crate its own [workspace] table and Cargo.lock" "$r_wsimplicit"

write_valid_rust_lib "$r_wsimplicit/repros/ws-implicit/ext-helper" "ext-helper" $'\n[workspace]' "" 'pub fn ext_val() -> i32 {
    5
}'
gen_lockfile "$r_wsimplicit/repros/ws-implicit/ext-helper"
run_check "$r_wsimplicit" --metadata-only >/dev/null
run_check "$r_wsimplicit" >/dev/null
pass "Workspace implicit members (direct, transitive, workspace.dependencies) and excluded path-dep workspace root pass"

# Excluded path dep cannot inherit the outer workspace's metadata
replace_in_file "$r_wsimplicit/repros/ws-implicit/ext-helper/Cargo.toml" 'publish = false' 'publish.workspace = true'
expect_fail "excluded path-dependency attempting workspace inheritance" "ext-helper/Cargo.toml: [package].publish.workspace = true requires [workspace.package] in $r_wsimplicit/repros/ws-implicit/ext-helper/Cargo.toml" "$r_wsimplicit"
replace_in_file "$r_wsimplicit/repros/ws-implicit/ext-helper/Cargo.toml" 'publish.workspace = true' 'publish = false'

# Implicit workspace member rejects publish = true
replace_in_file "$r_wsimplicit/repros/ws-implicit/helper/Cargo.toml" 'publish.workspace = true' 'publish = true'
expect_fail "implicit workspace member with publish = true" "helper/Cargo.toml: [package].publish must resolve to false (found True)" "$r_wsimplicit"
replace_in_file "$r_wsimplicit/repros/ws-implicit/helper/Cargo.toml" 'publish = true' 'publish.workspace = true'

# Implicit workspace member is covered by fmt, clippy, and test
printf '// SPDX-License-Identifier: Apache-2.0\npub fn helper_val()->i32{transitive::t_val()+1}\n' >"$r_wsimplicit/repros/ws-implicit/helper/src/lib.rs"
expect_fail "implicit workspace member with unformatted src/lib.rs" "helper/src/lib.rs" "$r_wsimplicit"

cat >"$r_wsimplicit/repros/ws-implicit/helper/src/lib.rs" <<'EOF'
// SPDX-License-Identifier: Apache-2.0

pub fn helper_val() -> i32 {
    if 1 == 1 {
        transitive::t_val() + 1
    } else {
        0
    }
}
EOF
expect_fail "implicit workspace member with clippy warning" "clippy::eq_op" "$r_wsimplicit"

cat >"$r_wsimplicit/repros/ws-implicit/helper/src/lib.rs" <<'EOF'
// SPDX-License-Identifier: Apache-2.0

pub fn helper_val() -> i32 {
    transitive::t_val() + 1
}

#[cfg(test)]
mod tests {
    #[test]
    fn fails() {
        assert_eq!(1, 2);
    }
}
EOF
expect_fail "implicit workspace member with failing unit test" "FAILED" "$r_wsimplicit"

pass "All check-cases.sh self-tests passed"
