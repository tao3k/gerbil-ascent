# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

set shell := ["bash", "-euo", "pipefail", "-c"]

gerbil_test_runtime_options := "-:max-heap=1G,debug=q"
test_runner := 'GERBIL_LOADPATH="' + justfile_directory() + '${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" gerbil env gxi -:max-heap=1G,debug=q t/harness/run.ss'
tlc_release_url := "https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar"
tlc_sha256 := "936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88"

default:
    @just --list

build:
    GERBIL_BUILD_CORES="${GERBIL_BUILD_CORES:-$(getconf NPROCESSORS_ONLN)}" {{ test_runner }} run -- gerbil build

check-policy:
    ASP_GERBIL_SCHEME_POLICY=1 GERBIL_BUILD_CORES="${GERBIL_BUILD_CORES:-$(getconf NPROCESSORS_ONLN)}" {{ test_runner }} run -- gerbil build

test-file path:
    {{ test_runner }} test-file "{{ path }}"

# Native gxtest owns module execution; t/harness/run.ss owns the lane.
_test-file path:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f "{{ path }}"
    if [[ "{{ path }}" == t/qualification/ascent-temporal-lens-test.ss && -z "${ASCENT_NATIVE_TEST_REGISTRY:-}" ]]; then exec just _test-temporal; fi
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    output_file="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/case.XXXXXX")"
    trap 'rm -f "$output_file"' EXIT
    started=$SECONDS
    printf '[ascent-test] START %s\n' "{{ path }}"
    export GERBIL_LOADPATH="${ASCENT_TEST_LIBRARY:+$ASCENT_TEST_LIBRARY:}{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}"
    test_module="{{ path }}"
    if [[ -n "${ASCENT_TEST_LIBRARY:-}" ]]; then
        compiled="$ASCENT_TEST_LIBRARY/gerbil-ascent/${test_module%.ss}.ssi"
        test -f "$compiled"
        test_module="$compiled"
        runner=(gxi {{ gerbil_test_runtime_options }} t/harness/gxtest.ss)
        if [[ -n "${ASCENT_NATIVE_TEST_ENTRY:-}" ]]; then
            test -x "$ASCENT_NATIVE_TEST_ENTRY"
            runner=("$ASCENT_NATIVE_TEST_ENTRY" {{ gerbil_test_runtime_options }})
            if [[ -n "${ASCENT_NATIVE_TEST_REGISTRY:-}" ]]; then runner+=("{{ path }}"); fi
        fi
    else
        runner=(gerbil {{ gerbil_test_runtime_options }} test)
    fi
    if [[ -n "${ASCENT_NATIVE_TEST_ENTRY:-}" ]]; then
        timeout "${ASCENT_GXTEST_TIMEOUT:-120s}" "${runner[@]}" 2>&1 | tee "$output_file"
    else
        timeout "${ASCENT_GXTEST_TIMEOUT:-120s}" "${runner[@]}" -v 5 "$test_module" 2>&1 | tee "$output_file"
    fi
    if grep -E 'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi
    awk -f "{{ justfile_directory() }}/tools/assert-test-cases.awk" "$output_file"
    grep -Fx "MODULE-OK $test_module" "$output_file" >/dev/null
    grep -F 'HARNESS-OK' "$output_file" >/dev/null
    grep -x 'OK' "$output_file" >/dev/null
    if [[ -n "${ASCENT_TEST_LIBRARY:-}" ]]; then grep -Fx 'NATIVE-MODULES-OK' "$output_file" >/dev/null; fi
    printf '[ascent-test] PASS %s (%ss)\n' "{{ path }}" "$((SECONDS - started))"

# Explicitly admitted modules run in separate processes; native Cases stay serial.
test-parallel jobs='auto':
    {{ test_runner }} test "{{ jobs }}" parallel

# Native Cases stay serial; admitted modules use a process pool.
test jobs='auto':
    {{ test_runner }} test "{{ jobs }}" all

# Compile through the test entrypoint, then execute the native test module.
test-native path:
    {{ test_runner }} test-file "{{ path }}"

# Positive native lifecycle plus independently injected failure controls.
check-native-entry:
    #!/usr/bin/env bash
    set -euo pipefail
    just test-native t/harness/native-entry-test.ss
    export ASCENT_TEST_LIBRARY="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    export ASCENT_PERFORMANCE_MODULES="{{ justfile_directory() }}/.cache/ascent/native-library/modules.sexp"
    export ASCENT_NATIVE_TEST_ENTRY="{{ justfile_directory() }}/.cache/ascent/native-library/single-test"
    export PYTHONPATH="{{ justfile_directory() }}/python/src${PYTHONPATH:+:$PYTHONPATH}"
    output_file="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/native-control.XXXXXX")"
    trap 'rm -f "$output_file"' EXIT
    for control in setup case cleanup empty; do
        expected=42
        marker='ERROR MODULE'
        if [[ "$control" == case ]]; then marker='ERROR CASE'; fi
        if [[ "$control" == empty ]]; then expected=1; marker='FAIL no discovered Cases'; fi
        status=0
        ASCENT_NATIVE_ENTRY_CONTROL="$control" python3 -m ascent_test_support.supervision --startup-seconds 5 --idle-seconds 5 -- just _test-file t/harness/native-entry-test.ss > "$output_file" 2>&1 || status=$?
        if [[ "$status" != "$expected" ]] || ! grep -F "$marker" "$output_file" >/dev/null; then cat "$output_file"; exit 1; fi
        printf 'NATIVE-ENTRY-CONTROL-OK %s exit=%s\n' "$control" "$status"
    done

# Run the same native module inventory with one worker.
test-serial:
    {{ test_runner }} test 1 all

# Native Scheme actors own admission, output credits, failure and draining.
_test-suite jobs lane:
    {{ test_runner }} test "{{ jobs }}" "{{ lane }}"

# Small native registry and actor lifecycle qualification before the full pool.
check-actor-pool:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ test_runner }} test-pool 2 t/harness/native-entry-test.ss t/harness/actor-pool-test.ss
    export PYTHONPATH="{{ justfile_directory() }}/python/src${PYTHONPATH:+:$PYTHONPATH}"
    output=$(mktemp)
    trap 'rm -f "$output"' EXIT
    for control in missing unknown extra; do
      args=()
      marker='native pool requires one registry key'
      if [[ "$control" == unknown ]]; then args=(t/harness/not-in-registry.ss); marker='unknown native test registry key'; fi
      if [[ "$control" == extra ]]; then args=(t/harness/native-entry-test.ss other); fi
      code=0
      python3 -m ascent_test_support.supervision --startup-seconds 5 --idle-seconds 5 -- .cache/ascent/native-library/test-pool {{ gerbil_test_runtime_options }} "${args[@]}" > "$output" 2>&1 || code=$?
      [[ "$code" == 70 ]] && grep -F "$marker" "$output" >/dev/null
      if grep -E '^(HARNESS|MODULE|CASE) ' "$output" >/dev/null; then cat "$output"; exit 1; fi
      echo "NATIVE-REGISTRY-CONTROL-OK $control exit=$code"
    done

# Paired actor source transactions; evaluator work is outside this interval.
performance-source-cut:
    {{ test_runner }} run -- just _performance-source-cut

_performance-source-cut:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .cache/ascent/source-cut
    gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' -e '(import :std/make)' -e '(make ["program/source-cut" "t/performance/source-cut-benchmark"] srcdir: (current-directory) libdir: (path-expand ".cache/ascent/native-library/lib") build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in untouched wide-batch small; do
        timeout 90s gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' :gerbil-ascent/t/performance/source-cut-benchmark "$scenario" ".cache/ascent/source-cut/$scenario-final.sexp"
    done

# Paired complete actor rounds with wide ready queues and active assignments.
performance-actor-admission baseline='admission' lane='qualification':
    {{ test_runner }} run -- just _performance-actor-admission "{{ baseline }}" "{{ lane }}"

_performance-actor-admission baseline lane:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    [[ "{{ baseline }}" = admission || "{{ baseline }}" = coordinator ]]
    receipt_dir=".cache/ascent/actor-{{ baseline }}"
    mkdir -p "$receipt_dir" .cache/ascent/actor-admission
    gxi {{ gerbil_test_runtime_options }} t/performance/actor-admission-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/actor-admission/native-entry"
    [[ "{{ lane }}" = qualification || "{{ lane }}" = stream ]]
    scenarios=(wide backlog small)
    if [[ "{{ lane }}" = stream ]]; then scenarios=(stream); fi
    for scenario in "${scenarios[@]}"; do
        timeout 90s .cache/ascent/actor-admission/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" "$receipt_dir/$scenario.sexp" "{{ baseline }}"
    done

# Matched physical index build, extension and lookup with projection controls.
performance-index-projection:
    {{ test_runner }} run -- just _performance-index-projection

_performance-index-projection:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/index-projection
    gxi {{ gerbil_test_runtime_options }} t/performance/index-projection-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/index-projection/native-entry"
    for scenario in wide compact fallback small; do
        timeout 90s .cache/ascent/index-projection/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/index-projection/$scenario.sexp"
    done

# Complete fresh-engine expression execution, matched natively.
performance-expression-plan:
    {{ test_runner }} run -- just _performance-expression-plan

_performance-expression-plan:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/expression-plan
    gxi {{ gerbil_test_runtime_options }} t/performance/expression-plan-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/expression-plan/native-entry"
    status=0
    for scenario in lower-deep lower-scope lower-small lower-pure lower-pure-wide deep scope chain wide pure small; do
        timeout 90s .cache/ascent/expression-plan/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/expression-plan/$scenario.sexp" || status=1
    done
    exit "$status"

# Complete positive proof production and independent replay, matched natively.
performance-proof-replay:
    {{ test_runner }} run -- just _performance-proof-replay

_performance-proof-replay:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/proof-replay
    gxi {{ gerbil_test_runtime_options }} t/performance/proof-replay-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/proof-replay/native-entry"
    for scenario in copy duplicate source small; do
        timeout 90s .cache/ascent/proof-replay/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/proof-replay/$scenario.sexp"
    done

# Cold typed-expression compilation with matched native semantic checks.
performance-typed-domain:
    {{ test_runner }} run -- just _performance-typed-domain

_performance-typed-domain:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/typed-domain
    gxi {{ gerbil_test_runtime_options }} t/performance/typed-domain-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/typed-domain/native-entry"
    for scenario in ordered permuted small; do
        timeout 90s .cache/ascent/typed-domain/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/typed-domain/$scenario.sexp"
    done

# Matched complete independent absence verification using the public ASP API.
performance-nonmembership-index:
    {{ test_runner }} run -- just _performance-nonmembership-index

_performance-nonmembership-index:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/nonmembership-index
    gxi {{ gerbil_test_runtime_options }} t/performance/nonmembership-index-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/nonmembership-index/native-entry"
    for scenario in wide uncovered small; do
        timeout 90s .cache/ascent/nonmembership-index/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/nonmembership-index/$scenario.sexp"
    done

# Matched complete temporal projection through the public ASP benchmark API.
performance-temporal-projection:
    {{ test_runner }} run -- just _performance-temporal-projection

_performance-temporal-projection:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/temporal-projection
    gxi {{ gerbil_test_runtime_options }} t/performance/temporal-projection-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/temporal-projection/native-entry"
    for scenario in chain fan complete empty; do
        timeout 90s .cache/ascent/temporal-projection/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/temporal-projection/$scenario.sexp"
    done

# Matched SCC commit and complete construction control through ASP benchmarks.
performance-uf-commit:
    {{ test_runner }} run -- just _performance-uf-commit

_performance-uf-commit:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/uf-commit
    gxi {{ gerbil_test_runtime_options }} t/performance/uf-commit-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/uf-commit/native-entry"
    for scenario in partial cycle lifecycle dag duplicate islands; do
        timeout 90s .cache/ascent/uf-commit/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/uf-commit/$scenario.sexp"
    done

# Matched cold slot compilation and native traversal with shape controls.
performance-slot-projection:
    {{ test_runner }} run -- just _performance-slot-projection

_performance-slot-projection:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/slot-projection
    gxi {{ gerbil_test_runtime_options }} t/performance/slot-projection-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/slot-projection/native-entry"
    for scenario in sparse reverse repeat full below-boundary boundary small empty single; do
        timeout 90s .cache/ascent/slot-projection/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/slot-projection/$scenario.sexp"
    done

# Matched full proof production, replay and checker with source controls.
performance-stratified-model:
    {{ test_runner }} run -- just _performance-stratified-model

_performance-stratified-model:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/stratified-model
    gxi {{ gerbil_test_runtime_options }} t/performance/stratified-model-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/stratified-model/native-entry"
    for scenario in source derived relations duplicates small; do
        timeout 90s .cache/ascent/stratified-model/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/stratified-model/$scenario.sexp"
    done

# Matched complete operator compilation with shared lexical dependencies.
performance-operator-scope:
    {{ test_runner }} run -- just _performance-operator-scope

_performance-operator-scope:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/operator-scope
    gxi {{ gerbil_test_runtime_options }} t/performance/operator-scope-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/operator-scope/native-entry"
    for scenario in scaled-diamond small; do
        timeout 90s .cache/ascent/operator-scope/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/operator-scope/$scenario.sexp"
    done

# Grounded provenance maintenance with independent frozen semantics.
performance-provenance-maintenance:
    {{ test_runner }} run -- just _performance-provenance-maintenance

_performance-provenance-maintenance:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/provenance-maintenance
    gxi {{ gerbil_test_runtime_options }} t/performance/provenance-maintenance-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/provenance-maintenance/native-entry"
    for scenario in wide duplicates read small; do
        timeout 90s .cache/ascent/provenance-maintenance/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/provenance-maintenance/$scenario.sexp"
    done

performance-component-workspace:
    {{ test_runner }} run -- just _performance-component-workspace

_performance-component-workspace:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/component-workspace
    gxi {{ gerbil_test_runtime_options }} t/performance/component-workspace-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/component-workspace/native-entry"
    for scenario in scan recursive indexed small; do
        timeout 90s .cache/ascent/component-workspace/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/component-workspace/$scenario.sexp"
    done

performance-component-scope:
    {{ test_runner }} run -- just _performance-component-scope

_performance-component-scope:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/component-scope
    gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' -e '(import :std/make)' -e '(make ["program/component-plan" "program/component-worker" "program/positive-components" "program/evaluate" "t/performance/component-scope/reference" "t/performance/component-scope/fixture" "t/performance/component-scope-benchmark"] srcdir: (current-directory) libdir: (path-expand ".cache/ascent/native-library/lib") build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in sparse-plan multihead-plan closure-one closure-four small; do
        timeout 90s gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' :gerbil-ascent/t/performance/component-scope-benchmark "$scenario" "$library" ".cache/ascent/component-scope/$scenario.sexp"
    done

# Paired strict-dependency admission and complete cold/warm public solves.
performance-strata-preflight:
    {{ test_runner }} run -- just _performance-strata-preflight

_performance-strata-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/strata-preflight
    gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' -e '(import :std/make)' -e '(make ["core/rule-semantics" "program/actor-round" "program/positive-components" "program/planning" "program/evaluate" "t/performance/strata-preflight/reference-semantics" "t/performance/strata-preflight/reference-planning" "t/performance/strata-preflight/reference-evaluate" "t/performance/strata-preflight/fixture" "t/performance/strata-preflight-benchmark"] srcdir: (current-directory) libdir: (path-expand ".cache/ascent/native-library/lib") build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in positive negation aggregate lattice cold warm small; do
        timeout 90s gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' :gerbil-ascent/t/performance/strata-preflight-benchmark "$scenario" "$library" ".cache/ascent/strata-preflight/$scenario.sexp"
    done

# Paired ordered index build/extension/lookup and complete native solve control.
performance-index-build:
    {{ test_runner }} run -- just _performance-index-build

_performance-index-build:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/index-build
    gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' -e '(import :std/make)' -e '(make ["table/funs" "table/access" "program/index" "program/evaluate" "t/performance/index-build/reference-funs" "t/performance/index-build/reference-access" "t/performance/index-build/reference-index" "t/performance/index-build/reference-evaluate" "t/performance/index-build/fixture" "t/performance/index-build-benchmark"] srcdir: (current-directory) libdir: (path-expand ".cache/ascent/native-library/lib") build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in scalar-dense scalar-unique composite-dense composite-unique empty small solve; do
        timeout 90s gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' :gerbil-ascent/t/performance/index-build-benchmark "$scenario" "$library" ".cache/ascent/index-build/$scenario.sexp"
    done

# Paired persistent source-log kernels and complete public source transactions.
performance-source-log:
    {{ test_runner }} run -- just _performance-source-log

_performance-source-log:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/source-log
    gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' -e '(import :std/make)' -e '(make ["core/positive-plan" "program/actor-round" "program/source-log" "program/evaluate" "program/session" "t/performance/source-log/reference-update-selection" "t/performance/source-log/reference-reuse" "t/performance/source-log/reference-evaluate" "t/performance/source-log/reference-session" "t/performance/source-log/fixture" "t/performance/source-log-benchmark"] srcdir: (current-directory) libdir: (path-expand ".cache/ascent/native-library/lib") build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in join equal pending mismatch update appended-update small; do
        timeout 90s gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' :gerbil-ascent/t/performance/source-log-benchmark "$scenario" "$library" ".cache/ascent/source-log/$scenario.sexp"
    done

# Paired native selected frames and complete dependency updates/append lifecycle.
performance-selected-activation:
    {{ test_runner }} run -- just _performance-selected-activation

_performance-selected-activation:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/selected-activation
    gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' -e '(import :std/make)' -e '(make ["program/activation" "program/update-selection" "program/reuse" "program/evaluate" "t/performance/selected-activation/reference-selection" "t/performance/selected-activation/reference-reuse" "t/performance/selected-activation/reference-evaluate" "t/performance/selected-activation/fixture" "t/performance/selected-activation-benchmark"] srcdir: (current-directory) libdir: (path-expand ".cache/ascent/native-library/lib") build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in sparse partial all update lifecycle small; do
        timeout 90s gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' :gerbil-ascent/t/performance/selected-activation-benchmark "$scenario" "$library" ".cache/ascent/selected-activation/$scenario.sexp"
    done

# Paired native storage batch preflight and complete retained-engine updates.
performance-storage-batch:
    {{ test_runner }} run -- just _performance-storage-batch

_performance-storage-batch:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/storage-batch
    gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' -e '(import :std/make)' -e '(make ["program/admission" "program/evaluate" "t/performance/storage-batch/reference" "t/performance/storage-batch/reference-evaluate" "t/performance/storage-batch/fixture" "t/performance/storage-batch-benchmark"] srcdir: (current-directory) libdir: (path-expand ".cache/ascent/native-library/lib") build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in batch wide duplicates engine single empty engine-small; do
        timeout 90s gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' :gerbil-ascent/t/performance/storage-batch-benchmark "$scenario" "$library" ".cache/ascent/storage-batch/$scenario.sexp"
    done

# Paired native engine-owned physical index entries and complete indexed solves.
performance-index-entry:
    {{ test_runner }} run -- just _performance-index-entry

_performance-index-entry:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/index-entry
    gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' -e '(import :std/make)' -e '(make ["program/index" "program/evaluate" "t/performance/index-entry/reference" "t/performance/index-entry/reference-evaluate" "t/performance/index-entry/fixture" "t/performance/index-entry-benchmark"] srcdir: (current-directory) libdir: (path-expand ".cache/ascent/native-library/lib") build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in all delta advance scalar cold solve-wide solve-small; do
        timeout 90s gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' :gerbil-ascent/t/performance/index-entry-benchmark "$scenario" "$library" ".cache/ascent/index-entry/$scenario.sexp"
    done

# Paired native general callbacks, ordered pattern bindings and complete solves.
performance-rule-bindings:
    {{ test_runner }} run -- just _performance-rule-bindings

_performance-rule-bindings:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    mkdir -p .cache/ascent/rule-bindings
    gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' -e '(import :std/make)' -e '(make ["core/rule-bindings" "core/positive-plan" "program/evaluate" "t/performance/rule-bindings/reference" "t/performance/rule-bindings/reference-positive" "t/performance/rule-bindings/reference-evaluate" "t/performance/rule-bindings/fixture" "t/performance/rule-bindings-benchmark"] srcdir: (current-directory) libdir: (path-expand ".cache/ascent/native-library/lib") build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in call-two call-six bind-wide guards patterns small; do
        timeout 90s gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' :gerbil-ascent/t/performance/rule-bindings-benchmark "$scenario" "$library" ".cache/ascent/rule-bindings/$scenario.sexp"
    done

# Paired native finite evidence generation and verification.
performance-finite-replay:
    {{ test_runner }} run -- just _performance-finite-replay

_performance-finite-replay:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' -e '(import :std/make)' -e '(make ["candidate/funs" "candidate/finite-evidence" "candidate/types" "candidate/datum" "t/performance/finite-replay/reference-funs" "t/performance/finite-replay/reference" "t/performance/finite-replay-benchmark"] srcdir: (current-directory) libdir: (path-expand ".cache/ascent/native-library/lib") build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in wide duplicates small constant; do
        timeout 90s gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' :gerbil-ascent/t/performance/finite-replay-benchmark "$scenario" "$library"
    done

# Paired native inert traversal and complete certificate verification.
performance-bounded-datum:
    {{ test_runner }} run -- just _performance-bounded-datum

_performance-bounded-datum:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' -e '(import :std/make)' -e '(make ["candidate/datum" "candidate/types" "candidate/provenance" "candidate/provenance-graph" "t/performance/bounded-datum/reference" "t/performance/bounded-datum/reference-graph" "t/performance/bounded-datum-benchmark"] srcdir: (current-directory) libdir: (path-expand ".cache/ascent/native-library/lib") build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in kernel verifier; do
        timeout 90s gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' :gerbil-ascent/t/performance/bounded-datum-benchmark "$scenario" "$library"
    done

# Paired native complete-provenance generation.
performance-provenance-index:
    {{ test_runner }} run -- just _performance-provenance-index

_performance-provenance-index:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' -e '(import :std/make)' -e '(make ["candidate/provenance-graph" "t/performance/provenance-index/reference" "t/performance/provenance-index-benchmark"] srcdir: (current-directory) libdir: (path-expand ".cache/ascent/native-library/lib") build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in small wide duplicates; do
        timeout 90s gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' :gerbil-ascent/t/performance/provenance-index-benchmark "$scenario" "$library"
    done

# Paired native source-selection over compiled declaration dependencies.
performance-update-dependencies:
    {{ test_runner }} run -- just _performance-update-dependencies

_performance-update-dependencies:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' -e '(import :std/make)' -e '(make ["core/dependency-graph" "core/rule-semantics" "program/planning" "program/update-selection" "t/performance/update-dependencies/reference" "t/performance/update-dependencies-benchmark"] srcdir: (current-directory) libdir: (path-expand ".cache/ascent/native-library/lib") build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in chain-changed chain-unchanged wide-changed wide-unchanged; do
        timeout 90s gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' :gerbil-ascent/t/performance/update-dependencies-benchmark "$scenario" "$library"
    done

# Paired native index construction, extension and evaluated-key lookup.
performance-scalar-index:
    {{ test_runner }} run -- just _performance-scalar-index

_performance-scalar-index:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' -e '(import :std/make)' -e '(make ["table/funs" "table/access" "core/positive-plan" "program/index" "program/evaluate" "t/performance/scalar-index/reference-access" "t/performance/scalar-index-benchmark"] srcdir: (current-directory) libdir: (path-expand ".cache/ascent/native-library/lib") build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in single-first single-later composite-control tiny-control; do
        timeout 90s gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' :gerbil-ascent/t/performance/scalar-index-benchmark "$scenario" "$library"
    done

performance-finite-mapping:
    {{ test_runner }} run -- just _performance-finite-mapping

_performance-finite-mapping:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ justfile_directory() }}/.cache/ascent/native-library/lib"
    gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' -e '(import :std/make)' -e '(make ["table/provider" "table/storage" "table/access" "program/types" "program/objects" "program/scheme-checked" "program/index" "program/evaluate" "program/session" "program/update-selection" "t/performance/finite-mapping/reference-types" "t/performance/finite-mapping/reference-objects" "t/performance/finite-mapping/reference" "t/performance/finite-mapping-benchmark"] srcdir: (current-directory) libdir: (path-expand ".cache/ascent/native-library/lib") build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in narrow-rows wide-rows wide-view source-control canonical-provider; do
        timeout 90s gxi {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand ".cache/ascent/native-library/lib"))' :gerbil-ascent/t/performance/finite-mapping-benchmark "$scenario" "$library"
    done

test-quick:
    {{ test_runner }} test-quick

_test-quick:
    #!/usr/bin/env bash
    set -euo pipefail
    gxi {{ gerbil_test_runtime_options }} t/harness/run.ss test-modules quick | while IFS= read -r path; do just _test-file "$path"; done

small-graph-benchmark:
    {{ test_runner }} run -- just _small-graph-benchmark

_small-graph-benchmark:
    GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s gerbil {{ gerbil_test_runtime_options }} env gxi t/performance/small-graph-benchmark.ss

# Matched row-copy boundary costs. The probe checks equal rows and isolation
# after every sample; it does not time a complete retained-session solve.
admission-copy-benchmark:
    {{ test_runner }} run -- just _admission-copy-benchmark

_admission-copy-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    output_file="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/case.XXXXXX")"
    trap 'rm -f "$output_file"' EXIT
    export GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}"
    printf '[admission-copy] START three matched row-copy cases\n'
    timeout 180s gxi {{ gerbil_test_runtime_options }} t/performance/scheme-admission-copy-benchmark.ss 2>&1 | tee "$output_file"
    test "$(grep -c '^CASE ' "$output_file")" -eq 3
    test "$(grep -c '^WARM ' "$output_file")" -eq 6
    test "$(grep -c '^SAMPLE ' "$output_file")" -eq 48
    grep -x 'OK' "$output_file" >/dev/null
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi

# LeanPoo-backed ASCENT proof package. The Lake manifest fixes dependencies.
check-lean-proofs:
    #!/usr/bin/env bash
    set -euo pipefail
    cd packages/proofs/lean
    lake -v build AscentProof AscentProofTests

# Lean proofs and bounded TLC publication models. Supply TLC_JAR or TLC_BIN.
check-nonmembership-formal: check-lean-proofs
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "${TLC_JAR:-}" && -z "${TLC_BIN:-}" ]]; then
      TLC_JAR=.cache/ascent/tools/tla2tools-v1.7.4.jar
      mkdir -p "$(dirname "$TLC_JAR")"
      if [[ ! -f "$TLC_JAR" ]]; then
        curl -fLsS "{{ tlc_release_url }}" -o "$TLC_JAR.download"
        mv "$TLC_JAR.download" "$TLC_JAR"
      fi
    fi
    if [[ -n "${TLC_JAR:-}" ]]; then
      actual="$(shasum -a 256 "$TLC_JAR" | awk '{print $1}')"
      [[ "$actual" == "{{ tlc_sha256 }}" ]] || { echo "TLC jar checksum mismatch: $TLC_JAR" >&2; exit 2; }
      tlc=(java -XX:+UseParallelGC -Xmx1g -cp "$TLC_JAR" tlc2.TLC)
    else
      tlc=("${TLC_BIN:-tlc}")
    fi
    cutoff="${ASCENT_TLC_GENERATION_CUTOFF:-2}"
    [[ "$cutoff" =~ ^[0-9]+$ ]] && (( cutoff >= 2 )) || { echo 'TLC generation cutoff must be an integer >= 2' >&2; exit 2; }
    temp="$(mktemp -d)"
    trap 'rm -rf "$temp"' EXIT
    for model in PositiveNonmembershipSession SessionTransaction NativeSessionPublication; do
      sed "s/TLCGenerationCutoff = [0-9][0-9]*/TLCGenerationCutoff = $cutoff/" "packages/proofs/tla/$model.cfg" > "$temp/$model.cfg"
      echo "TLA-CHECK $model generation-cutoff=$cutoff (TLC enumeration only)"
      "${tlc[@]}" -workers 2 -config "$temp/$model.cfg" -metadir "$temp/$model" "packages/proofs/tla/$model.tla"
    done
    for mutation in early bounded alias; do
      sed "s/Mutation = \"none\"/Mutation = \"$mutation\"/" "$temp/NativeSessionPublication.cfg" > "$temp/native-$mutation.cfg"
      if "${tlc[@]}" -workers 2 -config "$temp/native-$mutation.cfg" -metadir "$temp/native-$mutation" packages/proofs/tla/NativeSessionPublication.tla > "$temp/native-$mutation.log" 2>&1; then
        cat "$temp/native-$mutation.log"
        echo "Missing native Session counterexample for $mutation" >&2
        exit 1
      else
        code=$?
      fi
      cat "$temp/native-$mutation.log"
      [[ "$code" = 12 ]] && grep -q 'Invariant CommittedSnapshot is violated' "$temp/native-$mutation.log"
      echo "COUNTEREXAMPLE-OK native-$mutation"
    done
    for mutation in early stale global reuse; do
      sed "s/Mutation = \"none\"/Mutation = \"$mutation\"/" "$temp/SessionTransaction.cfg" > "$temp/$mutation.cfg"
      if "${tlc[@]}" -workers 2 -config "$temp/$mutation.cfg" -metadir "$temp/$mutation" packages/proofs/tla/SessionTransaction.tla > "$temp/$mutation.log" 2>&1; then
        cat "$temp/$mutation.log"
        echo "Missing counterexample for $mutation" >&2
        exit 1
      else
        code=$?
      fi
      cat "$temp/$mutation.log"
      case "$mutation" in
        early) [[ "$code" = 12 ]] && grep -q 'Invariant AtomicSnapshot is violated' "$temp/$mutation.log" ;;
        stale) [[ "$code" = 13 ]] && grep -q 'Action property NoStaleCommit is violated' "$temp/$mutation.log" ;;
        global) [[ "$code" = 12 ]] && grep -q 'Invariant AtomicSnapshot is violated' "$temp/$mutation.log" ;;
        reuse) [[ "$code" = 12 ]] && grep -q 'Invariant AtomicSnapshot is violated' "$temp/$mutation.log" ;;
      esac
      echo "COUNTEREXAMPLE-OK $mutation"
    done
    echo 'FORMAL-CHECK-OK'

# Proposed actor protocol plus the existing unbounded Lean and Session gates.
check-actor-round-formal: check-nonmembership-formal
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "${TLC_BIN:-}" ]]; then tlc=("$TLC_BIN"); else tlc=(java -XX:+UseParallelGC -cp "${TLC_JAR:-.cache/ascent/tools/tla2tools-v1.7.4.jar}" tlc2.TLC); fi
    temp=$(mktemp -d)
    trap 'rm -rf "$temp"' EXIT
    generations="${ASCENT_ACTOR_TLC_GENERATION_CUTOFF:-2}"
    rounds="${ASCENT_ACTOR_TLC_ROUND_CUTOFF:-4}"
    [[ "$generations" =~ ^[0-9]+$ && "$rounds" =~ ^[0-9]+$ && "$generations" -ge 2 && "$rounds" -ge 3 ]]
    sed -e "s/TLCGenerationCutoff = [0-9][0-9]*/TLCGenerationCutoff = $generations/" -e "s/TLCRoundCutoff = [0-9][0-9]*/TLCRoundCutoff = $rounds/" packages/proofs/tla/ActorRound.cfg > "$temp/normal.cfg"
    echo "TLA-CHECK ActorRound generation-cutoff=$generations round-cutoff=$rounds (TLC enumeration only)"
    "${tlc[@]}" -workers 2 -config "$temp/normal.cfg" -metadir "$temp/normal" packages/proofs/tla/ActorRound.tla
    for mutation in early stale cancel; do
      sed "s/Mutation = \"none\"/Mutation = \"$mutation\"/" "$temp/normal.cfg" > "$temp/$mutation.cfg"
      code=0
      "${tlc[@]}" -workers 2 -config "$temp/$mutation.cfg" -metadir "$temp/$mutation" packages/proofs/tla/ActorRound.tla > "$temp/$mutation.out" 2>&1 || code=$?
      if [[ "$mutation" = stale ]]; then expected=NoStaleCompletion; else expected=CompletePublication; fi
      [[ "$code" = 12 ]] && grep -q "Invariant $expected is violated" "$temp/$mutation.out"
      echo "COUNTEREXAMPLE-OK actor-$mutation $expected"
    done
    echo 'ACTOR-ROUND-CHECK-OK'

# Solver streaming credits and terminal drain safety.
check-actor-credit-formal:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "${TLC_BIN:-}" ]]; then tlc=("$TLC_BIN"); else tlc=(java -XX:+UseParallelGC -cp "${TLC_JAR:-.cache/ascent/tools/tla2tools-v1.7.4.jar}" tlc2.TLC); fi
    temp=$(mktemp -d)
    trap 'rm -rf "$temp"' EXIT
    for capacity in 1 2 3; do
      sed "s/Capacity = 2/Capacity = $capacity/" packages/proofs/tla/ActorRoundCredits.cfg > "$temp/$capacity.cfg"
      "${tlc[@]}" -workers 1 -config "$temp/$capacity.cfg" -metadir "$temp/$capacity" packages/proofs/tla/ActorRoundCredits.tla
    done
    sed 's/EarlyReturn = FALSE/EarlyReturn = TRUE/' packages/proofs/tla/ActorRoundCredits.cfg > "$temp/early.cfg"
    code=0
    "${tlc[@]}" -workers 1 -config "$temp/early.cfg" -metadir "$temp/early" packages/proofs/tla/ActorRoundCredits.tla > "$temp/early.out" 2>&1 || code=$?
    [[ "$code" = 12 ]] && grep -q 'Invariant CompleteReturn is violated' "$temp/early.out"
    echo 'COUNTEREXAMPLE-OK actor-credit-early CompleteReturn'
    echo 'ACTOR-CREDIT-CHECK-OK'

# Test-pool protocol safety is distinct from solver round safety.
check-actor-pool-formal:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "${TLC_BIN:-}" ]]; then tlc=("$TLC_BIN"); else tlc=(java -XX:+UseParallelGC -cp "${TLC_JAR:-.cache/ascent/tools/tla2tools-v1.7.4.jar}" tlc2.TLC); fi
    temp=$(mktemp -d)
    trap 'rm -rf "$temp"' EXIT
    for capacity in 1 2 3; do
      sed "s/Capacity = 2/Capacity = $capacity/" packages/proofs/tla/ActorTestPool.cfg > "$temp/$capacity.cfg"
      "${tlc[@]}" -workers 1 -config "$temp/$capacity.cfg" -metadir "$temp/$capacity" packages/proofs/tla/ActorTestPool.tla
    done
    sed 's/EarlyReturn = FALSE/EarlyReturn = TRUE/' packages/proofs/tla/ActorTestPool.cfg > "$temp/early.cfg"
    code=0
    "${tlc[@]}" -workers 1 -config "$temp/early.cfg" -metadir "$temp/early" packages/proofs/tla/ActorTestPool.tla > "$temp/early.out" 2>&1 || code=$?
    [[ "$code" = 12 ]] && grep -q 'Invariant CompleteReturn is violated' "$temp/early.out"
    echo 'COUNTEREXAMPLE-OK actor-pool-early CompleteReturn'
    echo 'ACTOR-POOL-CHECK-OK'

# Matched finite-operator research probe; every sample checks independent
# closure before reporting cost. This is separate from the SS suite.
operator-change-probe:
    {{ test_runner }} run -- just _operator-change-probe

_operator-change-probe:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    output_file="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/case.XXXXXX")"
    trap 'rm -f "$output_file"' EXIT
    export GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}"
    timeout 90s gerbil {{ gerbil_test_runtime_options }} env gxi t/performance/scheme-operator-change-probe.ss 2>&1 | tee "$output_file"
    test "$(grep -c '^CASE ' "$output_file")" -eq 6
    test "$(grep -c '^SAMPLE ' "$output_file")" -eq 60
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi

# Exact-set gate and matched exploratory timing for native retained updates.
operator-retained-probe:
    {{ test_runner }} run -- just _operator-retained-probe

_operator-retained-probe:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    output_file="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/case.XXXXXX")"
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
    {{ test_runner }} run -- just _binding-benchmark

_binding-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export GERBIL_BUILD_CORES="${GERBIL_BUILD_CORES:-$(getconf NPROCESSORS_ONLN)}"
    export ASCENT_BINDING_BENCH_LIB="{{ justfile_directory() }}/.gerbil/binding-benchmark/lib"
    export ASCENT_BINDING_RECEIPT="${ASCENT_BINDING_RECEIPT:-{{ justfile_directory() }}/.gerbil/binding-benchmark/receipt.sexp}"
    mkdir -p "$ASCENT_BINDING_BENCH_LIB"
    shasum -a 256 core/dependency-graph.ss core/rule-semantics.ss program/objects.ss program/evaluate.ss program/analysis.ss program/planning.ss t/qualification/ascent-binding-reference-fixture.ss t/qualification/ascent-binding-reference-evaluate.ss t/qualification/ascent-index-program-fixture.ss t/performance/binding-benchmark.ss tools/build-binding-benchmark.ss > "$ASCENT_BINDING_RECEIPT.sources"
    started=$SECONDS
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    log="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/run.XXXXXX")"
    trap 'rm -f "$log"' EXIT
    printf '[binding-benchmark] BUILD compiled current/reference engines (%s cores)\n' "$GERBIL_BUILD_CORES"
    timeout 150s gxi {{ gerbil_test_runtime_options }} tools/build-binding-benchmark.ss
    printf '[binding-benchmark] RUN alternating old/new, 1000 samples per case\n'
    GERBIL_LOADPATH="$ASCENT_BINDING_BENCH_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 120s gxi {{ gerbil_test_runtime_options }} t/performance/binding-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 6
    grep -x 'OK' "$log" >/dev/null

strata-benchmark:
    {{ test_runner }} run -- just _strata-benchmark

_strata-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export GERBIL_BUILD_CORES="${GERBIL_BUILD_CORES:-$(getconf NPROCESSORS_ONLN)}"
    export ASCENT_STRATA_BENCH_LIB="{{ justfile_directory() }}/.gerbil/strata-benchmark/lib"
    export ASCENT_STRATA_RECEIPT="${ASCENT_STRATA_RECEIPT:-{{ justfile_directory() }}/.gerbil/strata-benchmark/receipt.sexp}"
    mkdir -p "$ASCENT_STRATA_BENCH_LIB"
    shasum -a 256 core/dependency-graph.ss core/rule-semantics.ss t/qualification/ascent-strata-fixture.ss t/performance/strata-benchmark.ss tools/build-strata-benchmark.ss > "$ASCENT_STRATA_RECEIPT.sources"
    started=$SECONDS
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    log="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/run.XXXXXX")"
    trap 'rm -f "$log"' EXIT
    printf '[strata-benchmark] BUILD current planning and relaxation oracle\n'
    timeout 60s gxi {{ gerbil_test_runtime_options }} tools/build-strata-benchmark.ss
    printf '[strata-benchmark] RUN alternating old/new, 1000 samples per case\n'
    GERBIL_LOADPATH="$ASCENT_STRATA_BENCH_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 90s gxi {{ gerbil_test_runtime_options }} t/performance/strata-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 4
    grep -x 'OK' "$log" >/dev/null

# Run one unchanged SS fixture through the native qualification harness.
performance-scenario name:
    {{ test_runner }} performance "{{ name }}"

# ASCENT owns its 1000-sample SS receipts using ASP's benchmark profile.
performance:
    {{ test_runner }} performance suite

_performance-scenario name:
    #!/usr/bin/env bash
    set -euo pipefail
    name="{{ name }}"
    path="t/scenarios/performance/$name/scenario.ss"
    case "$name" in
        ascent-binary-program) test_module=t/performance/ascent-binary-program-performance-test.ss ;;
        ascent-shortest-candidates) test_module=t/performance/ascent-shortest-candidates-performance-test.ss ;;
        *) test -f "$path"; test_module=t/performance/ascent-scenario-performance-test.ss ;;
    esac
    started=$SECONDS
    printf '[ascent-ss] START %s (1000 samples)\n' "$name"
    if ASCENT_SS_SCENARIO="$path" ASCENT_GXTEST_TIMEOUT="${ASCENT_GXTEST_TIMEOUT:-120s}" just _test-file "$test_module"; then
        printf '[ascent-ss] PASS %s (%ss)\n' "$name" "$((SECONDS - started))"
    else
        status=$?
        printf '[ascent-ss] FAIL %s (%ss, exit=%s)\n' "$name" "$((SECONDS - started))" "$status" >&2
        exit "$status"
    fi

_performance:
    #!/usr/bin/env bash
    set -euo pipefail
    # The ASP runner reports after its 1000 timed attempts; printing from a
    # timed thunk would change the samples. Each native test process has a
    # bounded total timeout; only actual build/test/results report progress.
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
        ASCENT_GXTEST_TIMEOUT="${ASCENT_GXTEST_TIMEOUT:-180s}" just _performance-scenario "$1"
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
    run_case ascent-binary-program just _performance-scenario ascent-binary-program
    run_scenario ascent-reachability-closure
    run_scenario ascent-table-expression
    run_scenario ascent-table-expression-membership
    run_case ascent-shortest-candidates just _performance-scenario ascent-shortest-candidates
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
    @gxi t/harness/artifact.ss check >/dev/null
    @PYTHONPATH="{{ justfile_directory() }}/python/src" python3 -m ascent_test_support.supervision -- timeout 90s .cache/ascent/native-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle byods-lattice-session

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
    @gxi t/harness/artifact.ss check >/dev/null
    @PYTHONPATH="{{ justfile_directory() }}/python/src" python3 -m ascent_test_support.supervision -- timeout 90s .cache/ascent/native-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle arity-repetition

clause-composition-rows:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-clause-composition-output.ss

support-study-reference:
    @timeout 120s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-support-study-output.ss reference

support-study-hypothetical:
    @timeout 120s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-support-study-output.ss hypothetical

support-study-candidate mode="evaluate":
    @timeout 120s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-support-study-output.ss {{ mode }}

candidate-description:
    @timeout 120s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-support-study-output.ss description

candidate-repair-seed mode="repair-seed":
    @timeout 120s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-support-study-output.ss {{ mode }}

support-discriminator-reference:
    @timeout 120s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-support-study-output.ss discriminator-reference

support-discriminator-candidate:
    @timeout 120s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-support-study-output.ss discriminator-evaluate

clause-scale-rows:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-clause-scale-output.ss

divisibility-lattice-rows:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-divisibility-lattice-output.ss

multi-source-session-rows:
    @gxi t/harness/artifact.ss check >/dev/null
    @PYTHONPATH="{{ justfile_directory() }}/python/src" python3 -m ascent_test_support.supervision -- timeout 90s .cache/ascent/native-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle multi-source-session

byods-session-rows:
    @gxi t/harness/artifact.ss check >/dev/null
    @PYTHONPATH="{{ justfile_directory() }}/python/src" python3 -m ascent_test_support.supervision -- timeout 90s .cache/ascent/native-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle byods-session

grouped-eqrel-session-rows:
    @gxi t/harness/artifact.ss check >/dev/null
    @PYTHONPATH="{{ justfile_directory() }}/python/src" python3 -m ascent_test_support.supervision -- timeout 90s .cache/ascent/native-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle grouped-eqrel-session

oracle:
    #!/usr/bin/env bash
    set -euo pipefail
    export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
    if [[ "$(uname -s)" == Darwin ]]; then
        unset SDKROOT DEVELOPER_DIR
        export SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
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
    {{ test_runner }} run -- just _size-benchmark

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
    {{ test_runner }} run -- just _multi-frontier-benchmark

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
    {{ test_runner }} run -- just _set-size-benchmark

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
    {{ test_runner }} run -- just _set-batch-benchmark

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
    {{ test_runner }} run -- just _set-emit-benchmark

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
    {{ test_runner }} run -- just _set-emit-allocation

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
    {{ test_runner }} run -- just _set-source-allocation

_set-source-allocation:
    timeout 90s gxi {{ gerbil_test_runtime_options }} tools/build-set-source-benchmark.ss
    GERBIL_LOADPATH="$ASCENT_SET_SOURCE_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 150s gxi {{ gerbil_test_runtime_options }} t/performance/set-source-allocation.ss

# Whole-solve positive rule plans: ordered semantics, allocation and raw timing.
positive-plan-benchmark:
    {{ test_runner }} run -- just _positive-plan-benchmark

_positive-plan-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export ASCENT_POSITIVE_PLAN_LIB="{{ justfile_directory() }}/.gerbil/positive-plan/lib"
    export ASCENT_POSITIVE_PLAN_RECEIPT="${ASCENT_POSITIVE_PLAN_RECEIPT:-{{ justfile_directory() }}/.gerbil/positive-plan/receipt.sexp}"
    mkdir -p .gerbil/positive-plan
    shasum -a 256 core/positive-plan.ss program/index.ss program/actor-round.ss program/evaluate.ss program/analysis.ss t/qualification/ascent-positive-plan-reference-analysis.ss t/qualification/ascent-positive-plan-reference-evaluate.ss t/performance/positive-plan-benchmark.ss tools/build-positive-plan-benchmark.ss > "$ASCENT_POSITIVE_PLAN_RECEIPT.sources"
    timeout 150s gxi {{ gerbil_test_runtime_options }} tools/build-positive-plan-benchmark.ss
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    log="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/run.XXXXXX")"
    trap 'rm -f "$log"' EXIT
    GERBIL_LOADPATH="$ASCENT_POSITIVE_PLAN_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s gxi {{ gerbil_test_runtime_options }} t/performance/positive-plan-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 7
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    grep -x 'OK' "$log" >/dev/null

workspace-benchmark:
    {{ test_runner }} run -- just _workspace-benchmark

_workspace-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export ASCENT_WORKSPACE_LIB="{{ justfile_directory() }}/.gerbil/execution-workspace/lib"
    export ASCENT_WORKSPACE_RECEIPT="${ASCENT_WORKSPACE_RECEIPT:-{{ justfile_directory() }}/.gerbil/execution-workspace/receipt.sexp}"
    mkdir -p .gerbil/execution-workspace
    shasum -a 256 core/positive-plan.ss program/evaluate.ss program/analysis.ss t/qualification/ascent-workspace-reference-analysis.ss t/qualification/ascent-workspace-reference-positive.ss t/qualification/ascent-workspace-reference-evaluate.ss t/performance/workspace-benchmark.ss tools/build-workspace-benchmark.ss > "$ASCENT_WORKSPACE_RECEIPT.sources"
    timeout 150s gxi {{ gerbil_test_runtime_options }} tools/build-workspace-benchmark.ss
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    log="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/run.XXXXXX")"
    trap 'rm -f "$log"' EXIT
    GERBIL_LOADPATH="$ASCENT_WORKSPACE_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s gxi {{ gerbil_test_runtime_options }} t/performance/workspace-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 9
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    grep -x 'OK' "$log" >/dev/null

ordered-relations-benchmark:
    {{ test_runner }} run -- gxi {{ gerbil_test_runtime_options }} t/performance/ordered-relations/qualify.ss

materialization-benchmark:
    {{ test_runner }} run -- just _materialization-benchmark

_materialization-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export ASCENT_MATERIALIZATION_LIB="{{ justfile_directory() }}/.gerbil/relation-materialization/lib"
    export ASCENT_MATERIALIZATION_RECEIPT="${ASCENT_MATERIALIZATION_RECEIPT:-{{ justfile_directory() }}/.gerbil/relation-materialization/receipt.sexp}"
    mkdir -p .gerbil/relation-materialization
    shasum -a 256 core/binary-relation.ss table/expression.ss t/qualification/ascent-materialization-reference.ss t/performance/materialization-benchmark.ss tools/build-materialization-benchmark.ss > "$ASCENT_MATERIALIZATION_RECEIPT.sources"
    timeout 150s gxi {{ gerbil_test_runtime_options }} tools/build-materialization-benchmark.ss
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    log="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/run.XXXXXX")"
    trap 'rm -f "$log"' EXIT
    GERBIL_LOADPATH="$ASCENT_MATERIALIZATION_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s gxi {{ gerbil_test_runtime_options }} t/performance/materialization-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 8
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    grep -x 'OK' "$log" >/dev/null

index-lifecycle-benchmark:
    {{ test_runner }} run -- just _index-lifecycle-benchmark

_index-lifecycle-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export ASCENT_INDEX_LIFECYCLE_LIB="{{ justfile_directory() }}/.gerbil/index-lifecycle/lib"
    export ASCENT_INDEX_LIFECYCLE_RECEIPT="${ASCENT_INDEX_LIFECYCLE_RECEIPT:-{{ justfile_directory() }}/.gerbil/index-lifecycle/receipt.sexp}"
    mkdir -p .gerbil/index-lifecycle
    shasum -a 256 table/funs.ss table/access.ss table/provider.ss program/evaluate.ss core/positive-plan.ss program/analysis.ss t/qualification/ascent-index-reference-funs.ss t/qualification/ascent-index-reference-provider.ss t/qualification/ascent-index-reference-evaluate.ss t/performance/index-lifecycle-benchmark.ss tools/build-index-lifecycle-benchmark.ss > "$ASCENT_INDEX_LIFECYCLE_RECEIPT.sources"
    timeout 150s gxi {{ gerbil_test_runtime_options }} tools/build-index-lifecycle-benchmark.ss
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    log="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/run.XXXXXX")"
    trap 'rm -f "$log"' EXIT
    GERBIL_LOADPATH="$ASCENT_INDEX_LIFECYCLE_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 30s gxi {{ gerbil_test_runtime_options }} t/performance/index-lifecycle/module-resolution.ss > "$ASCENT_INDEX_LIFECYCLE_RECEIPT.modules"
    test "$(grep -c '/.gerbil/index-lifecycle/lib/.*\.ssi$' "$ASCENT_INDEX_LIFECYCLE_RECEIPT.modules")" -eq 5
    GERBIL_LOADPATH="$ASCENT_INDEX_LIFECYCLE_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s gxi {{ gerbil_test_runtime_options }} t/performance/index-lifecycle-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 7
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    grep -x 'OK' "$log" >/dev/null

result-benchmark:
    {{ test_runner }} run -- just _result-benchmark

_result-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export ASCENT_RESULT_LIB="{{ justfile_directory() }}/.gerbil/result-publication/lib"
    export ASCENT_RESULT_RECEIPT="${ASCENT_RESULT_RECEIPT:-{{ justfile_directory() }}/.gerbil/result-publication/receipt.sexp}"
    mkdir -p .gerbil/result-publication
    shasum -a 256 program/result.ss program/evaluate.ss core/positive-plan.ss program/analysis.ss table/access.ss table/funs.ss table/storage.ss t/qualification/ascent-result-reference-evaluate.ss t/performance/result-benchmark.ss tools/build-result-benchmark.ss > "$ASCENT_RESULT_RECEIPT.sources"
    timeout 150s gxi {{ gerbil_test_runtime_options }} tools/build-result-benchmark.ss
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    log="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/run.XXXXXX")"
    trap 'rm -f "$log"' EXIT
    GERBIL_LOADPATH="$ASCENT_RESULT_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 30s gxi {{ gerbil_test_runtime_options }} t/performance/result-publication/module-resolution.ss > "$ASCENT_RESULT_RECEIPT.modules"
    test "$(grep -c '/.gerbil/result-publication/lib/.*\.ssi$' "$ASCENT_RESULT_RECEIPT.modules")" -eq 3
    GERBIL_LOADPATH="$ASCENT_RESULT_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s gxi {{ gerbil_test_runtime_options }} t/performance/result-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 10
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    grep -x 'OK' "$log" >/dev/null

# Matched finite temporal metadata cost; no speedup claim or added threshold.
temporal-scale:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-temporal-scale-output.ss

# Visible import progress for the composed temporal proof dependency graph.
test-temporal:
    {{ test_runner }} test-file t/qualification/ascent-temporal-lens-test.ss

_test-temporal:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    log="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/run.XXXXXX")"
    trap 'rm -f "$log"' EXIT
    test_module="${ASCENT_TEST_LIBRARY:+$ASCENT_TEST_LIBRARY/gerbil-ascent/}t/qualification/ascent-temporal-lens-test${ASCENT_TEST_LIBRARY:+.ssi}"
    if [[ -z "${ASCENT_TEST_LIBRARY:-}" ]]; then test_module="$test_module.ss"; fi
    ASCENT_TEMPORAL_TEST_MODULE="$test_module" GERBIL_LOADPATH="${ASCENT_TEST_LIBRARY:+$ASCENT_TEST_LIBRARY:}{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 120s gxi {{ gerbil_test_runtime_options }} t/harness/temporal-test.ss 2>&1 | tee "$log"
    if grep -E 'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    awk -f "{{ justfile_directory() }}/tools/assert-test-cases.awk" "$log"
    grep -Fx "MODULE-OK $test_module" "$log" >/dev/null
    grep -F 'HARNESS-OK' "$log" >/dev/null
    grep -x 'OK' "$log" >/dev/null
    if [[ -n "${ASCENT_TEST_LIBRARY:-}" ]]; then grep -Fx 'NATIVE-MODULES-OK' "$log" >/dev/null; fi

# Compile outside the runtime gate; std/make checks current source dependencies.
build-dsl-closure:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .cache/ascent/tmp
    export ASCENT_DSL_BUILD_TOKEN="$(mktemp .cache/ascent/tmp/build-owner.XXXXXX)"
    trap 'rm -f "$ASCENT_DSL_BUILD_TOKEN"' EXIT
    export ASCENT_DSL_BUILD_STARTED="$(date +%s)"
    export GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}"
    compiler=(gerbil env gxi)
    if [[ -n "${GERBIL_PATH:-}" ]]; then
        # The captured package environment is already explicit. Match gxpkg's
        # public env-exec PATH setup without starting its package CLI again.
        export PATH="$GERBIL_PATH/bin:$PATH"
        compiler=(gxi)
    fi
    PYTHONPATH="{{ justfile_directory() }}/python/src" python3 -m ascent_test_support.supervision --cpu-progress --startup-seconds 60 --idle-seconds 60 -- bash -e -c '"$@" {{ gerbil_test_runtime_options }} t/harness/run.ss build-dsl-closure; gxi t/harness/artifact.ss finalize' build-dsl-closure "${compiler[@]}"

# Counterbalanced measurements with independent Scheme truth; no speed threshold.
check-retained-benefit:
    #!/usr/bin/env bash
    set -euo pipefail
    gxi t/harness/artifact.ss check
    PYTHONPATH="{{ justfile_directory() }}/python/src" python3 -m ascent_test_support.supervision -- timeout 120s .cache/ascent/native-library/dsl-closure {{ gerbil_test_runtime_options }} --retained-benefit

# Run the known Suites through std/test in serial AOT processes with strict progress.
check-dsl-closure:
    #!/usr/bin/env bash
    set -euo pipefail
    gxi t/harness/artifact.ss check
    test -x .cache/ascent/native-library/dsl-closure
    mkdir -p .cache/ascent/tmp
    output_file="$(mktemp .cache/ascent/tmp/dsl.XXXXXX)"
    trap 'rm -f "$output_file"' EXIT
    for module in scheme-closure-contract scheme-artifact scheme-provenance-graph scheme-higher-order ascent-index-lifecycle scheme-finite-mapping scheme-session-deletion ascent-timeout scheme-stratified-provenance scheme-model-closure scheme-operator scheme-library-contract scheme-operator-retained ascent-finite-evidence ascent-positive-nonmembership; do
        PYTHONPATH="{{ justfile_directory() }}/python/src" python3 -m ascent_test_support.supervision -- timeout "${ASCENT_GXTEST_TIMEOUT:-120s}" .cache/ascent/native-library/dsl-closure {{ gerbil_test_runtime_options }} "t/qualification/$module-test.ss" 2>&1 | tee -a "$output_file"
    done
    if grep -E 'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi
    awk -f tools/assert-test-cases.awk "$output_file"
    test "$(grep -c '^MODULE-OK ' "$output_file")" -eq 15
    test "$(grep -c '^HARNESS-OK ' "$output_file")" -eq 15
    test "$(grep -cx 'OK' "$output_file")" -eq 15

# Unbounded Session protocol with configurable finite TLC exploration.
check-actor-session-formal:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "${TLC_BIN:-}" ]]; then tlc=("$TLC_BIN"); else tlc=(java -XX:+UseParallelGC -cp "${TLC_JAR:-.cache/ascent/tools/tla2tools-v1.7.4.jar}" tlc2.TLC); fi
    temp=$(mktemp -d)
    trap 'rm -rf "$temp"' EXIT
    generations="${ASCENT_SESSION_TLC_GENERATION_CUTOFF:-4}"
    [[ "$generations" =~ ^[0-9]+$ && "$generations" -ge 3 ]]
    sed "s/TLCGenerationCutoff = [0-9][0-9]*/TLCGenerationCutoff = $generations/" packages/proofs/tla/ActorSession.cfg > "$temp/normal.cfg"
    "${tlc[@]}" -workers 1 -config "$temp/normal.cfg" -metadir "$temp/normal" packages/proofs/tla/ActorSession.tla
    for mutation in stale early; do
      sed "s/Mutation = \"none\"/Mutation = \"$mutation\"/" "$temp/normal.cfg" > "$temp/$mutation.cfg"
      code=0
      "${tlc[@]}" -workers 1 -config "$temp/$mutation.cfg" -metadir "$temp/$mutation" packages/proofs/tla/ActorSession.tla > "$temp/$mutation.out" 2>&1 || code=$?
      if [[ "$mutation" = stale ]]; then invariant=NoStalePublication; else invariant=DrainedClose; fi
      [[ "$code" = 12 ]] && grep -q "Invariant $invariant is violated" "$temp/$mutation.out"
      echo "COUNTEREXAMPLE-OK actor-session-$mutation $invariant"
    done
    echo 'ACTOR-SESSION-CHECK-OK'

check-ready-components-formal:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "${TLC_BIN:-}" ]]; then tlc=("$TLC_BIN"); else tlc=(java -XX:+UseParallelGC -cp "${TLC_JAR:-.cache/ascent/tools/tla2tools-v1.7.4.jar}" tlc2.TLC); fi
    temp=$(mktemp -d)
    trap 'rm -rf "$temp"' EXIT
    for capacity in 1 2 3; do
      sed "s/Capacity = 2/Capacity = $capacity/" packages/proofs/tla/ReadyComponents.cfg > "$temp/$capacity.cfg"
      "${tlc[@]}" -workers 1 -config "$temp/$capacity.cfg" -metadir "$temp/$capacity" packages/proofs/tla/ReadyComponents.tla
    done
    for mutation in prerequisite early snapshot tail credit; do
      sed "s/Mutation = \"none\"/Mutation = \"$mutation\"/" packages/proofs/tla/ReadyComponents.cfg > "$temp/$mutation.cfg"
      code=0
      "${tlc[@]}" -workers 1 -config "$temp/$mutation.cfg" -metadir "$temp/$mutation" packages/proofs/tla/ReadyComponents.tla > "$temp/$mutation.out" 2>&1 || code=$?
      invariant=CompletedDelivery
      if [[ "$mutation" = prerequisite ]]; then invariant=Prerequisites; fi
      if [[ "$mutation" = early ]]; then invariant=CompleteReturn; fi
      if [[ "$mutation" = snapshot ]]; then invariant=DependencySnapshot; fi
      [[ "$code" = 12 ]] && grep -q "Invariant $invariant is violated" "$temp/$mutation.out"
      echo "COUNTEREXAMPLE-OK ready-components-$mutation $invariant"
    done
    echo 'READY-COMPONENTS-CHECK-OK'

check-component-index-formal:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "${TLC_BIN:-}" ]]; then tlc=("$TLC_BIN"); else tlc=(java -XX:+UseParallelGC -cp "${TLC_JAR:-.cache/ascent/tools/tla2tools-v1.7.4.jar}" tlc2.TLC); fi
    temp=$(mktemp -d)
    trap 'rm -rf "$temp"' EXIT
    "${tlc[@]}" -workers 1 -config packages/proofs/tla/ComponentIndex.cfg -metadir "$temp/correct" packages/proofs/tla/ComponentIndex.tla
    for mutation in order early failed alias foreign; do
      sed "s/Mutation = \"none\"/Mutation = \"$mutation\"/" packages/proofs/tla/ComponentIndex.cfg > "$temp/$mutation.cfg"
      code=0
      "${tlc[@]}" -workers 1 -config "$temp/$mutation.cfg" -metadir "$temp/$mutation" packages/proofs/tla/ComponentIndex.tla > "$temp/$mutation.out" 2>&1 || code=$?
      [[ "$code" = 12 ]] && grep -q 'Invariant Consistent is violated' "$temp/$mutation.out"
      echo "COUNTEREXAMPLE-OK component-index-$mutation Consistent"
    done
    echo 'COMPONENT-INDEX-CHECK-OK'

# BYODS concrete frontier coverage and consumer visibility; finite eqrel model.
check-provider-frontier-formal:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "${TLC_BIN:-}" ]]; then tlc=("$TLC_BIN"); else tlc=(java -XX:+UseParallelGC -cp "${TLC_JAR:-.cache/ascent/tools/tla2tools-v1.7.4.jar}" tlc2.TLC); fi
    temp=$(mktemp -d)
    trap 'rm -rf "$temp"' EXIT
    "${tlc[@]}" -workers 1 -config packages/proofs/tla/ProviderFrontier.cfg -metadir "$temp/good" packages/proofs/tla/ProviderFrontier.tla
    sed 's/InitialInputs = {}/InitialInputs <- SeededInputs/' packages/proofs/tla/ProviderFrontier.cfg > "$temp/seeded.cfg"
    "${tlc[@]}" -workers 1 -config "$temp/seeded.cfg" -metadir "$temp/seeded" packages/proofs/tla/ProviderFrontier.tla
    sed 's/Mutation = "none"/Mutation = "overlap"/' packages/proofs/tla/ProviderFrontier.cfg > "$temp/overlap.cfg"
    "${tlc[@]}" -workers 1 -config "$temp/overlap.cfg" -metadir "$temp/overlap" packages/proofs/tla/ProviderFrontier.tla
    for mutation in raw foreign omit early old initial; do
      sed "s/Mutation = \"none\"/Mutation = \"$mutation\"/" packages/proofs/tla/ProviderFrontier.cfg > "$temp/$mutation.cfg"
      if [[ "$mutation" == initial ]]; then
        sed 's/InitialInputs = {}/InitialInputs <- SeededInputs/' "$temp/$mutation.cfg" > "$temp/initial-seeded.cfg"
        mv "$temp/initial-seeded.cfg" "$temp/$mutation.cfg"
      fi
      code=0
      "${tlc[@]}" -workers 1 -config "$temp/$mutation.cfg" -metadir "$temp/$mutation" packages/proofs/tla/ProviderFrontier.tla > "$temp/$mutation.out" 2>&1 || code=$?
      invariant=FrontierComplete
      if [[ "$mutation" == omit ]]; then invariant=DeliveredExact; fi
      if [[ "$mutation" == early || "$mutation" == old || "$mutation" == initial ]]; then invariant=ConsumerSnapshot; fi
      [[ "$code" = 12 ]] && grep -q "Invariant $invariant is violated" "$temp/$mutation.out"
      echo "COUNTEREXAMPLE-OK provider-frontier-$mutation $invariant"
    done
    echo 'PROVIDER-FRONTIER-CHECK-OK'

# SCC union-find insertion/remapping and refusal, with discriminating mutations.
check-transitive-components-formal:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "${TLC_BIN:-}" ]]; then tlc=("$TLC_BIN"); else tlc=(java -XX:+UseParallelGC -cp "${TLC_JAR:-.cache/ascent/tools/tla2tools-v1.7.4.jar}" tlc2.TLC); fi
    temp=$(mktemp -d)
    trap 'rm -rf "$temp"' EXIT
    "${tlc[@]}" -workers 1 -config packages/proofs/tla/TransitiveComponents.cfg -metadir "$temp/good" packages/proofs/tla/TransitiveComponents.tla
    for mutation in split stale reject; do
      invariant=SCCExact
      if [[ "$mutation" == stale ]]; then invariant=ReachExact; fi
      if [[ "$mutation" == reject ]]; then invariant=RefusalAtomic; fi
      sed -e "s/Mutation = \"none\"/Mutation = \"$mutation\"/" -e "s/INVARIANTS .*/INVARIANTS $invariant/" packages/proofs/tla/TransitiveComponents.cfg > "$temp/$mutation.cfg"
      code=0
      "${tlc[@]}" -workers 1 -config "$temp/$mutation.cfg" -metadir "$temp/$mutation" packages/proofs/tla/TransitiveComponents.tla > "$temp/$mutation.out" 2>&1 || code=$?
      [[ "$code" = 12 ]] && grep -q "Invariant $invariant is violated" "$temp/$mutation.out"
      echo "COUNTEREXAMPLE-OK transitive-components-$mutation $invariant"
    done
    echo 'TRANSITIVE-COMPONENTS-CHECK-OK'

# Frozen BYODS relation views: lifetime, publication and logical budgets.
check-provider-views-formal:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "${TLC_BIN:-}" ]]; then tlc=("$TLC_BIN"); else tlc=(java -XX:+UseParallelGC -Xmx1g -cp "${TLC_JAR:-.cache/ascent/tools/tla2tools-v1.7.4.jar}" tlc2.TLC); fi
    temp=$(mktemp -d)
    trap 'rm -rf "$temp"' EXIT
    cutoff="${ASCENT_TLC_GENERATION_CUTOFF:-3}"
    [[ "$cutoff" =~ ^[0-9]+$ ]] || { echo 'Invalid TLC exploration bound' >&2; exit 2; }
    sed "s/ExplorationBound = [0-9][0-9]*/ExplorationBound = $cutoff/" packages/proofs/tla/ProviderViews.cfg > "$temp/base.cfg"
    echo "TLA-CHECK ProviderViews exploration-bound=$cutoff (TLC enumeration only)"
    "${tlc[@]}" -workers 1 -config "$temp/base.cfg" -metadir "$temp/good" packages/proofs/tla/ProviderViews.tla
    for mutation in alias retire early stale budget; do
      case "$mutation" in
        alias) invariant=FrozenRead ;;
        retire) invariant=ReaderAlive ;;
        early) invariant=AtomicPublication ;;
        stale) invariant=CurrentReply ;;
        budget) invariant=LogicalBudget ;;
      esac
      sed -e "s/Mutation = \"none\"/Mutation = \"$mutation\"/" -e "s/INVARIANTS .*/INVARIANTS $invariant/" "$temp/base.cfg" > "$temp/$mutation.cfg"
      code=0
      "${tlc[@]}" -workers 1 -config "$temp/$mutation.cfg" -metadir "$temp/$mutation" packages/proofs/tla/ProviderViews.tla > "$temp/$mutation.out" 2>&1 || code=$?
      [[ "$code" = 12 ]] && grep -q "Invariant $invariant is violated" "$temp/$mutation.out"
      echo "COUNTEREXAMPLE-OK provider-views-$mutation $invariant"
    done
    cp packages/proofs/tla/ReaderLifetime.cfg "$temp/live.cfg"
    "${tlc[@]}" -workers 1 -config "$temp/live.cfg" -metadir "$temp/live" packages/proofs/tla/ReaderLifetime.tla
    for mutation in stuck unfair; do
      sed "s/Mutation = \"none\"/Mutation = \"$mutation\"/" "$temp/live.cfg" > "$temp/$mutation.cfg"
      code=0
      "${tlc[@]}" -workers 1 -config "$temp/$mutation.cfg" -metadir "$temp/$mutation" packages/proofs/tla/ReaderLifetime.tla > "$temp/$mutation.out" 2>&1 || code=$?
      if [[ "$code" != 13 ]] || ! grep -q 'Temporal properties were violated' "$temp/$mutation.out"; then
        cat "$temp/$mutation.out"
        exit 1
      fi
      echo "COUNTEREXAMPLE-OK provider-views-$mutation ReaderCompletion exit=$code"
    done
    echo 'PROVIDER-VIEWS-CHECK-OK'
