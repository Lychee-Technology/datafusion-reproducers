#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Plan the same workloads on DataFusion 55.0.0 and 56.0.0 and write one CSV.
# Each configuration is built (release, --locked) into its own target
# directory before any measurement. Every run is bounded by --timeout-secs;
# a timeout is recorded as status `timeout`, never as a time.
#
# Usage: scripts/verify-versions.sh [OUTPUT_CSV]
#   OUTPUT_CSV is relative to the caller's working directory;
#   default output: results/verification.csv in the case directory

set -euo pipefail

case_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-$case_dir/results/verification.csv}"
mkdir -p "$(dirname "$out")"
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
cd "$case_dir"

declare -A bins=(
    [df55]="target/df55/release/deep-expression-planning"
    [df56]="target/df56/release/deep-expression-planning"
)

for feature in df55 df56; do
    echo "building $feature" >&2
    if ! cargo build --release --locked --quiet \
        --no-default-features --features "$feature" \
        --target-dir "target/$feature"; then
        echo "error: build failed for $feature; no measurements taken" >&2
        exit 1
    fi
done

header_written=false
run() {
    local feature="$1"
    shift
    echo "$feature $*" >&2
    local rows status=0
    rows="$("${bins[$feature]}" --format csv "$@")" || status=$?
    # 124 is a recorded timeout; anything else non-zero is a failure.
    if [[ $status -ne 0 && $status -ne 124 ]]; then
        echo "error: $feature $* exited with $status" >&2
        exit 1
    fi
    if [[ "$header_written" == false ]]; then
        printf '%s\n' "${rows%%$'\n'*}" >"$out"
        header_written=true
    fi
    # Everything after the header line; no pipe, so pipefail cannot trip.
    if [[ "$rows" == *$'\n'* ]]; then
        printf '%s\n' "${rows#*$'\n'}" >>"$out"
    fi
}

for feature in df55 df56; do
    # The reported workload: sorted and unsorted distinct over a growing depth.
    for input in sorted unsorted; do
        for depth in 25 50 100 200; do
            run "$feature" --depth "$depth" --input "$input" \
                --iterations 3 --warmup 1 --timeout-secs 300
        done
    done
    # Depth 500 reportedly times out on 56: one bounded run.
    run "$feature" --depth 500 --iterations 1 --warmup 0 --timeout-secs 120

    # Controls at depth 100.
    for mode in group-by order-by project; do
        run "$feature" --depth 100 --mode "$mode" --iterations 3 --warmup 1 --timeout-secs 120
    done
    run "$feature" --depth 100 --key-only --iterations 3 --warmup 1 --timeout-secs 120
    run "$feature" --depth 25 --projections 4 --retain --iterations 3 --warmup 1 --timeout-secs 120
    for partitions in 1 8; do
        run "$feature" --depth 100 --partitions "$partitions" \
            --iterations 3 --warmup 1 --timeout-secs 120
    done
done

echo "wrote $out" >&2
