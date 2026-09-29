# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

set shell := ["bash", "-euo", "pipefail", "-c"]

gerbil_test_runtime_options := "-:max-heap=1G,debug=q"

default:
    @just --list

build:
    gerbil build

test-file path:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f "{{ path }}"
    output="$(GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout "${ASCENT_GXTEST_TIMEOUT:-120s}" gerbil {{ gerbil_test_runtime_options }} env gxtest "{{ path }}" 2>&1)" || { status=$?; printf '%s\n' "$output"; exit "$status"; }
    printf '%s\n' "$output"
    if grep -E 'ERROR (CHECK|CASE|HARNESS)|Heap overflow|Stack overflow' <<< "$output" >/dev/null; then exit 1; fi
    grep -F 'MODULE-OK {{ path }}' <<< "$output" >/dev/null
    grep -F 'HARNESS-OK' <<< "$output" >/dev/null
    grep -x 'OK' <<< "$output" >/dev/null

test:
    #!/usr/bin/env bash
    set -euo pipefail
    for file in t/qualification/*-test.ss; do
        just test-file "$file"
    done

# ASCENT owns its 1000-sample SS receipts using ASP's benchmark profile.
performance:
    #!/usr/bin/env bash
    set -euo pipefail
    export GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}"
    run_case() {
        local name="$1"
        shift
        printf '[ascent-ss] START %s (1000 samples)\n' "$name"
        local started=$SECONDS
        if "$@"; then
            printf '[ascent-ss] PASS %s (%ss)\n' "$name" "$((SECONDS - started))"
        else
            local status=$?
            printf '[ascent-ss] FAIL %s (%ss, exit=%s)\n' "$name" "$((SECONDS - started))" "$status" >&2
            return "$status"
        fi
    }
    run_scenario() {
        local name="$1"
        local path="t/scenarios/performance/$name/scenario.ss"
        run_case "$name" env ASCENT_SS_SCENARIO="$path" ASCENT_GXTEST_TIMEOUT=180s just test-file t/performance/ascent-scenario-performance-test.ss
    }
    run_scenario ascent-byods-trrel
    run_scenario ascent-session-update
    run_scenario ascent-ten-thousand-appends
    run_scenario ascent-nonpositive-session-update
    run_scenario ascent-rule-clauses
    run_scenario ascent-var-points-to
    run_scenario ascent-upstream-examples
    run_scenario ascent-product-session
    run_scenario ascent-mutual-recursive-heads
    run_scenario ascent-derived-aggregate
    run_scenario ascent-indexed-joins
    run_scenario ascent-byods-eqrel
    run_case ascent-binary-program just test-file t/performance/ascent-binary-program-performance-test.ss
    run_scenario ascent-reachability-closure
    run_scenario ascent-table-expression
    run_scenario ascent-table-expression-membership
    run_case ascent-shortest-candidates just test-file t/performance/ascent-shortest-candidates-performance-test.ss
ascent-pairs:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-binary-program-pairs.ss

ascent-guarded:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-binary-program-guarded.ss

ascent-candidates:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-closure-candidates-output.ss

timeout-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-timeout-output.ss

rule-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-rule-program-output.ss

aggregate-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-aggregate-program-output.ss

derived-aggregate-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-derived-aggregate-program-output.ss

syntax-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-syntax-program-output.ss

var-points-to-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-var-points-to-output.ss

upstream-example-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-upstream-examples-output.ss

lattice-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-lattice-program-output.ss

lattice-set-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-lattice-set-output.ss

integrated-corpus-rows:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-integrated-corpus-output.ss

mutual-corpus-rows:
    @timeout 120s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-mutual-program-output.ss

lattice-session-corpus-rows:
    @timeout 120s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-lattice-session-output.ss

lattice-negation-rows:
    @timeout 120s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-lattice-negation-output.ss

invalid-program-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-invalid-program-output.ss

product-session-rows:
    @timeout 120s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-product-session-output.ss

index-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-index-program-output.ss

index-rows-alist:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-index-program-output.ss alist

index-composite-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-index-program-output.ss composite

index-composite-rows-alist:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-index-program-output.ss composite alist

eqrel-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-eqrel-program-output.ss

eqrel-default-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-eqrel-program-output.ss default

trrel-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-eqrel-program-output.ss trrel

trrel-uf-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-eqrel-program-output.ss trrel-uf

byods-query-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-byods-query-output.ss

typed-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-typed-program-output.ss

module-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-module-program-output.ss

mutual-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-mutual-program-output.ss

oracle:
    gerbil env cargo test --locked --manifest-path rust/ascent-oracle/Cargo.toml

timed-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-timing-test.ss
