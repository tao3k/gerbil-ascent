# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

set shell := ["bash", "-euo", "pipefail", "-c"]

gerbil_test_runtime_options := "-:max-heap=1G,debug=q"

default:
    @just --list

build:
    python3 tools/test_execution.py run -- just _build

_build:
    GERBIL_BUILD_CORES="${GERBIL_BUILD_CORES:-$(getconf NPROCESSORS_ONLN)}" gerbil build

check-policy:
    python3 tools/test_execution.py run -- just _check-policy

_check-policy:
    ASP_GERBIL_SCHEME_POLICY=1 GERBIL_BUILD_CORES="${GERBIL_BUILD_CORES:-$(getconf NPROCESSORS_ONLN)}" gerbil build

test-file path:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f "{{ path }}"
    output_file="$(mktemp)"
    trap 'rm -f "$output_file"' EXIT
    started=$SECONDS
    printf '[ascent-test] START %s\n' "{{ path }}"
    GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" python3 tools/test_execution.py run --module "{{ path }}" -- timeout "${ASCENT_GXTEST_TIMEOUT:-120s}" gerbil {{ gerbil_test_runtime_options }} test -v 5 "{{ path }}" 2>&1 | tee "$output_file"
    if grep -E 'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi
    awk -f "{{ justfile_directory() }}/tools/assert-test-cases.awk" "$output_file"
    grep -Fx 'MODULE-OK {{ path }}' "$output_file" >/dev/null
    grep -F 'HARNESS-OK' "$output_file" >/dev/null
    grep -x 'OK' "$output_file" >/dev/null
    printf '[ascent-test] PASS %s (%ss)\n' "{{ path }}" "$((SECONDS - started))"

# Explicitly admitted modules run in separate processes; native Cases stay serial.
test-parallel jobs='auto':
    python3 tools/test_execution.py parallel --jobs "{{ jobs }}"

# Native Cases stay serial; admitted modules use a process pool.
test jobs='auto':
    python3 tools/test_execution.py suite --jobs "{{ jobs }}"

# Retain the original batch runner for comparisons.
test-serial:
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
        printf '[ascent-test] START batch %s\n' "${batch[*]}"
        python3 tools/test_execution.py run -- timeout "${ASCENT_GXTEST_TIMEOUT:-120s}" gerbil {{ gerbil_test_runtime_options }} test -v 5 "${batch[@]}" 2>&1 | tee "$output_file"
        if grep -E 'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi
        awk -f "{{ justfile_directory() }}/tools/assert-test-cases.awk" "$output_file"
        local batch_file
        for batch_file in "${batch[@]}"; do
            grep -Fx "MODULE-OK $batch_file" "$output_file" >/dev/null
        done
        grep -F 'HARNESS-OK' "$output_file" >/dev/null
        grep -x 'OK' "$output_file" >/dev/null
        qualified+=("${batch[@]}")
        printf '[ascent-test] PASS batch %s\n' "${batch[*]}"
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
    python3 tools/test_execution.py run -- just _test-quick

_test-quick:
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
    python3 tools/test_execution.py run -- just _small-graph-benchmark

_small-graph-benchmark:
    GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s gerbil {{ gerbil_test_runtime_options }} env gxi t/performance/small-graph-benchmark.ss

# Matched row-copy boundary costs. The probe checks equal rows and isolation
# after every sample; it does not time a complete retained-session solve.
admission-copy-benchmark:
    python3 tools/test_execution.py run -- just _admission-copy-benchmark

_admission-copy-benchmark:
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
    python3 tools/test_execution.py run -- just _operator-change-probe

_operator-change-probe:
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
    python3 tools/test_execution.py run -- just _operator-retained-probe

_operator-retained-probe:
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

clock-memory-probe:
    ASCENT_GXTEST_TIMEOUT="${ASCENT_GXTEST_TIMEOUT:-100s}" just test-file t/performance/ascent-clock-memory-probe.ss

binding-benchmark:
    python3 tools/test_execution.py run -- just _binding-benchmark

_binding-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export GERBIL_BUILD_CORES="${GERBIL_BUILD_CORES:-$(getconf NPROCESSORS_ONLN)}"
    export ASCENT_BINDING_BENCH_LIB="{{ justfile_directory() }}/.gerbil/binding-benchmark/lib"
    export ASCENT_BINDING_RECEIPT="${ASCENT_BINDING_RECEIPT:-{{ justfile_directory() }}/.gerbil/binding-benchmark/receipt.sexp}"
    mkdir -p "$ASCENT_BINDING_BENCH_LIB"
    shasum -a 256 program/graph.ss program/funs.ss program/objects.ss program/evaluate.ss program/analysis.ss program/planning.ss t/qualification/ascent-binding-reference-fixture.ss t/qualification/ascent-binding-reference-evaluate.ss t/qualification/ascent-index-program-fixture.ss t/performance/binding-benchmark.ss tools/build-binding-benchmark.ss > "$ASCENT_BINDING_RECEIPT.sources"
    started=$SECONDS
    log="$(mktemp)"
    (while sleep 10; do printf '[binding-benchmark] RUNNING (%ss)\n' "$((SECONDS - started))"; done) &
    progress_pid=$!
    trap 'kill "$progress_pid" 2>/dev/null || true; wait "$progress_pid" 2>/dev/null || true; rm -f "$log"' EXIT
    printf '[binding-benchmark] BUILD compiled current/reference engines (%s cores)\n' "$GERBIL_BUILD_CORES"
    timeout 150s gxi {{ gerbil_test_runtime_options }} tools/build-binding-benchmark.ss
    printf '[binding-benchmark] RUN alternating old/new, 1000 samples per case\n'
    GERBIL_LOADPATH="$ASCENT_BINDING_BENCH_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 120s gxi {{ gerbil_test_runtime_options }} t/performance/binding-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 6
    grep -x 'OK' "$log" >/dev/null

strata-benchmark:
    python3 tools/test_execution.py run -- just _strata-benchmark

_strata-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export GERBIL_BUILD_CORES="${GERBIL_BUILD_CORES:-$(getconf NPROCESSORS_ONLN)}"
    export ASCENT_STRATA_BENCH_LIB="{{ justfile_directory() }}/.gerbil/strata-benchmark/lib"
    export ASCENT_STRATA_RECEIPT="${ASCENT_STRATA_RECEIPT:-{{ justfile_directory() }}/.gerbil/strata-benchmark/receipt.sexp}"
    mkdir -p "$ASCENT_STRATA_BENCH_LIB"
    shasum -a 256 program/graph.ss program/funs.ss t/qualification/ascent-strata-fixture.ss t/performance/strata-benchmark.ss tools/build-strata-benchmark.ss > "$ASCENT_STRATA_RECEIPT.sources"
    started=$SECONDS
    log="$(mktemp)"
    (while sleep 10; do printf '[strata-benchmark] RUNNING (%ss)\n' "$((SECONDS - started))"; done) &
    progress_pid=$!
    trap 'kill "$progress_pid" 2>/dev/null || true; wait "$progress_pid" 2>/dev/null || true; rm -f "$log"' EXIT
    printf '[strata-benchmark] BUILD current planning and relaxation oracle\n'
    timeout 60s gxi {{ gerbil_test_runtime_options }} tools/build-strata-benchmark.ss
    printf '[strata-benchmark] RUN alternating old/new, 1000 samples per case\n'
    GERBIL_LOADPATH="$ASCENT_STRATA_BENCH_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 90s gxi {{ gerbil_test_runtime_options }} t/performance/strata-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 4
    grep -x 'OK' "$log" >/dev/null

# Run one unchanged SS fixture through the native qualification harness.
performance-scenario name:
    #!/usr/bin/env bash
    set -euo pipefail
    name="{{ name }}"
    path="t/scenarios/performance/$name/scenario.ss"
    test -f "$path"
    started=$SECONDS
    printf '[ascent-ss] START %s (1000 samples)\n' "$name"
    (while sleep 10; do printf '[ascent-ss] RUNNING %s (%ss)\n' "$name" "$((SECONDS - started))"; done) &
    progress_pid=$!
    trap 'kill "$progress_pid" 2>/dev/null || true; wait "$progress_pid" 2>/dev/null || true' EXIT
    if ASCENT_SS_SCENARIO="$path" ASCENT_GXTEST_TIMEOUT="${ASCENT_GXTEST_TIMEOUT:-120s}" just test-file t/performance/ascent-scenario-performance-test.ss; then
        printf '[ascent-ss] PASS %s (%ss)\n' "$name" "$((SECONDS - started))"
    else
        status=$?
        printf '[ascent-ss] FAIL %s (%ss, exit=%s)\n' "$name" "$((SECONDS - started))" "$status" >&2
        exit "$status"
    fi

# ASCENT owns its 1000-sample SS receipts using ASP's benchmark profile.
performance:
    python3 tools/test_execution.py run -- just _performance

_performance:
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
        ASCENT_GXTEST_TIMEOUT="${ASCENT_GXTEST_TIMEOUT:-180s}" just performance-scenario "$1"
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

size-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .gerbil/size-benchmark
    export ASCENT_SIZE_BENCH_LIB="{{ justfile_directory() }}/.gerbil/size-benchmark/lib"
    export ASCENT_SIZE_RECEIPT="${ASCENT_SIZE_RECEIPT:-{{ justfile_directory() }}/.gerbil/size-benchmark/receipt.sexp}"
    shasum -a 256 program/evaluate.ss t/qualification/ascent-size-reference-evaluate.ss t/performance/size-benchmark.ss tools/build-size-benchmark.ss > "$ASCENT_SIZE_RECEIPT.sources"
    python3 tools/test_execution.py run -- just _size-benchmark

_size-benchmark:
    timeout 90s gxi {{ gerbil_test_runtime_options }} tools/build-size-benchmark.ss
    GERBIL_LOADPATH="$ASCENT_SIZE_BENCH_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 150s gxi {{ gerbil_test_runtime_options }} t/performance/size-benchmark.ss

# Whole-solve comparison against the committed narrow-frontier evaluator.
multi-frontier-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .gerbil/multi-frontier
    export ASCENT_MULTI_FRONTIER_LIB="{{ justfile_directory() }}/.gerbil/multi-frontier/lib"
    export ASCENT_MULTI_FRONTIER_RECEIPT="${ASCENT_MULTI_FRONTIER_RECEIPT:-{{ justfile_directory() }}/.gerbil/multi-frontier/receipt.sexp}"
    shasum -a 256 program/evaluate.ss t/qualification/ascent-multi-frontier-reference-evaluate.ss t/performance/multi-frontier-benchmark.ss tools/build-multi-frontier-benchmark.ss > "$ASCENT_MULTI_FRONTIER_RECEIPT.sources"
    python3 tools/test_execution.py run -- just _multi-frontier-benchmark

_multi-frontier-benchmark:
    timeout 90s gxi {{ gerbil_test_runtime_options }} tools/build-multi-frontier-benchmark.ss
    GERBIL_LOADPATH="$ASCENT_MULTI_FRONTIER_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 150s gxi {{ gerbil_test_runtime_options }} t/performance/multi-frontier-benchmark.ss

set-size-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .gerbil/set-size
    export ASCENT_SET_SIZE_LIB="{{ justfile_directory() }}/.gerbil/set-size/lib"
    export ASCENT_SET_SIZE_RECEIPT="${ASCENT_SET_SIZE_RECEIPT:-{{ justfile_directory() }}/.gerbil/set-size/receipt.sexp}"
    shasum -a 256 program/evaluate.ss t/qualification/ascent-set-size-reference-evaluate.ss t/performance/set-size-benchmark.ss tools/build-set-size-benchmark.ss > "$ASCENT_SET_SIZE_RECEIPT.sources"
    python3 tools/test_execution.py run -- just _set-size-benchmark

_set-size-benchmark:
    timeout 90s gxi {{ gerbil_test_runtime_options }} tools/build-set-size-benchmark.ss
    GERBIL_LOADPATH="$ASCENT_SET_SIZE_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 150s gxi {{ gerbil_test_runtime_options }} t/performance/set-size-benchmark.ss

set-batch-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .gerbil/set-batch
    export ASCENT_SET_BATCH_LIB="{{ justfile_directory() }}/.gerbil/set-batch/lib"
    export ASCENT_SET_BATCH_RECEIPT="${ASCENT_SET_BATCH_RECEIPT:-{{ justfile_directory() }}/.gerbil/set-batch/receipt.sexp}"
    shasum -a 256 table/storage.ss t/qualification/ascent-set-batch-reference.ss t/performance/set-batch-benchmark.ss tools/build-set-batch-benchmark.ss > "$ASCENT_SET_BATCH_RECEIPT.sources"
    python3 tools/test_execution.py run -- just _set-batch-benchmark

_set-batch-benchmark:
    timeout 90s gxi {{ gerbil_test_runtime_options }} tools/build-set-batch-benchmark.ss
    GERBIL_LOADPATH="$ASCENT_SET_BATCH_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 150s gxi {{ gerbil_test_runtime_options }} t/performance/set-batch-benchmark.ss

set-emit-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .gerbil/set-emit
    export ASCENT_SET_EMIT_LIB="{{ justfile_directory() }}/.gerbil/set-emit/lib"
    export ASCENT_SET_EMIT_RECEIPT="${ASCENT_SET_EMIT_RECEIPT:-{{ justfile_directory() }}/.gerbil/set-emit/receipt.sexp}"
    shasum -a 256 program/evaluate.ss t/qualification/ascent-set-emit-reference-evaluate.ss t/performance/set-emit-benchmark.ss tools/build-set-emit-benchmark.ss > "$ASCENT_SET_EMIT_RECEIPT.sources"
    python3 tools/test_execution.py run -- just _set-emit-benchmark

_set-emit-benchmark:
    timeout 90s gxi {{ gerbil_test_runtime_options }} tools/build-set-emit-benchmark.ss
    GERBIL_LOADPATH="$ASCENT_SET_EMIT_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 400s gxi {{ gerbil_test_runtime_options }} t/performance/set-emit-benchmark.ss

set-emit-allocation:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .gerbil/set-emit
    export ASCENT_SET_EMIT_LIB="{{ justfile_directory() }}/.gerbil/set-emit/lib"
    export ASCENT_SET_EMIT_ALLOCATION_RECEIPT="${ASCENT_SET_EMIT_ALLOCATION_RECEIPT:-{{ justfile_directory() }}/.gerbil/set-emit/allocation.sexp}"
    shasum -a 256 program/evaluate.ss t/qualification/ascent-set-emit-reference-evaluate.ss t/performance/set-emit-allocation.ss tools/build-set-emit-benchmark.ss > "$ASCENT_SET_EMIT_ALLOCATION_RECEIPT.sources"
    python3 tools/test_execution.py run -- just _set-emit-allocation

_set-emit-allocation:
    timeout 90s gxi {{ gerbil_test_runtime_options }} tools/build-set-emit-benchmark.ss
    GERBIL_LOADPATH="$ASCENT_SET_EMIT_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 150s gxi {{ gerbil_test_runtime_options }} t/performance/set-emit-allocation.ss

set-source-allocation:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .gerbil/set-source
    export ASCENT_SET_SOURCE_LIB="{{ justfile_directory() }}/.gerbil/set-source/lib"
    export ASCENT_SET_SOURCE_ALLOCATION_RECEIPT="${ASCENT_SET_SOURCE_ALLOCATION_RECEIPT:-{{ justfile_directory() }}/.gerbil/set-source/allocation.sexp}"
    shasum -a 256 program/evaluate.ss program/admission.ss t/qualification/ascent-set-source-reference-evaluate.ss t/performance/set-source-allocation.ss tools/build-set-source-benchmark.ss > "$ASCENT_SET_SOURCE_ALLOCATION_RECEIPT.sources"
    python3 tools/test_execution.py run -- just _set-source-allocation

_set-source-allocation:
    timeout 90s gxi {{ gerbil_test_runtime_options }} tools/build-set-source-benchmark.ss
    GERBIL_LOADPATH="$ASCENT_SET_SOURCE_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 150s gxi {{ gerbil_test_runtime_options }} t/performance/set-source-allocation.ss

# Whole-solve positive rule plans: ordered semantics, allocation and raw timing.
positive-plan-benchmark:
    python3 tools/test_execution.py run -- just _positive-plan-benchmark

_positive-plan-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export ASCENT_POSITIVE_PLAN_LIB="{{ justfile_directory() }}/.gerbil/positive-plan/lib"
    export ASCENT_POSITIVE_PLAN_RECEIPT="${ASCENT_POSITIVE_PLAN_RECEIPT:-{{ justfile_directory() }}/.gerbil/positive-plan/receipt.sexp}"
    mkdir -p .gerbil/positive-plan
    shasum -a 256 program/positive.ss program/evaluate.ss program/analysis.ss t/qualification/ascent-positive-plan-reference-analysis.ss t/qualification/ascent-positive-plan-reference-evaluate.ss t/performance/positive-plan-benchmark.ss tools/build-positive-plan-benchmark.ss > "$ASCENT_POSITIVE_PLAN_RECEIPT.sources"
    timeout 150s gxi {{ gerbil_test_runtime_options }} tools/build-positive-plan-benchmark.ss
    log="$(mktemp)"
    trap 'rm -f "$log"' EXIT
    GERBIL_LOADPATH="$ASCENT_POSITIVE_PLAN_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s gxi {{ gerbil_test_runtime_options }} t/performance/positive-plan-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 7
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    grep -x 'OK' "$log" >/dev/null

workspace-benchmark:
    python3 tools/test_execution.py run -- just _workspace-benchmark

_workspace-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export ASCENT_WORKSPACE_LIB="{{ justfile_directory() }}/.gerbil/execution-workspace/lib"
    export ASCENT_WORKSPACE_RECEIPT="${ASCENT_WORKSPACE_RECEIPT:-{{ justfile_directory() }}/.gerbil/execution-workspace/receipt.sexp}"
    mkdir -p .gerbil/execution-workspace
    shasum -a 256 program/positive.ss program/evaluate.ss program/analysis.ss t/qualification/ascent-workspace-reference-analysis.ss t/qualification/ascent-workspace-reference-positive.ss t/qualification/ascent-workspace-reference-evaluate.ss t/performance/workspace-benchmark.ss tools/build-workspace-benchmark.ss > "$ASCENT_WORKSPACE_RECEIPT.sources"
    timeout 150s gxi {{ gerbil_test_runtime_options }} tools/build-workspace-benchmark.ss
    log="$(mktemp)"
    trap 'rm -f "$log"' EXIT
    GERBIL_LOADPATH="$ASCENT_WORKSPACE_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s gxi {{ gerbil_test_runtime_options }} t/performance/workspace-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 9
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    grep -x 'OK' "$log" >/dev/null

materialization-benchmark:
    python3 tools/test_execution.py run -- just _materialization-benchmark

_materialization-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export ASCENT_MATERIALIZATION_LIB="{{ justfile_directory() }}/.gerbil/relation-materialization/lib"
    export ASCENT_MATERIALIZATION_RECEIPT="${ASCENT_MATERIALIZATION_RECEIPT:-{{ justfile_directory() }}/.gerbil/relation-materialization/receipt.sexp}"
    mkdir -p .gerbil/relation-materialization
    shasum -a 256 table/expression.ss t/qualification/ascent-materialization-reference.ss t/performance/materialization-benchmark.ss tools/build-materialization-benchmark.ss > "$ASCENT_MATERIALIZATION_RECEIPT.sources"
    timeout 150s gxi {{ gerbil_test_runtime_options }} tools/build-materialization-benchmark.ss
    log="$(mktemp)"
    trap 'rm -f "$log"' EXIT
    GERBIL_LOADPATH="$ASCENT_MATERIALIZATION_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s gxi {{ gerbil_test_runtime_options }} t/performance/materialization-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 8
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    grep -x 'OK' "$log" >/dev/null

index-lifecycle-benchmark:
    python3 tools/test_execution.py run -- just _index-lifecycle-benchmark

_index-lifecycle-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export ASCENT_INDEX_LIFECYCLE_LIB="{{ justfile_directory() }}/.gerbil/index-lifecycle/lib"
    export ASCENT_INDEX_LIFECYCLE_RECEIPT="${ASCENT_INDEX_LIFECYCLE_RECEIPT:-{{ justfile_directory() }}/.gerbil/index-lifecycle/receipt.sexp}"
    mkdir -p .gerbil/index-lifecycle
    shasum -a 256 table/funs.ss table/access.ss table/provider.ss program/evaluate.ss program/positive.ss program/analysis.ss t/qualification/ascent-index-reference-funs.ss t/qualification/ascent-index-reference-provider.ss t/qualification/ascent-index-reference-evaluate.ss t/performance/index-lifecycle-benchmark.ss tools/build-index-lifecycle-benchmark.ss > "$ASCENT_INDEX_LIFECYCLE_RECEIPT.sources"
    timeout 150s gxi {{ gerbil_test_runtime_options }} tools/build-index-lifecycle-benchmark.ss
    log="$(mktemp)"
    trap 'rm -f "$log"' EXIT
    GERBIL_LOADPATH="$ASCENT_INDEX_LIFECYCLE_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 30s gxi {{ gerbil_test_runtime_options }} t/performance/index-lifecycle/module-resolution.ss > "$ASCENT_INDEX_LIFECYCLE_RECEIPT.modules"
    test "$(grep -c '/.gerbil/index-lifecycle/lib/.*\.ssi$' "$ASCENT_INDEX_LIFECYCLE_RECEIPT.modules")" -eq 5
    GERBIL_LOADPATH="$ASCENT_INDEX_LIFECYCLE_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s gxi {{ gerbil_test_runtime_options }} t/performance/index-lifecycle-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 7
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    grep -x 'OK' "$log" >/dev/null

result-benchmark:
    python3 tools/test_execution.py run -- just _result-benchmark

_result-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export ASCENT_RESULT_LIB="{{ justfile_directory() }}/.gerbil/result-publication/lib"
    export ASCENT_RESULT_RECEIPT="${ASCENT_RESULT_RECEIPT:-{{ justfile_directory() }}/.gerbil/result-publication/receipt.sexp}"
    mkdir -p .gerbil/result-publication
    shasum -a 256 program/result.ss program/evaluate.ss program/positive.ss program/analysis.ss table/access.ss table/funs.ss table/storage.ss t/qualification/ascent-result-reference-evaluate.ss t/performance/result-benchmark.ss tools/build-result-benchmark.ss > "$ASCENT_RESULT_RECEIPT.sources"
    timeout 150s gxi {{ gerbil_test_runtime_options }} tools/build-result-benchmark.ss
    log="$(mktemp)"
    trap 'rm -f "$log"' EXIT
    GERBIL_LOADPATH="$ASCENT_RESULT_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 30s gxi {{ gerbil_test_runtime_options }} t/performance/result-publication/module-resolution.ss > "$ASCENT_RESULT_RECEIPT.modules"
    test "$(grep -c '/.gerbil/result-publication/lib/.*\.ssi$' "$ASCENT_RESULT_RECEIPT.modules")" -eq 3
    GERBIL_LOADPATH="$ASCENT_RESULT_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s gxi {{ gerbil_test_runtime_options }} t/performance/result-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 10
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    grep -x 'OK' "$log" >/dev/null
