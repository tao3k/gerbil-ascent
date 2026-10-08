#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
set -euo pipefail
cores="${GERBIL_BUILD_CORES:-1}"
[[ "$cores" =~ ^[1-9][0-9]*$ ]] || { echo 'invalid GERBIL_BUILD_CORES' >&2; exit 1; }
# Bound simultaneous Scheme heaps independently from compiler thread capacity.
(( cores <= 4 )) || cores=4
modules=(t/qualification/*-test.ss)
(( ${#modules[@]} > 0 ))
scratch="$(mktemp -d .cache/ascent/tmp/source-tests.XXXXXX)"
pids=()
cleanup() {
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
    for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
    rm -rf "$scratch"
}
trap cleanup EXIT
trap 'exit 124' TERM INT
for ((worker=0; worker<cores; worker++)); do
    selected=()
    for ((index=worker; index<${#modules[@]}; index+=cores)); do
        selected+=("${modules[index]}")
    done
    (( ${#selected[@]} > 0 )) || continue
    (
        output="$scratch/$worker.log"
        printf 'SOURCE-WORKER %s modules=%s\n' "$worker" "${#selected[@]}"
        "$@" "${selected[@]}" 2>&1 | tee "$output"
        if grep -E 'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow' "$output" >/dev/null; then exit 1; fi
        awk -f tools/assert-test-cases.awk "$output"
        test "$(grep -c '^MODULE-OK ' "$output")" -eq "${#selected[@]}"
        grep -F 'HARNESS-OK' "$output" >/dev/null
        grep -x 'OK' "$output" >/dev/null
        printf 'SOURCE-WORKER-OK %s modules=%s\n' "$worker" "${#selected[@]}"
    ) &
    pids+=("$!")
done
status=0
for pid in "${pids[@]}"; do
    wait "$pid" || status=$?
done
pids=()
(( status == 0 )) || exit "$status"
printf 'SOURCE-TESTS-OK modules=%s workers=%s\n' "${#modules[@]}" "$cores"
