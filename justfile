# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

set shell := ["bash", "-euo", "pipefail", "-c"]

gerbil_test_runtime_options := "-:max-heap=1G,debug=q"

default:
    @just --list

build:
    GERBIL_BUILD_CORES="${GERBIL_BUILD_CORES:-$(getconf NPROCESSORS_ONLN)}" gerbil build

check-policy:
    ASP_GERBIL_SCHEME_POLICY=1 GERBIL_BUILD_CORES="${GERBIL_BUILD_CORES:-$(getconf NPROCESSORS_ONLN)}" gerbil build

test-file path:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f "{{ path }}"
    output_file="$(mktemp)"
    trap 'rm -f "$output_file"' EXIT
    GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout "${ASCENT_GXTEST_TIMEOUT:-120s}" gerbil {{ gerbil_test_runtime_options }} test -v 5 "{{ path }}" 2>&1 | tee "$output_file"
    if grep -E 'ERROR (CHECK|CASE|HARNESS)|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi
    grep -F 'MODULE-OK {{ path }}' "$output_file" >/dev/null
    grep -F 'HARNESS-OK' "$output_file" >/dev/null
    grep -x 'OK' "$output_file" >/dev/null

test:
    #!/usr/bin/env bash
    set -euo pipefail
    files=(t/qualification/*-test.ss)
    qualified=()
    output_file="$(mktemp)"
    trap 'rm -f "$output_file"' EXIT
    export GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}"
    # Reset Gerbil between bounded batches. The exhaustive operator modules
    # run alone so each has its own timeout and completion receipts.
    run_batch() {
        local batch=("$@")
        : > "$output_file"
        timeout "${ASCENT_GXTEST_TIMEOUT:-120s}" gerbil {{ gerbil_test_runtime_options }} test -v 5 "${batch[@]}" 2>&1 | tee "$output_file"
        if grep -E 'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi
        local batch_file
        for batch_file in "${batch[@]}"; do
            grep -Fx "MODULE-OK $batch_file" "$output_file" >/dev/null
        done
        grep -F 'HARNESS-OK' "$output_file" >/dev/null
        grep -x 'OK' "$output_file" >/dev/null
        qualified+=("${batch[@]}")
    }
    batch=()
    for file in "${files[@]}"; do
        if [[ "$file" == t/qualification/ascent-reasoning-library-test.ss ||
              "$file" == t/qualification/scheme-library-contract-test.ss ||
              "$file" == t/qualification/scheme-operator-test.ss ||
              "$file" == t/qualification/scheme-operator-retained-test.ss ]]; then
            if ((${#batch[@]})); then run_batch "${batch[@]}"; batch=(); fi
            run_batch "$file"
        else
            batch+=("$file")
            if ((${#batch[@]} == 2)); then run_batch "${batch[@]}"; batch=(); fi
        fi
    done
    if ((${#batch[@]})); then run_batch "${batch[@]}"; fi
    # A successful shell exit must mean every discovered test ran exactly once.
    test "${#qualified[@]}" -eq "${#files[@]}"
    for ((i=0; i<${#files[@]}; i++)); do
        test "${qualified[i]}" = "${files[i]}"
    done

test-quick:
    #!/usr/bin/env bash
    set -euo pipefail
    export GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}"
    output_file="$(mktemp)"
    trap 'rm -f "$output_file"' EXIT
    timeout "${ASCENT_GXTEST_TIMEOUT:-120s}" gerbil {{ gerbil_test_runtime_options }} test -v 3 \
        t/qualification/ascent-finite-evidence-test.ss \
        t/qualification/ascent-positive-nonmembership-test.ss \
        t/qualification/ascent-positive-provenance-test.ss \
        t/qualification/ascent-reasoning-library-test.ss \
        t/qualification/ascent-stratified-proof-test.ss 2>&1 | tee "$output_file"
    if grep -E 'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi
    for path in t/qualification/ascent-finite-evidence-test.ss \
                t/qualification/ascent-positive-nonmembership-test.ss \
                t/qualification/ascent-positive-provenance-test.ss \
                t/qualification/ascent-reasoning-library-test.ss \
                t/qualification/ascent-stratified-proof-test.ss; do
        grep -Fx "MODULE-OK $path" "$output_file" >/dev/null
    done
    grep -F 'HARNESS-OK' "$output_file" >/dev/null
    grep -x 'OK' "$output_file" >/dev/null

small-graph-benchmark:
    GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s gerbil {{ gerbil_test_runtime_options }} env gxi t/performance/small-graph-benchmark.ss

# Matched row-copy boundary costs. The probe checks equal rows and isolation
# after every sample; it does not time a complete retained-session solve.
admission-copy-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    output_file="$(mktemp)"
    trap 'rm -f "$output_file"' EXIT
    export GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}"
    printf '[admission-copy] START three matched row-copy cases\n'
    timeout 180s gxi {{ gerbil_test_runtime_options }} t/performance/scheme-admission-copy-benchmark.ss 2>&1 | tee "$output_file"
    test "$(grep -c '^CASE ' "$output_file")" -eq 3
    test "$(grep -c '^WARM ' "$output_file")" -eq 6
    test "$(grep -c '^SAMPLE ' "$output_file")" -eq 48
    grep -x 'OK' "$output_file" >/dev/null
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi

# Abstract theorem and bounded local receipt-lifecycle safety model.
# Supply TLC_BIN when tlc is not on PATH; this gate does not build Scheme.
check-nonmembership-formal:
    #!/usr/bin/env bash
    set -euo pipefail
    lean packages/proofs/lean/PositiveNonmembership.lean
    model_dir="$(mktemp -d)"
    trap 'rm -rf "$model_dir"' EXIT
    "${TLC_BIN:-tlc}" -config packages/proofs/tla/PositiveNonmembershipSession.cfg -metadir "$model_dir" packages/proofs/tla/PositiveNonmembershipSession.tla

# Matched finite-operator research probe; every sample checks independent
# closure before reporting cost. This is separate from the SS suite.
operator-change-probe:
    #!/usr/bin/env bash
    set -euo pipefail
    output_file="$(mktemp)"
    trap 'rm -f "$output_file"' EXIT
    export GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}"
    timeout 90s gerbil {{ gerbil_test_runtime_options }} env gxi t/performance/scheme-operator-change-probe.ss 2>&1 | tee "$output_file"
    test "$(grep -c '^CASE ' "$output_file")" -eq 6
    test "$(grep -c '^SAMPLE ' "$output_file")" -eq 60
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi

# Exact-set gate and matched exploratory timing for native retained updates.
operator-retained-probe:
    #!/usr/bin/env bash
    set -euo pipefail
    output_file="$(mktemp)"
    trap 'rm -f "$output_file"' EXIT
    export GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}"
    timeout 120s gerbil {{ gerbil_test_runtime_options }} env gxi t/performance/scheme-operator-retained-probe.ss 2>&1 | tee "$output_file"
    test "$(grep -c '^CASE ' "$output_file")" -eq 6
    test "$(grep -c '^SAMPLE ' "$output_file")" -eq 72
    test "$(grep -c '^SEQUENCE ' "$output_file")" -eq 1
    test "$(grep -c '^LIFECYCLE SAMPLE ' "$output_file")" -eq 8
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi

# ASCENT owns its 1000-sample SS receipts using ASP's benchmark profile.
performance:
    #!/usr/bin/env bash
    set -euo pipefail
    export GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}"
    # The ASP runner reports after its 1000 timed attempts; printing from a
    # timed thunk would change the samples. Each native test process has a
    # bounded total timeout and the scenario wrapper prints progress.
    run_case() {
        local name="$1"
        shift
        printf '[ascent-ss] START %s (1000 samples)\n' "$name"
        local started=$SECONDS
        (while sleep 10; do printf '[ascent-ss] RUNNING %s (%ss)\n' "$name" "$((SECONDS - started))"; done) &
        local heartbeat=$!
        if "$@"; then
            kill "$heartbeat" 2>/dev/null || true
            wait "$heartbeat" 2>/dev/null || true
            printf '[ascent-ss] PASS %s (%ss)\n' "$name" "$((SECONDS - started))"
        else
            local status=$?
            kill "$heartbeat" 2>/dev/null || true
            wait "$heartbeat" 2>/dev/null || true
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

timeout-strata-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-timeout-strata-output.ss

byods-lattice-rows:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-byods-lattice-output.ss

byods-lattice-session-rows:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-byods-lattice-session-output.ss

byods-lattice-scale-rows:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-byods-lattice-scale-output.ss

rule-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-rule-program-output.ss

aggregate-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-aggregate-program-output.ss

derived-aggregate-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-derived-aggregate-program-output.ss

syntax-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-syntax-program-output.ss

scc-summary:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-scc-summary-test.ss

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

index-lattice-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-index-program-output.ss lattice

index-lattice-rows-alist:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-index-program-output.ss lattice alist

eqrel-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-eqrel-program-output.ss

eqrel-scale-rows:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-eqrel-program-output.ss scale

eqrel-default-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-eqrel-program-output.ss default

trrel-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-eqrel-program-output.ss trrel

trrel-scale-rows:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-eqrel-program-output.ss trrel scale

trrel-uf-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-eqrel-program-output.ss trrel-uf

trrel-uf-scale-rows:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-eqrel-program-output.ss trrel-uf scale

byods-query-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-byods-query-output.ss

typed-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-typed-program-output.ss

module-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-module-program-output.ss

mutual-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-mutual-program-output.ss

scc-order-rows:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-scc-order-output.ss

arity-repetition-rows:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-arity-repetition-output.ss

clause-composition-rows:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-clause-composition-output.ss

clause-scale-rows:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-clause-scale-output.ss

divisibility-lattice-rows:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-divisibility-lattice-output.ss

multi-source-session-rows:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-multi-source-session-output.ss

byods-session-rows:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-byods-session-output.ss

grouped-eqrel-session-rows:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-grouped-eqrel-session-output.ss

oracle:
    #!/usr/bin/env bash
    set -euo pipefail
    export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
    if [[ "$(uname -s)" == Darwin ]]; then
        export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
        export CC=/usr/bin/clang
        export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C linker=/usr/bin/clang -C link-arg=-isysroot -C link-arg=$SDKROOT"
    fi
    gerbil env env PATH="$PATH" cargo test --locked --manifest-path rust/ascent-oracle/Cargo.toml

timed-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-timing-test.ss
