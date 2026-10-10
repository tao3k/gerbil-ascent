# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

set shell := ["bash", "-euo", "pipefail", "-c"]

# Match the repository's mrr-gerbil environment boundary. Homebrew's configured
# compiler must not inherit Nix compiler flags or its macOS SDK. Resolve the
# active Homebrew OpenSSL library after clearing inherited search paths; Gerbil
# release metadata can retain a removed Cellar directory after a formula upgrade.
gerbil_environment := if os() == "macos" {
    "env -u CC -u CFLAGS -u CPPFLAGS -u LDFLAGS -u CPATH -u C_INCLUDE_PATH -u CPLUS_INCLUDE_PATH -u LIBRARY_PATH -u NIX_CFLAGS_COMPILE -u NIX_LDFLAGS -u DEVELOPER_DIR -u SDKROOT LIBRARY_PATH=\"$(brew --prefix openssl@3)/lib\""
} else { "env" }
gerbil_command := gerbil_environment + " gerbil"
# gxpkg env only selects the package prefix and prepends its bin directory.
# The captured environment already fixes the toolchain; apply that boundary
# directly instead of importing the package-management CLI for every script.
gerbil_package_prefix := '${GERBIL_PATH:-' + justfile_directory() + '/.gerbil}'
gxi_command := gerbil_environment + ' GERBIL_PATH="' + gerbil_package_prefix + '" PATH="' + gerbil_package_prefix + '/bin:$PATH" gxi'

# Production, tests and AOT objects share the standard package library.
package_library := gerbil_package_prefix + '/lib'

gerbil_test_runtime_options := "-:max-heap=1G,debug=q"
test_library_environment := 'GERBIL_PATH="' + gerbil_package_prefix + '" ASCENT_TEST_LIBRARY="' + gerbil_package_prefix + '/lib" ASCENT_PERFORMANCE_MODULES="' + justfile_directory() + '/.cache/ascent/native-library/modules.sexp" GERBIL_LOADPATH="' + gerbil_package_prefix + '/lib:' + justfile_directory() + '${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" '
quint_backend_sha256 := "880c0b2b72354816f12e9a9755829f2907071e9a181ffea1937954c23d54739d"

default:
    @just --list

build:
    GERBIL_BUILD_CORES="${GERBIL_BUILD_CORES:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || getconf NPROCESSORS_ONLN)}" {{ gerbil_command }} build

check-policy:
    ASP_GERBIL_SCHEME_POLICY=1 GERBIL_BUILD_CORES="${GERBIL_BUILD_CORES:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || getconf NPROCESSORS_ONLN)}" {{ gerbil_command }} build

# Runtime source loading is a separate gate from compiled native qualification.
check-source-views:
    just _check-source-views

_check-source-views:
    @GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" {{ gxi_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-source-view-output.ss

test-file path heap='2G':
    just _test-file "{{ path }}" "{{ heap }}"

# Gerbil owns ordinary discovery and Case execution; this recipe checks its verdict.
_test-file path heap='2G':
    #!/usr/bin/env bash
    set -euo pipefail
    test -e "{{ path }}"
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    output_file="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/case.XXXXXX")"
    trap 'rm -f "$output_file"' EXIT
    started=$SECONDS
    printf '[ascent-test] START %s\n' "{{ path }}"
    export GERBIL_PATH="{{ gerbil_package_prefix }}"
    export GERBIL_LOADPATH="${ASCENT_TEST_LIBRARY:+$ASCENT_TEST_LIBRARY:}${GERBIL_LOADPATH:+$GERBIL_LOADPATH:}{{ justfile_directory() }}"
    test_module="{{ path }}"
    if [[ -n "${ASCENT_TEST_LIBRARY:-}" ]]; then
        compiled="$ASCENT_TEST_LIBRARY/gerbil-ascent/${test_module%.ss}.ssi"
        test -f "$compiled"
        test_module="$compiled"
        runner=({{ gxi_command }} {{ gerbil_test_runtime_options }} :gerbil/tools/gxtest)
    else
        runner=({{ gerbil_command }} -:max-heap={{ heap }},debug=q test)
    fi
    timeout "${ASCENT_GXTEST_TIMEOUT:-120s}" "${runner[@]}" -v 5 "$test_module" 2>&1 | tee "$output_file"
    if grep -E 'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi
    awk -f "{{ justfile_directory() }}/tools/assert-test-cases.awk" "$output_file"
    if [[ -d "$test_module" ]]; then grep -F 'MODULE-OK ' "$output_file" >/dev/null; else grep -Fx "MODULE-OK $test_module" "$output_file" >/dev/null; fi
    grep -F 'HARNESS-OK' "$output_file" >/dev/null
    grep -x 'OK' "$output_file" >/dev/null
    printf '[ascent-test] PASS %s (%ss)\n' "{{ path }}" "$((SECONDS - started))"

# Ordinary test discovery and execution belong to Gerbil.
test heap='2G':
    ASCENT_GXTEST_TIMEOUT="${ASCENT_GXTEST_TIMEOUT:-180s}" just test-file t/qualification "{{ heap }}"

# One compiler invocation; upstream make owns threads, ordering and currentness.
prepare-test-library:
    {{ gxi_command }} -:max-heap=3G,debug=q tools/build-test-library.ss library

# Native performance Suites use the declared Gerbil testing isolation profile.
test-performance-contracts: prepare-test-library
    #!/usr/bin/env bash
    set -euo pipefail
    output="$(mktemp)"
    trap 'rm -f "$output"' EXIT
    library="{{ package_library }}/gerbil-ascent/t/performance"
    modules=()
    for name in ascent-withdrawal-support-performance ascent-change-plan-performance ascent-source-cut-allocation ascent-component-index-performance ascent-actor-credit-performance ascent-trrel-uf-performance ascent-steensgaard-performance ascent-relation-view-performance scheme-library-lifecycle-performance; do
        modules+=("$library/$name-test.ssi")
    done
    {{ test_library_environment }} timeout "${ASCENT_GXTEST_TIMEOUT:-120s}" {{ gxi_command }} -:max-heap=2G,debug=q tools/test-performance-contracts.ss "${modules[@]}" 2>&1 | tee "$output"
    if grep -E 'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow' "$output" >/dev/null; then exit 1; fi
    awk -f tools/assert-test-cases.awk "$output"
    test "$(grep -c '^MODULE-OK ' "$output")" -eq "${#modules[@]}"
    grep -F 'HARNESS-OK' "$output" >/dev/null
    grep -x 'OK' "$output" >/dev/null

# Paired actor source transactions; evaluator work is outside this interval.
performance-source-cut: prepare-test-library
    {{ test_library_environment }} just _performance-source-cut

_performance-source-cut:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .cache/ascent/source-cut
    {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' -e '(import :std/make)' -e '(make ["program/source-cut" "t/performance/source-cut-benchmark"] srcdir: (current-directory) libdir: (path-expand "lib" (getenv "GERBIL_PATH")) build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in untouched wide-batch small; do
        timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' :gerbil-ascent/t/performance/source-cut-benchmark "$scenario" ".cache/ascent/source-cut/$scenario-final.sexp"
    done

# Paired complete actor rounds with wide ready queues and active assignments.
performance-actor-admission baseline='admission' lane='qualification': prepare-test-library
    {{ test_library_environment }} just _performance-actor-admission "{{ baseline }}" "{{ lane }}"

_performance-actor-admission baseline lane:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    [[ "{{ baseline }}" = admission || "{{ baseline }}" = coordinator ]]
    receipt_dir=".cache/ascent/actor-{{ baseline }}"
    mkdir -p "$receipt_dir" .cache/ascent/actor-admission
    {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/actor-admission-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/actor-admission/native-entry"
    [[ "{{ lane }}" = qualification || "{{ lane }}" = stream ]]
    scenarios=(wide backlog small)
    if [[ "{{ lane }}" = stream ]]; then scenarios=(stream); fi
    for scenario in "${scenarios[@]}"; do
        timeout 90s .cache/ascent/actor-admission/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" "$receipt_dir/$scenario.sexp" "{{ baseline }}"
    done

# Matched physical index build, extension and lookup with projection controls.
performance-index-projection: prepare-test-library
    {{ test_library_environment }} just _performance-index-projection

_performance-index-projection:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/index-projection
    {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/index-projection-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/index-projection/native-entry"
    for scenario in wide compact fallback small; do
        timeout 90s .cache/ascent/index-projection/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/index-projection/$scenario.sexp"
    done

# Complete fresh-engine expression execution, matched natively.
performance-expression-plan: prepare-test-library
    {{ test_library_environment }} just _performance-expression-plan

_performance-expression-plan:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/expression-plan
    {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/expression-plan-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/expression-plan/native-entry"
    status=0
    for scenario in lower-deep lower-scope lower-small lower-pure lower-pure-wide deep scope chain wide pure small; do
        timeout 90s .cache/ascent/expression-plan/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/expression-plan/$scenario.sexp" || status=1
    done
    exit "$status"

# Complete positive proof production and independent replay, matched natively.
performance-proof-replay: prepare-test-library
    {{ test_library_environment }} just _performance-proof-replay

_performance-proof-replay:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/proof-replay
    {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/proof-replay-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/proof-replay/native-entry"
    for scenario in copy duplicate source small; do
        timeout 90s .cache/ascent/proof-replay/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/proof-replay/$scenario.sexp"
    done

# Cold typed-expression compilation with matched native semantic checks.
performance-typed-domain: prepare-test-library
    {{ test_library_environment }} just _performance-typed-domain

_performance-typed-domain:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/typed-domain
    {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/typed-domain-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/typed-domain/native-entry"
    for scenario in ordered permuted small; do
        timeout 90s .cache/ascent/typed-domain/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/typed-domain/$scenario.sexp"
    done

# Matched complete independent absence verification using the public ASP API.
performance-nonmembership-index: prepare-test-library
    {{ test_library_environment }} just _performance-nonmembership-index

_performance-nonmembership-index:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/nonmembership-index
    {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/nonmembership-index-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/nonmembership-index/native-entry"
    for scenario in wide uncovered small; do
        timeout 90s .cache/ascent/nonmembership-index/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/nonmembership-index/$scenario.sexp"
    done

# Matched complete temporal projection through the public ASP benchmark API.
performance-temporal-projection: prepare-test-library
    {{ test_library_environment }} just _performance-temporal-projection

_performance-temporal-projection:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/temporal-projection
    {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/temporal-projection-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/temporal-projection/native-entry"
    for scenario in chain fan complete empty; do
        timeout 90s .cache/ascent/temporal-projection/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/temporal-projection/$scenario.sexp"
    done

# Matched SCC commit and complete construction control through ASP benchmarks.
performance-uf-commit: prepare-test-library
    {{ test_library_environment }} just _performance-uf-commit

_performance-uf-commit:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/uf-commit
    {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/uf-commit-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/uf-commit/native-entry"
    for scenario in partial cycle lifecycle dag duplicate islands; do
        timeout 90s .cache/ascent/uf-commit/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/uf-commit/$scenario.sexp"
    done

# Matched cold slot compilation and native traversal with shape controls.
performance-slot-projection: prepare-test-library
    {{ test_library_environment }} just _performance-slot-projection

_performance-slot-projection:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/slot-projection
    {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/slot-projection-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/slot-projection/native-entry"
    for scenario in sparse reverse repeat full below-boundary boundary small empty single; do
        timeout 90s .cache/ascent/slot-projection/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/slot-projection/$scenario.sexp"
    done

# Matched full proof production, replay and checker with source controls.
performance-stratified-model: prepare-test-library
    {{ test_library_environment }} just _performance-stratified-model

_performance-stratified-model:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/stratified-model
    {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/stratified-model-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/stratified-model/native-entry"
    for scenario in source derived relations duplicates small; do
        timeout 90s .cache/ascent/stratified-model/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/stratified-model/$scenario.sexp"
    done

# Matched complete operator compilation with shared lexical dependencies.
performance-operator-scope: prepare-test-library
    {{ test_library_environment }} just _performance-operator-scope

_performance-operator-scope:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/operator-scope
    {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/operator-scope-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/operator-scope/native-entry"
    for scenario in scaled-diamond small; do
        timeout 90s .cache/ascent/operator-scope/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/operator-scope/$scenario.sexp"
    done

# Grounded provenance maintenance with independent frozen semantics.
performance-provenance-maintenance: prepare-test-library
    {{ test_library_environment }} just _performance-provenance-maintenance

_performance-provenance-maintenance:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/provenance-maintenance
    {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/provenance-maintenance-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/provenance-maintenance/native-entry"
    for scenario in wide duplicates read small; do
        timeout 90s .cache/ascent/provenance-maintenance/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/provenance-maintenance/$scenario.sexp"
    done

performance-component-workspace: prepare-test-library
    {{ test_library_environment }} just _performance-component-workspace

_performance-component-workspace:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/component-workspace
    {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/component-workspace-build.ss "$library" "{{ justfile_directory() }}/.cache/ascent/component-workspace/native-entry"
    for scenario in scan recursive indexed small; do
        timeout 90s .cache/ascent/component-workspace/native-entry {{ gerbil_test_runtime_options }} "$scenario" "$library" ".cache/ascent/component-workspace/$scenario.sexp"
    done

performance-component-scope: prepare-test-library
    {{ test_library_environment }} just _performance-component-scope

_performance-component-scope:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/component-scope
    {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' -e '(import :std/make)' -e '(make ["program/component-plan" "program/component-worker" "program/positive-components" "program/evaluate" "t/performance/component-scope/reference" "t/performance/component-scope/fixture" "t/performance/component-scope-benchmark"] srcdir: (current-directory) libdir: (path-expand "lib" (getenv "GERBIL_PATH")) build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in sparse-plan multihead-plan closure-one closure-four small; do
        timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' :gerbil-ascent/t/performance/component-scope-benchmark "$scenario" "$library" ".cache/ascent/component-scope/$scenario.sexp"
    done

# Paired strict-dependency admission and complete cold/warm public solves.
performance-strata-preflight: prepare-test-library
    {{ test_library_environment }} just _performance-strata-preflight

_performance-strata-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/strata-preflight
    {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' -e '(import :std/make)' -e '(make ["core/rule-semantics" "program/actor-round" "program/positive-components" "program/planning" "program/evaluate" "t/performance/strata-preflight/reference-semantics" "t/performance/strata-preflight/reference-planning" "t/performance/strata-preflight/reference-evaluate" "t/performance/strata-preflight/fixture" "t/performance/strata-preflight-benchmark"] srcdir: (current-directory) libdir: (path-expand "lib" (getenv "GERBIL_PATH")) build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in positive negation aggregate lattice cold warm small; do
        timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' :gerbil-ascent/t/performance/strata-preflight-benchmark "$scenario" "$library" ".cache/ascent/strata-preflight/$scenario.sexp"
    done

# Paired ordered index build/extension/lookup and complete native solve control.
performance-index-build: prepare-test-library
    {{ test_library_environment }} just _performance-index-build

_performance-index-build:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/index-build
    {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' -e '(import :std/make)' -e '(make ["table/funs" "table/access" "program/index" "program/evaluate" "t/performance/index-build/reference-funs" "t/performance/index-build/reference-access" "t/performance/index-build/reference-index" "t/performance/index-build/reference-evaluate" "t/performance/index-build/fixture" "t/performance/index-build-benchmark"] srcdir: (current-directory) libdir: (path-expand "lib" (getenv "GERBIL_PATH")) build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in scalar-dense scalar-unique composite-dense composite-unique empty small solve; do
        timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' :gerbil-ascent/t/performance/index-build-benchmark "$scenario" "$library" ".cache/ascent/index-build/$scenario.sexp"
    done

# Paired persistent source-log kernels and complete public source transactions.
performance-source-log: prepare-test-library
    {{ test_library_environment }} just _performance-source-log

_performance-source-log:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/source-log
    {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' -e '(import :std/make)' -e '(make ["core/positive-plan" "program/actor-round" "program/source-log" "program/evaluate" "program/session" "t/performance/source-log/reference-update-selection" "t/performance/source-log/reference-reuse" "t/performance/source-log/reference-evaluate" "t/performance/source-log/reference-session" "t/performance/source-log/fixture" "t/performance/source-log-benchmark"] srcdir: (current-directory) libdir: (path-expand "lib" (getenv "GERBIL_PATH")) build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in join equal pending mismatch update appended-update small; do
        timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' :gerbil-ascent/t/performance/source-log-benchmark "$scenario" "$library" ".cache/ascent/source-log/$scenario.sexp"
    done

# Paired native selected frames and complete dependency updates/append lifecycle.
performance-selected-activation: prepare-test-library
    {{ test_library_environment }} just _performance-selected-activation

_performance-selected-activation:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/selected-activation
    {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' -e '(import :std/make)' -e '(make ["program/activation" "program/update-selection" "program/reuse" "program/evaluate" "t/performance/selected-activation/reference-selection" "t/performance/selected-activation/reference-reuse" "t/performance/selected-activation/reference-evaluate" "t/performance/selected-activation/fixture" "t/performance/selected-activation-benchmark"] srcdir: (current-directory) libdir: (path-expand "lib" (getenv "GERBIL_PATH")) build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in sparse partial all update lifecycle small; do
        timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' :gerbil-ascent/t/performance/selected-activation-benchmark "$scenario" "$library" ".cache/ascent/selected-activation/$scenario.sexp"
    done

# Paired native storage batch preflight and complete retained-engine updates.
performance-storage-batch: prepare-test-library
    {{ test_library_environment }} just _performance-storage-batch

_performance-storage-batch:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/storage-batch
    {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' -e '(import :std/make)' -e '(make ["program/admission" "program/evaluate" "t/performance/storage-batch/reference" "t/performance/storage-batch/reference-evaluate" "t/performance/storage-batch/fixture" "t/performance/storage-batch-benchmark"] srcdir: (current-directory) libdir: (path-expand "lib" (getenv "GERBIL_PATH")) build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in batch wide duplicates engine single empty engine-small; do
        timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' :gerbil-ascent/t/performance/storage-batch-benchmark "$scenario" "$library" ".cache/ascent/storage-batch/$scenario.sexp"
    done

# Paired native curried index build, extension and prefix/full reads.
performance-index-sharing: prepare-test-library
    {{ test_library_environment }} just _performance-index-sharing

_performance-index-sharing:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    directory="{{ justfile_directory() }}/.cache/ascent/index-sharing"
    mkdir -p "$directory"
    {{ gxi_command }} {{ gerbil_test_runtime_options }} :gerbil-ascent/t/performance/index-sharing-build "$library" "$directory/benchmark"
    for scenario in wide sparse small scalar empty; do
        timeout 90s "$directory/benchmark" {{ gerbil_test_runtime_options }} "$scenario" "$library" "$directory/$scenario.sexp"
    done

# Paired native engine-owned physical index entries and complete indexed solves.
performance-index-entry: prepare-test-library
    {{ test_library_environment }} just _performance-index-entry

_performance-index-entry:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/index-entry
    {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' -e '(import :std/make)' -e '(make ["program/index" "program/evaluate" "t/performance/index-entry/reference" "t/performance/index-entry/reference-evaluate" "t/performance/index-entry/fixture" "t/performance/index-entry-benchmark"] srcdir: (current-directory) libdir: (path-expand "lib" (getenv "GERBIL_PATH")) build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in all delta advance scalar cold solve-wide solve-small; do
        timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' :gerbil-ascent/t/performance/index-entry-benchmark "$scenario" "$library" ".cache/ascent/index-entry/$scenario.sexp"
    done

# Paired native general callbacks, ordered pattern bindings and complete solves.
performance-rule-bindings: prepare-test-library
    {{ test_library_environment }} just _performance-rule-bindings

_performance-rule-bindings:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    mkdir -p .cache/ascent/rule-bindings
    {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' -e '(import :std/make)' -e '(make ["core/rule-bindings" "core/positive-plan" "program/evaluate" "t/performance/rule-bindings/reference" "t/performance/rule-bindings/reference-positive" "t/performance/rule-bindings/reference-evaluate" "t/performance/rule-bindings/fixture" "t/performance/rule-bindings-benchmark"] srcdir: (current-directory) libdir: (path-expand "lib" (getenv "GERBIL_PATH")) build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in call-two call-six bind-wide guards patterns small; do
        timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' :gerbil-ascent/t/performance/rule-bindings-benchmark "$scenario" "$library" ".cache/ascent/rule-bindings/$scenario.sexp"
    done

# Paired native finite evidence generation and verification.
performance-finite-replay: prepare-test-library
    {{ test_library_environment }} just _performance-finite-replay

_performance-finite-replay:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' -e '(import :std/make)' -e '(make ["candidate/funs" "candidate/finite-evidence" "candidate/types" "candidate/datum" "t/performance/finite-replay/reference-funs" "t/performance/finite-replay/reference" "t/performance/finite-replay-benchmark"] srcdir: (current-directory) libdir: (path-expand "lib" (getenv "GERBIL_PATH")) build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in wide duplicates small constant; do
        timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' :gerbil-ascent/t/performance/finite-replay-benchmark "$scenario" "$library"
    done

# Paired native inert traversal and complete certificate verification.
performance-bounded-datum: prepare-test-library
    {{ test_library_environment }} just _performance-bounded-datum

_performance-bounded-datum:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' -e '(import :std/make)' -e '(make ["candidate/datum" "candidate/types" "candidate/provenance" "candidate/provenance-graph" "t/performance/bounded-datum/reference" "t/performance/bounded-datum/reference-graph" "t/performance/bounded-datum-benchmark"] srcdir: (current-directory) libdir: (path-expand "lib" (getenv "GERBIL_PATH")) build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in kernel verifier; do
        timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' :gerbil-ascent/t/performance/bounded-datum-benchmark "$scenario" "$library"
    done

# Paired native complete-provenance generation.
performance-provenance-index: prepare-test-library
    {{ test_library_environment }} just _performance-provenance-index

_performance-provenance-index:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' -e '(import :std/make)' -e '(make ["candidate/provenance-graph" "t/performance/provenance-index/reference" "t/performance/provenance-index-benchmark"] srcdir: (current-directory) libdir: (path-expand "lib" (getenv "GERBIL_PATH")) build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in small wide duplicates; do
        timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' :gerbil-ascent/t/performance/provenance-index-benchmark "$scenario" "$library"
    done

# Paired native source-selection over compiled declaration dependencies.
performance-update-dependencies: prepare-test-library
    {{ test_library_environment }} just _performance-update-dependencies

_performance-update-dependencies:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' -e '(import :std/make)' -e '(make ["core/dependency-graph" "core/rule-semantics" "program/planning" "program/update-selection" "t/performance/update-dependencies/reference" "t/performance/update-dependencies-benchmark"] srcdir: (current-directory) libdir: (path-expand "lib" (getenv "GERBIL_PATH")) build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in chain-changed chain-unchanged wide-changed wide-unchanged; do
        timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' :gerbil-ascent/t/performance/update-dependencies-benchmark "$scenario" "$library"
    done

# Paired native index construction, extension and evaluated-key lookup.
performance-scalar-index: prepare-test-library
    {{ test_library_environment }} just _performance-scalar-index

_performance-scalar-index:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' -e '(import :std/make)' -e '(make ["table/funs" "table/access" "core/positive-plan" "program/index" "program/evaluate" "t/performance/scalar-index/reference-access" "t/performance/scalar-index-benchmark"] srcdir: (current-directory) libdir: (path-expand "lib" (getenv "GERBIL_PATH")) build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in single-first single-later composite-control tiny-control; do
        timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' :gerbil-ascent/t/performance/scalar-index-benchmark "$scenario" "$library"
    done

performance-finite-mapping: prepare-test-library
    {{ test_library_environment }} just _performance-finite-mapping

_performance-finite-mapping:
    #!/usr/bin/env bash
    set -euo pipefail
    library="{{ package_library }}"
    {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' -e '(import :std/make)' -e '(make ["table/provider" "table/storage" "table/access" "program/types" "program/objects" "program/scheme-checked" "program/index" "program/evaluate" "program/session" "program/update-selection" "t/performance/finite-mapping/reference-types" "t/performance/finite-mapping/reference-objects" "t/performance/finite-mapping/reference" "t/performance/finite-mapping-benchmark"] srcdir: (current-directory) libdir: (path-expand "lib" (getenv "GERBIL_PATH")) build-deps: (path-expand ".cache/ascent/native-library/build-deps"))'
    for scenario in narrow-rows wide-rows wide-view source-control canonical-provider; do
        timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} -e '(add-load-path! (path-expand "lib" (getenv "GERBIL_PATH")))' :gerbil-ascent/t/performance/finite-mapping-benchmark "$scenario" "$library"
    done

test-quick:
    just _test-quick

_test-quick:
    #!/usr/bin/env bash
    set -euo pipefail
    for path in t/qualification/ascent-{finite-evidence,positive-nonmembership,positive-provenance,reasoning-library,stratified-proof}-test.ss; do just test-file "$path"; done

small-graph-benchmark: prepare-test-library
    {{ test_library_environment }} just _small-graph-benchmark

_small-graph-benchmark:
    GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s {{ gerbil_command }} {{ gerbil_test_runtime_options }} env {{ gxi_command }} t/performance/small-graph-benchmark.ss

# Matched row-copy boundary costs. The probe checks equal rows and isolation
# after every sample; it does not time a complete retained-session solve.
admission-copy-benchmark: prepare-test-library
    {{ test_library_environment }} just _admission-copy-benchmark

_admission-copy-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    output_file="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/case.XXXXXX")"
    trap 'rm -f "$output_file"' EXIT
    export GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}"
    printf '[admission-copy] START three matched row-copy cases\n'
    timeout 180s {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/scheme-admission-copy-benchmark.ss 2>&1 | tee "$output_file"
    test "$(grep -c '^CASE ' "$output_file")" -eq 3
    test "$(grep -c '^WARM ' "$output_file")" -eq 6
    test "$(grep -c '^SAMPLE ' "$output_file")" -eq 48
    grep -x 'OK' "$output_file" >/dev/null
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi

# LeanPoo-backed ASCENT proof package. The Lake manifest fixes dependencies.
# Compare regenerated Quint observations and the frozen Scheme corpus with
# the executable Lean contract. Ordinary Gerbil tests consume the same corpus.
check-feedback-conformance: prepare-quint
    mkdir -p .cache/ascent/feedback-conformance
    .cache/ascent/tools/quint/node_modules/.bin/quint repl -q --backend typescript -r packages/proofs/quint/ExecutionFeedback.qnt::ExecutionFeedback conformance .exit > .cache/ascent/feedback-conformance/quint.json
    cd packages/proofs/lean && lake build FeedbackConformance && lake env lean --run FeedbackConformance.lean ../../../.cache/ascent/feedback-conformance/quint.json ../../../t/qualification/fixtures/feedback/conformance.json

check-scoped-reachability-mask-conformance: prepare-quint
    mkdir -p .cache/ascent/scoped-reachability-mask-conformance
    .cache/ascent/tools/quint/node_modules/.bin/quint repl -q --backend typescript -r packages/proofs/quint/ScopedReachabilityMask.qnt::ScopedReachabilityMask conformance .exit > .cache/ascent/scoped-reachability-mask-conformance/quint.json
    cd packages/proofs/lean && lake build ScopedReachabilityMask && lake env lean --run ScopedReachabilityMaskConformance.lean ../../../.cache/ascent/scoped-reachability-mask-conformance/quint.json ../../../t/qualification/fixtures/scoped-reachability-mask/conformance.json

check-scoped-composition-conformance: prepare-quint
    mkdir -p .cache/ascent/scoped-composition-conformance
    .cache/ascent/tools/quint/node_modules/.bin/quint repl -q --backend typescript -r packages/proofs/quint/ScopedComposition.qnt::ScopedComposition conformance .exit > .cache/ascent/scoped-composition-conformance/quint.json
    cd packages/proofs/lean && lake build ScopedComposition && lake env lean --run ScopedCompositionConformance.lean ../../../.cache/ascent/scoped-composition-conformance/quint.json ../../../t/qualification/fixtures/scoped-composition/conformance.json

check-branch-scoped-witness-conformance: prepare-quint
    mkdir -p .cache/ascent/branch-scoped-witness-conformance
    .cache/ascent/tools/quint/node_modules/.bin/quint repl -q --backend typescript -r packages/proofs/quint/BranchScopedWitness.qnt::BranchScopedWitness conformance .exit > .cache/ascent/branch-scoped-witness-conformance/quint.json
    cd packages/proofs/lean && lake build BranchScopedWitness && lake env lean --run BranchScopedWitnessConformance.lean ../../../.cache/ascent/branch-scoped-witness-conformance/quint.json ../../../t/qualification/fixtures/branch-scoped-witness/conformance.json

check-scoped-witness-conformance: prepare-quint
    mkdir -p .cache/ascent/scoped-witness-conformance
    .cache/ascent/tools/quint/node_modules/.bin/quint repl -q --backend typescript -r packages/proofs/quint/ScopedWitness.qnt::ScopedWitness conformance .exit > .cache/ascent/scoped-witness-conformance/quint.json
    cd packages/proofs/lean && lake build ScopedWitness && lake env lean --run ScopedWitness.lean ../../../.cache/ascent/scoped-witness-conformance/quint.json ../../../t/qualification/fixtures/scoped-witness/conformance.json

check-lean-proofs:
    #!/usr/bin/env bash
    set -euo pipefail
    cd packages/proofs/lean
    lake -v build AscentProof AscentProofTests

# Install the locked Quint tool and checksum-pinned compiler/checker backend once.
prepare-quint:
    #!/usr/bin/env bash
    set -euo pipefail
    tool=.cache/ascent/tools/quint
    mkdir -p "$tool"
    if [[ ! -x "$tool/node_modules/.bin/quint" ]] || ! cmp -s packages/proofs/quint/package-lock.json "$tool/package-lock.json" || ! cmp -s packages/proofs/quint/package.json "$tool/package.json"; then
      cp packages/proofs/quint/package.json packages/proofs/quint/package-lock.json "$tool/"
      (cd "$tool"; npm ci --ignore-scripts --no-audit --no-fund)
    fi
    [[ "$("$tool/node_modules/.bin/quint" --version)" = 0.33.0 ]]
    export QUINT_HOME="$PWD/.cache/ascent/tools/quint-backends"
    jar="$QUINT_HOME/apalache-dist-0.62.1/apalache/lib/apalache.jar"
    if [[ ! -f "$jar" ]]; then
      node - <<'JS'
    const {fetchApalache} = require('./.cache/ascent/tools/quint/node_modules/@informalsystems/quint/dist/src/apalache.js');
    fetchApalache('0.62.1', 2).then(result => {
      if (result.isLeft()) {console.error(result.value); process.exit(1)}
    }).catch(error => {console.error(error); process.exit(1)});
    JS
    fi
    actual=$(shasum -a 256 "$jar" | awk '{print $1}')
    [[ "$actual" = "{{ quint_backend_sha256 }}" ]] || { echo 'Quint backend checksum mismatch' >&2; exit 2; }

# Lean kernel checking and exhaustive Quint protocol exploration are independent.
# Both parent exit statuses are required; cached model results are never reused.
check-formal: prepare-quint
    #!/usr/bin/env bash
    set -euo pipefail
    just check-lean-proofs &
    lean=$!
    status=0
    just _check-quint all || status=$?
    wait "$lean" || status=$?
    [[ "$status" = 0 ]] || exit "$status"
    echo 'ALL-FORMAL-CHECK-OK'

check-nonmembership-formal: check-lean-proofs
    just _check-quint Nonmembership

check-actor-round-formal: check-nonmembership-formal
    just _check-quint ActorRound

check-actor-credit-formal:
    just _check-quint ActorRoundCredits

check-actor-pool-formal:
    just _check-quint ActorTestPool

check-actor-session-formal:
    just _check-quint ActorSession

check-ready-components-formal:
    just _check-quint ReadyComponents

check-component-index-formal:
    just _check-quint ComponentIndex

check-provider-frontier-formal:
    just _check-quint ProviderFrontier

check-transitive-components-formal:
    just _check-quint TransitiveComponents

check-provider-views-formal:
    just _check-quint ProviderViews

check-provider-replay-formal:
    just _check-quint ProviderReplay

check-provider-admission-formal:
    just _check-quint ProviderAdmission

check-lattice-projection-formal:
    just _check-quint LatticeProjection

check-oracle-transport-formal:
    just _check-quint OracleTransport

check-provider-routing-formal:
    just _check-quint ProviderRouting

_check-quint group='all': prepare-quint
    #!/usr/bin/env bash
    set -euo pipefail
    group="{{ group }}"
    models=(MinimumHeight WithdrawalConcurrency WithdrawalSession ChangePlan ActorRound ActorRoundCredits ActorSession ActorTestPool CertificateMaterial TerminalTraversal ExecutionFeedback Withholding CanonicalIndex DerivationCounts ProofShapeAdmission ProofPrefix ComponentIndex CountProbe LatticeProjection NativeSessionPublication NegativeProbe NumericProbe OracleTransport PositiveNonmembershipSession ProviderAdmission ProviderFrontier ProviderReplay ProviderRouting ProviderViews ReaderLifetime ReadyComponents SessionTransaction TransitiveComponents)
    models+=(ScopedWitness BranchScopedWitness ScopedComposition ScopedReachabilityMask)
    case "$group" in
      all) ;;
      Nonmembership) models=(CertificateMaterial TerminalTraversal ExecutionFeedback Withholding ProofShapeAdmission ProofPrefix CountProbe NegativeProbe NumericProbe PositiveNonmembershipSession SessionTransaction NativeSessionPublication) ;;
      ProviderViews) models=(ProviderViews ReaderLifetime) ;;
      *) found=0; for model in "${models[@]}"; do if [[ "$model" = "$group" ]]; then found=1; fi; done; [[ "$found" = 1 ]] || { echo "Unknown Quint feature: $group" >&2; exit 2; }; models=("$group") ;;
    esac
    export QUINT_HOME="$PWD/.cache/ascent/tools/quint-backends"
    export OUT_DIR="$PWD/.cache/ascent/quint-output"
    export no_proxy="127.0.0.1,localhost${no_proxy:+,$no_proxy}"
    export NO_PROXY="127.0.0.1,localhost${NO_PROXY:+,$NO_PROXY}"
    quint=.cache/ascent/tools/quint/node_modules/.bin/quint
    jar="$QUINT_HOME/apalache-dist-0.62.1/apalache/lib/apalache.jar"
    temp=$(mktemp -d)
    server_pid=
    cleanup() {
      if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
      rm -rf "$temp"
    }
    trap cleanup EXIT
    cutoff="${ASCENT_FORMAL_GENERATION_CUTOFF:-2}"
    actor_cutoff="${ASCENT_FORMAL_ACTOR_GENERATION_CUTOFF:-2}"
    round_cutoff="${ASCENT_FORMAL_ROUND_CUTOFF:-4}"
    session_cutoff="${ASCENT_FORMAL_SESSION_GENERATION_CUTOFF:-4}"
    views_cutoff="${ASCENT_FORMAL_GENERATION_CUTOFF:-3}"
    for bound in "$cutoff" "$actor_cutoff" "$round_cutoff" "$session_cutoff" "$views_cutoff"; do
      [[ "$bound" =~ ^[0-9]+$ ]] && ((bound >= 2)) || { echo 'Invalid finite exploration bound' >&2; exit 2; }
    done
    ((session_cutoff >= 3 && round_cutoff >= 3))
    configure() {
      main="$model"; specification=; constraint=; properties=
      case "$model" in
        ActorRound) constants="Workers = {1,2}\nGenerationCutoff = $actor_cutoff\nRoundCutoff = $round_cutoff\nMutation = \"none\""; invariants='CompletePublication NoStaleCompletion CompleteBarrier'; constraint=Exploration ;;
        ActorRoundCredits) constants='Tasks = {1,2,3}\nCapacity = 2\nEarlyReturn = FALSE'; invariants='Partition BoundedCredit BoundedAssigned CompleteReturn' ;;
        ActorTestPool) constants='Tasks = {1,2,3}\nCapacity = 2\nEarlyReturn = FALSE'; invariants='Partition BoundedCredits StoppedAdmission CompleteReturn' ;;
        ActorSession) constants="Cuts = {0,1}\nGenerationCutoff = $session_cutoff\nMutation = \"none\""; invariants='ConsistentPublication NoStalePublication DrainedClose'; constraint=Exploration ;;
        ComponentIndex) main=ComponentIndexFixture; constants='Fault = "none"'; invariants='Consistent PrivateExtension HeldStable ViewConsistent' ;;
        LatticeProjection) constants='Mutation = "none"\nRemaining = 2'; invariants='MapExact SnapshotExact PrivateStable HeldStable KeyCoverage BudgetBound RefusalSound RefusalStable' ;;
        NativeSessionPublication) constants="GenerationCutoff = $cutoff\nMutation = \"none\""; invariants='TypeOK CommittedSnapshot CleanAligned PartialBounded'; properties=NoPrematurePublication; constraint=ExplorationBound ;;
        PositiveNonmembershipSession) constants="GenerationCutoff = $cutoff"; invariants='TypeOK NoStalePublished NoStaleUse'; constraint=ExplorationBound ;;
        SessionTransaction) constants="GenerationCutoff = $cutoff\nMutation = \"none\""; invariants='TypeOK AtomicSnapshot'; properties='NoStaleCommit AbortPreservesSnapshot'; constraint=ExplorationBound ;;
        OracleTransport) constants='Mutation = "none"'; invariants='ReaderErrorSound CompleteReaders ReaderClean CompleteBytes ExitAndRequest' ;;
        ProviderAdmission) main=ProviderAdmissionFixture; constants='Fault = "none"'; invariants='CountCaps MatchingExact OutputExact DetachedPacket NoEarlyCallbacks FailedCacheRevoked' ;;
        ProviderFrontier) main=ProviderFrontierFixture; constants='Fault = "none"\nSeeded = FALSE'; invariants='ExactFrontier FrontierComplete DeliveredExact ConsumerSnapshot' ;;
        ProviderReplay) constants='Nodes = {0,1}\nScopes = {0,1}\nMutation = "none"'; invariants='PublishedExact JournalExact OrderExact HeldExact RefusalAtomic' ;;
        ProviderRouting) constants='Mutation = "none"'; invariants=CompleteExact ;;
        WithdrawalSession) constants='Mutation = "none"'; invariants='AtomicSnapshot FrozenGraph CurrentTokens CurrentOrdinal CumulativeSupport HistoricalObservation SupportCoverage StorageAtomic BudgetAdmission'; constraint=ExplorationBound ;;
        MinimumHeight) constants='Mutation = "none"'; invariants='CompleteMinimum Private' ;;
        WithdrawalConcurrency) constants='Mutation = "none"\nSecondExpected = 0'; invariants='AtomicSnapshot ExclusiveOwnership TerminalReleased OnePublicationPerGeneration ReceiptBound' ;;
        ChangePlan) constants='Mutation = "none"'; invariants='Frozen CompletePublication FailureAtomic' ;;
        DerivationCounts) constants='Mutation = "none"'; invariants='Private Fixed Exact' ;;
        CanonicalIndex) constants='Mutation = "none"'; invariants='Private Canonical' ;;
        Withholding) constants='Mutation = "none"'; invariants='Private Bound Protected ExactCut' ;;
        ExecutionFeedback) constants='Mutation = "none"'; invariants='Qualified ExactDifferences ExactMatch InconclusivePrivate' ;;
        ScopedReachabilityMask) constants='Mutation = "none"'; invariants='ExactReach ExactWitnesses ExactBranches ExactGroups Private' ;;
        ScopedComposition) constants='Mutation = "none"'; invariants='ExactWitnesses ExactCoverage ExactMissing ExactAnswer Private' ;;
        BranchScopedWitness) constants='Mutation = "none"'; invariants='ExactWitnesses ExactBranches ExactUnion Private' ;;
        ScopedWitness) constants='Mutation = "none"'; invariants='ExactWitnesses ExactAnswer Private' ;;
        ProofPrefix) constants='Mutation = "none"'; invariants='ExactPrefix GroundedPrefix PublishedGrounded RefusalPrivate PublicationPhase' ;;
        ProofShapeAdmission) constants='Mutation = "none"'; invariants='AllocationAfterAdmission AdmittedShape RefusalUnpublished PublicationAfterIndex' ;;
        TerminalTraversal) constants='Mutation = "none"'; invariants='Bounds FailureFrozen CompletedScan' ;;
        CertificateMaterial) constants='Mutation = "none"'; invariants='CountExact UsageBounds ReservedBeforeCopy NoPartialPublication FailureTerminal' ;;
        NegativeProbe) constants='Mutation = "none"'; invariants='AbsenceSound WitnessSound FailureTerminal Bounds' ;;
        NumericProbe) constants='Mutation = "none"'; invariants='TypedPrefix PrefixValue PublicationExact Unpublished Bounds' ;;
        CountProbe) constants='Mutation = "none"'; invariants='PrefixCount CompleteExact PublishedOnlyComplete FailureTerminal Bounds' ;;
        ProviderViews) constants="Rows = {0,1,2}\nBudget = 2\nMutation = \"none\"\nExplorationBound = $views_cutoff"; invariants='AtomicPublication FrozenRead ReaderAlive CurrentReply LogicalBudget'; constraint=Explore ;;
        ReaderLifetime) constants='Rows = {0,1,2}\nReaders = {1,2}\nBudget = 2\nMutation = "none"'; invariants='ReaderAlive AcceptedCurrent CreditBalance'; properties=ReaderCompletion; specification=spec ;;
        ReadyComponents) constants='Tasks = {1,2,3}\nCapacity = 2\nMutation = "none"'; invariants='Partition Prerequisites CapacityBound CompleteReturn DependencySnapshot CompletedDelivery' ;;
        TransitiveComponents) constants='Nodes = {1,2,3}\nMutation = "none"'; invariants='ReachExact SCCExact ParentRoots PrivateArcs RefusalAtomic ActiveExact DeltaExact ParentChains MemberPartition SizeExact' ;;
      esac
      base="$temp/$model.cfg"
      if [[ -n "$specification" ]]; then printf 'SPECIFICATION %s\n' "$specification" > "$base"; else printf 'INIT q_init\nNEXT q_step\n' > "$base"; fi
      configured_invariants=
      for property in $invariants; do
        if [[ "$main" != "$model" ]]; then property="${main}_${model}_$property"; fi
        configured_invariants+=" $property"
      done
      printf 'CONSTANTS\n%b\nINVARIANTS %s\nCHECK_DEADLOCK FALSE\n' "$constants" "$configured_invariants" >> "$base"
      if [[ -n "$properties" ]]; then printf 'PROPERTIES %s\n' "$properties" >> "$base"; fi
      if [[ -n "$constraint" ]]; then printf 'CONSTRAINT %s\n' "$constraint" >> "$base"; fi
    }
    cache=.cache/ascent/quint-compiled
    mkdir -p "$cache"
    backend_hash=$(shasum -a 256 "$jar" | awk '{print $1}')
    port=$((20000 + $$ % 30000))
    start_compiler() {
      java -Xmx1G -Xss32m -XX:+UseParallelGC "-Djava.io.tmpdir=$temp" -jar "$jar" server "--port=$port" > "$temp/server.out" 2>&1 &
      server_pid=$!
      ready=0
      for ((attempt=0; attempt<30; attempt++)); do
        if node - "$port" <<'JS'
    const grpc = require('./.cache/ascent/tools/quint/node_modules/@grpc/grpc-js');
    const loader = require('./.cache/ascent/tools/quint/node_modules/@grpc/proto-loader');
    const proto = grpc.loadPackageDefinition(loader.loadSync('./.cache/ascent/tools/quint/node_modules/@informalsystems/quint/dist/src/reflection.proto', {keepCase:true}));
    const client = new proto.grpc.reflection.v1alpha.ServerReflection('127.0.0.1:'+process.argv[2], grpc.credentials.createInsecure());
    const call = client.ServerReflectionInfo({deadline:new Date(Date.now()+1000)});
    call.on('data', r => {client.close(); process.exit(r.file_descriptor_response ? 0 : 1)});
    call.on('error', () => {client.close(); process.exit(1)});
    call.write({file_containing_symbol:'shai.cmdExecutor.CmdExecutor'});
    JS
        then ready=1; break; fi
        kill -0 "$server_pid" 2>/dev/null || break
        sleep 1
      done
      if [[ "$ready" != 1 ]]; then cat "$temp/server.out" >&2; exit 1; fi
    }
    for model in "${models[@]}"; do
      configure
      source="packages/proofs/quint/$model.qnt"
      temporal="$properties"
      if [[ "$model" = ReaderLifetime ]]; then temporal='ReaderCompletion RoundCompletion spec roundSpec'; fi
      fingerprint=$({ cat "$source" packages/proofs/quint/package-lock.json; printf '%s\n' "$backend_hash" "$main" "$invariants" "$temporal" "$constraint"; } | shasum -a 256 | awk '{print $1}')
      hit=0
      if [[ -f "$cache/$model.identity" && -f "$cache/$model.tla" ]]; then
        read -r expected artifact_hash < "$cache/$model.identity"
        actual=$(shasum -a 256 "$cache/$model.tla" | awk '{print $1}')
        if [[ "$expected" = "$fingerprint" && "$artifact_hash" = "$actual" ]]; then hit=1; fi
      fi
      if [[ "$hit" = 1 ]]; then cp "$cache/$model.tla" "$temp/$main.tla"; else
        if [[ -z "$server_pid" ]]; then start_compiler; fi
        compile_invariants="$invariants${constraint:+ $constraint}"
        options=(--main "$main" --target tlaplus --init init --step step --invariant "${compile_invariants// /,}" --apalache-version 0.62.1 --server-endpoint "127.0.0.1:$port" --verbosity 0)
        if [[ -n "$temporal" ]]; then options+=(--temporal "${temporal// /,}"); fi
        "$quint" compile "$source" "${options[@]}" > "$temp/$main.tla"
        grep -q "MODULE $main " "$temp/$main.tla"
        cp "$temp/$main.tla" "$cache/$model.tla"
        artifact_hash=$(shasum -a 256 "$cache/$model.tla" | awk '{print $1}')
        printf '%s %s\n' "$fingerprint" "$artifact_hash" > "$cache/$model.identity"
      fi
      # Apalache defines assignment annotations as equality. TLC's ENABLED
      # handling of the annotated call can spuriously disable fair actions.
      # Erase only operator tokens, preserving all quoted model values.
      node - "$temp/$main.tla" <<'JS'
    const fs = require('fs');
    const path = process.argv[2];
    const source = fs.readFileSync(path, 'utf8');
    fs.writeFileSync(path, source.replace(/"(?:\\.|[^"\\])*"|:=/g, token => token === ':=' ? '=' : token));
    JS
      echo "QUINT-COMPILE-OK $model cache=$hit"
        done
        if [[ -n "$server_pid" ]]; then kill "$server_pid"; wait "$server_pid" || true; server_pid=; fi
        check_model() {
          local model="$1" main base specification constraint properties constants invariants variant code expected property mutation capacity
          configure
          execute() {
            local variant="$1" config="$2" expected="$3" property="${4:-}" code=0
            java -Xmx1G -XX:+UseParallelGC "-Djava.io.tmpdir=$temp/$model" -cp "$jar" tlc2.TLC -workers 1 -config "$config" -metadir "$temp/$model/$variant" "$temp/$main.tla" 2>&1 | tee "$temp/$model-$variant.out" | awk -v label="$model-$variant" '/^Progress\(/ {print label ": " $0; fflush()}' || code=$?
            if [[ "$code" != "$expected" ]]; then cat "$temp/$model-$variant.out" >&2; echo "Quint checker failure: $model $variant exit=$code expected=$expected" >&2; return 1; fi
            if [[ "$expected" = 0 ]]; then
              grep -q 'Model checking completed. No error has been found.' "$temp/$model-$variant.out"
              grep 'states generated.*distinct states found' "$temp/$model-$variant.out" | tail -1
              echo "QUINT-CHECK-OK $model $variant"
            elif [[ "$expected" = 12 ]]; then
              grep -q "Invariant $property is violated" "$temp/$model-$variant.out" || { cat "$temp/$model-$variant.out" >&2; return 1; }
              echo "COUNTEREXAMPLE-OK $model-$variant $property exit=12"
            else
              grep -Eq "Temporal propert(y $property was|ies were) violated|Action property $property is violated" "$temp/$model-$variant.out" || { cat "$temp/$model-$variant.out" >&2; return 1; }
              echo "COUNTEREXAMPLE-OK $model-$variant $property exit=13"
            fi
          }
          fault() {
            mutation="$1"; property="$2"; expected="${3:-12}"
            if [[ "$main" != "$model" ]]; then property="${main}_${model}_$property"; fi
            variant="$temp/$model-$mutation.cfg"
            sed -e "s/Mutation = \"none\"/Mutation = \"$mutation\"/" -e "s/Fault = \"none\"/Fault = \"$mutation\"/" -e 's/EarlyReturn = FALSE/EarlyReturn = TRUE/' -e '/^INVARIANTS /d' -e '/^PROPERTIES /d' "$base" > "$variant"
            if [[ "$expected" = 12 ]]; then printf 'INVARIANT %s\n' "$property" >> "$variant"; else printf 'PROPERTY %s\n' "$property" >> "$variant"; fi
            if [[ "$model" = ProviderFrontier && "$mutation" = initial ]]; then sed -i.bak 's/Seeded = FALSE/Seeded = TRUE/' "$variant"; fi
            if [[ "$model" = LatticeProjection && "$mutation" = budget-skip || "$model" = LatticeProjection && "$mutation" = budget-events || "$model" = LatticeProjection && "$mutation" = refusal-publish ]]; then sed -i.bak 's/Remaining = 2/Remaining = 1/' "$variant"; fi
            execute "$mutation" "$variant" "$expected" "$property"
          }
          mkdir -p "$temp/$model"
          execute correct "$base" 0
          case "$model" in
            ActorRound) fault early CompletePublication; fault stale NoStaleCompletion; fault cancel CompletePublication ;;
            ActorRoundCredits|ActorTestPool) for capacity in 1 3; do sed "s/Capacity = 2/Capacity = $capacity/" "$base" > "$temp/$model-capacity.cfg"; execute "capacity-$capacity" "$temp/$model-capacity.cfg" 0; done; fault early CompleteReturn ;;
            ActorSession) fault stale NoStalePublication; fault early DrainedClose ;;
            ComponentIndex) for mutation in order early failed alias foreign reset columns rebuild-columns; do fault "$mutation" Consistent; done; fault held HeldStable; fault held-columns HeldStable; for mutation in extend-view failed-view rebuild-view; do fault "$mutation" ViewConsistent; done ;;
            LatticeProjection) for capacity in 0 1; do sed "s/Remaining = 2/Remaining = $capacity/" "$base" > "$temp/$model-capacity.cfg"; execute "remaining-$capacity" "$temp/$model-capacity.cfg" 0; done; for mutation in overwrite prior false; do fault "$mutation" MapExact; done; for mutation in retain early stale; do fault "$mutation" SnapshotExact; done; fault borrow HeldStable; fault lost-key KeyCoverage; fault repeat-key KeyCoverage; fault budget-skip BudgetBound; fault budget-events RefusalSound; fault refusal-publish RefusalStable ;;
            NativeSessionPublication) for mutation in early bounded alias; do fault "$mutation" CommittedSnapshot; done ;;
            SessionTransaction) fault early AtomicSnapshot; fault stale NoStaleCommit 13; fault global AtomicSnapshot; fault reuse AtomicSnapshot ;;
            ProviderFrontier) sed 's/Seeded = FALSE/Seeded = TRUE/' "$base" > "$temp/seeded.cfg"; execute seeded "$temp/seeded.cfg" 0; sed 's/Fault = "none"/Fault = "overlap"/' "$base" > "$temp/overlap.cfg"; execute overlap "$temp/overlap.cfg" 0; fault raw FrontierComplete; fault foreign FrontierComplete; fault omit DeliveredExact; for mutation in early old initial replace; do fault "$mutation" ConsumerSnapshot; done ;;
            ProviderReplay) fault scope PublishedExact; fault early JournalExact; fault drop JournalExact; fault kind OrderExact; fault cut HeldExact; fault reject RefusalAtomic ;;
            ProviderAdmission) fault nocap MatchingExact; fault set MatchingExact; fault allwitness CountCaps; fault early NoEarlyCallbacks; fault borrow DetachedPacket; fault retain FailedCacheRevoked ;;
            ProviderRouting) for mutation in drop order representative prefix; do fault "$mutation" CompleteExact; done ;;
            ProviderViews) fault alias FrozenRead; fault retire ReaderAlive; fault early AtomicPublication; fault stale CurrentReply; fault budget LogicalBudget ;;
            ReaderLifetime) for mutation in stuck unfair global; do fault "$mutation" ReaderCompletion 13; done; fault retire ReaderAlive; fault credit CreditBalance; fault aba AcceptedCurrent;
              sed -e 's/Readers = {1,2}/Readers = {1}/' -e 's/Mutation = "none"/Mutation = "global"/' "$base" > "$temp/single.cfg"; execute single-reader-global-fairness "$temp/single.cfg" 0;
              sed -e 's/SPECIFICATION spec/SPECIFICATION roundSpec/' -e 's/PROPERTIES ReaderCompletion/PROPERTIES ReaderCompletion RoundCompletion/' "$base" > "$temp/round.cfg"; execute sealed-round "$temp/round.cfg" 0;
              sed -e 's/Mutation = "none"/Mutation = "unfair"/' -e '/^INVARIANTS /d' -e '/^PROPERTIES /d' "$temp/round.cfg" > "$temp/round-unfair.cfg"; printf 'PROPERTY RoundCompletion\n' >> "$temp/round-unfair.cfg"; execute sealed-round-unfair "$temp/round-unfair.cfg" 13 RoundCompletion ;;
            ReadyComponents) for capacity in 1 3; do sed "s/Capacity = 2/Capacity = $capacity/" "$base" > "$temp/$model-capacity.cfg"; execute "capacity-$capacity" "$temp/$model-capacity.cfg" 0; done; fault prerequisite Prerequisites; fault early CompleteReturn; fault snapshot DependencySnapshot; fault tail CompletedDelivery; fault credit CompletedDelivery ;;
            TransitiveComponents) fault split SCCExact; fault stale ReachExact; fault reject RefusalAtomic; for mutation in raw diagonal old; do fault "$mutation" DeltaExact; done; fault chain ParentChains; fault members MemberPartition; fault size SizeExact; fault adjacency PrivateArcs ;;
            OracleTransport) fault early CompleteReaders; fault swallow ReaderClean; fault tail CompleteBytes; fault interrupt ReaderErrorSound ;;
            WithdrawalSession) fault early AtomicSnapshot; fault graphEdit FrozenGraph; fault unchecked AtomicSnapshot; fault ordinal CurrentOrdinal; fault forgetRemoved CumulativeSupport; fault rebase CurrentTokens; fault borrowObservation HistoricalObservation; fault compactLoss SupportCoverage; fault compactEarly StorageAtomic; fault compactRebase CurrentTokens; fault uncharged BudgetAdmission ;;
            MinimumHeight) fault first CompleteMinimum; fault stale CompleteMinimum; fault early Private; fault cycle CompleteMinimum; fault minimumBody CompleteMinimum ;;
            WithdrawalConcurrency) fault outside OnePublicationPerGeneration; fault abandon TerminalReleased; fault earlyUnlock ExclusiveOwnership; sed 's/SecondExpected = 0/SecondExpected = 1/' "$base" > "$temp/$model-successor.cfg"; execute successor "$temp/$model-successor.cfg" 0; sed 's/Mutation = "none"/Mutation = "lateReceipt"/' "$temp/$model-successor.cfg" > "$temp/$model-late.cfg"; execute late-receipt "$temp/$model-late.cfg" 12 ReceiptBound ;;
            ChangePlan) fault alias Frozen; fault borrow Frozen; fault early CompletePublication; fault failure FailureAtomic ;;
            DerivationCounts) fault refusal Private; fault early Fixed; fault accumulate Fixed ;;
            CanonicalIndex) fault early Private; fault omit Canonical; fault duplicate Canonical; fault order Canonical ;;
            Withholding) fault early Private; fault local Protected; fault stale Bound; fault missing Protected ;;
            ExecutionFeedback) fault stale Qualified; fault partial Qualified; fault missing ExactDifferences; fault extra ExactDifferences; fault referenceStale Qualified; fault referencePartial Qualified; fault query Qualified ;;
            ScopedReachabilityMask) fault global ExactWitnesses; fault late ExactWitnesses; fault cleanAlternative ExactBranches; fault forgetWitness ExactWitnesses ;;
            ScopedComposition) fault union ExactAnswer; fault allBranches ExactCoverage; fault emptyGroup ExactMissing; fault forgetWitness ExactWitnesses ;;
            BranchScopedWitness) fault crossMask ExactWitnesses; fault switchMask ExactWitnesses; fault forgetScope ExactWitnesses; fault collapseBranch ExactBranches ;;
            ScopedWitness) fault late ExactWitnesses; fault global ExactAnswer; fault anyBlocked ExactWitnesses; fault forget ExactWitnesses ;;
            ProofPrefix) fault early ExactPrefix; fault forward GroundedPrefix; fault source GroundedPrefix; fault partial RefusalPrivate ;;
            ProofShapeAdmission) fault early AllocationAfterAdmission; fault roots AdmittedShape; fault improper AdmittedShape; fault partial RefusalUnpublished ;;
            TerminalTraversal) fault tail FailureFrozen; fault resume FailureFrozen; fault skip FailureFrozen; fault early CompletedScan ;;
            CertificateMaterial) fault seed-skip CountExact; fault late ReservedBeforeCopy; fault partial NoPartialPublication; fault resume FailureTerminal ;;
            NegativeProbe) fault early AbsenceSound; fault refusal AbsenceSound; fault resume FailureTerminal ;;
            NumericProbe) fault type-skip TypedPrefix; fault empty PrefixValue; fault zero PrefixValue; fault early PublicationExact; fault refusal Unpublished ;;
            CountProbe) fault unmatched PrefixCount; fault early CompleteExact; fault refusal PublishedOnlyComplete; fault resume FailureTerminal ;;
          esac
        }
        # Calls run as simple commands in independent subshells: failures terminate
        # their lane, and both child exit statuses are required by the parent.
        lane() { local offset="$1" i; for ((i=offset;i<${#models[@]};i+=2)); do check_model "${models[i]}"; done; }
        lane 0 & first=$!
        lane 1 & second=$!
        status=0
        wait "$first" || status=$?
        wait "$second" || status=$?
        [[ "$status" = 0 ]] || exit "$status"
        echo 'ALL-QUINT-CHECK-OK'

# Matched finite-operator research probe; every sample checks independent
# closure before reporting cost. This is separate from the SS suite.
operator-change-probe: prepare-test-library
    {{ test_library_environment }} just _operator-change-probe

_operator-change-probe:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    output_file="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/case.XXXXXX")"
    trap 'rm -f "$output_file"' EXIT
    export GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}"
    timeout 90s {{ gerbil_command }} {{ gerbil_test_runtime_options }} env {{ gxi_command }} t/performance/scheme-operator-change-probe.ss 2>&1 | tee "$output_file"
    test "$(grep -c '^CASE ' "$output_file")" -eq 6
    test "$(grep -c '^SAMPLE ' "$output_file")" -eq 60
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi

# Exact-set gate and matched exploratory timing for native retained updates.
operator-retained-probe: prepare-test-library
    {{ test_library_environment }} just _operator-retained-probe

_operator-retained-probe:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    output_file="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/case.XXXXXX")"
    trap 'rm -f "$output_file"' EXIT
    export GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}"
    timeout 120s {{ gerbil_command }} {{ gerbil_test_runtime_options }} env {{ gxi_command }} t/performance/scheme-operator-retained-probe.ss 2>&1 | tee "$output_file"
    test "$(grep -c '^CASE ' "$output_file")" -eq 6
    test "$(grep -c '^SAMPLE ' "$output_file")" -eq 72
    test "$(grep -c '^SEQUENCE ' "$output_file")" -eq 1
    test "$(grep -c '^LIFECYCLE SAMPLE ' "$output_file")" -eq 8
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi

clock-memory-probe:
    ASCENT_GXTEST_TIMEOUT="${ASCENT_GXTEST_TIMEOUT:-100s}" just test-file t/performance/ascent-clock-memory-probe.ss

binding-benchmark: prepare-test-library
    {{ test_library_environment }} just _binding-benchmark

_binding-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export GERBIL_BUILD_CORES="${GERBIL_BUILD_CORES:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || getconf NPROCESSORS_ONLN)}"
    export ASCENT_BINDING_BENCH_LIB="{{ justfile_directory() }}/.gerbil/binding-benchmark/lib"
    export ASCENT_BINDING_RECEIPT="${ASCENT_BINDING_RECEIPT:-{{ justfile_directory() }}/.gerbil/binding-benchmark/receipt.sexp}"
    mkdir -p "$ASCENT_BINDING_BENCH_LIB"
    shasum -a 256 core/dependency-graph.ss core/rule-semantics.ss program/objects.ss program/evaluate.ss program/analysis.ss program/planning.ss t/qualification/ascent-binding-reference-fixture.ss t/qualification/ascent-binding-reference-evaluate.ss t/qualification/ascent-index-program-fixture.ss t/performance/binding-benchmark.ss tools/build-binding-benchmark.ss > "$ASCENT_BINDING_RECEIPT.sources"
    started=$SECONDS
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    log="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/run.XXXXXX")"
    trap 'rm -f "$log"' EXIT
    printf '[binding-benchmark] BUILD compiled current/reference engines (%s cores)\n' "$GERBIL_BUILD_CORES"
    timeout 150s {{ gxi_command }} {{ gerbil_test_runtime_options }} tools/build-binding-benchmark.ss
    printf '[binding-benchmark] RUN alternating old/new, 1000 samples per case\n'
    GERBIL_LOADPATH="$ASCENT_BINDING_BENCH_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 120s {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/binding-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 6
    grep -x 'OK' "$log" >/dev/null

strata-benchmark: prepare-test-library
    {{ test_library_environment }} just _strata-benchmark

_strata-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export GERBIL_BUILD_CORES="${GERBIL_BUILD_CORES:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || getconf NPROCESSORS_ONLN)}"
    export ASCENT_STRATA_BENCH_LIB="{{ justfile_directory() }}/.gerbil/strata-benchmark/lib"
    export ASCENT_STRATA_RECEIPT="${ASCENT_STRATA_RECEIPT:-{{ justfile_directory() }}/.gerbil/strata-benchmark/receipt.sexp}"
    mkdir -p "$ASCENT_STRATA_BENCH_LIB"
    shasum -a 256 core/dependency-graph.ss core/rule-semantics.ss t/qualification/ascent-strata-fixture.ss t/performance/strata-benchmark.ss tools/build-strata-benchmark.ss > "$ASCENT_STRATA_RECEIPT.sources"
    started=$SECONDS
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    log="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/run.XXXXXX")"
    trap 'rm -f "$log"' EXIT
    printf '[strata-benchmark] BUILD current planning and relaxation oracle\n'
    timeout 60s {{ gxi_command }} {{ gerbil_test_runtime_options }} tools/build-strata-benchmark.ss
    printf '[strata-benchmark] RUN alternating old/new, 1000 samples per case\n'
    GERBIL_LOADPATH="$ASCENT_STRATA_BENCH_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/strata-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 4
    grep -x 'OK' "$log" >/dev/null

# Run one unchanged SS fixture through the native qualification harness.
performance-scenario name: prepare-test-library
    {{ test_library_environment }} just _performance-scenario "{{ name }}"

# ASCENT owns its 1000-sample SS receipts using ASP's benchmark profile.
performance: prepare-test-library
    {{ test_library_environment }} just _performance

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
    output="$(mktemp)"
    trap 'rm -f "$output"' EXIT
    timeout "${ASCENT_GXTEST_TIMEOUT:-180s}" {{ gxi_command }} -:max-heap=2G,debug=q :gerbil/tools/gxtest -v 5 t/performance/ascent-scenario-performance-test.ss t/performance/ascent-binary-program-performance-test.ss t/performance/ascent-shortest-candidates-performance-test.ss 2>&1 | tee "$output"
    if grep -E 'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow' "$output" >/dev/null; then exit 1; fi
    awk -f tools/assert-test-cases.awk "$output"
    test "$(grep -c '^MODULE-OK ' "$output")" -eq 3
    grep -F 'HARNESS-OK' "$output" >/dev/null
    grep -x 'OK' "$output" >/dev/null

check-model-source-closure:
    {{ gxi_command }} t/native/artifact-admission.ss check
    {{ test_library_environment }} timeout 120s .cache/ascent/native-library/dsl-closure {{ gerbil_test_runtime_options }} --source-closure

ascent-pairs:
    @timeout 90s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-binary-program-pairs.ss

ascent-guarded:
    @timeout 90s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-binary-program-guarded.ss

ascent-candidates:
    @timeout 90s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-closure-candidates-output.ss

timeout-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-timeout-output.ss

timeout-strata-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-timeout-strata-output.ss

byods-lattice-rows:
    @timeout 90s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-byods-lattice-output.ss

byods-lattice-session-rows:
    @timeout 90s .cache/ascent/native-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle byods-lattice-session

byods-lattice-scale-rows:
    @timeout 90s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-byods-lattice-scale-output.ss

rule-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-rule-program-output.ss

aggregate-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-aggregate-program-output.ss

derived-aggregate-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-derived-aggregate-program-output.ss

syntax-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-syntax-program-output.ss

scc-summary:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-scc-summary-test.ss

var-points-to-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-var-points-to-output.ss

upstream-example-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-upstream-examples-output.ss

lattice-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-lattice-program-output.ss

lattice-set-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-lattice-set-output.ss

integrated-corpus-rows:
    @timeout 90s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-integrated-corpus-output.ss

mutual-corpus-rows:
    @timeout 120s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-mutual-program-output.ss

lattice-session-corpus-rows:
    @timeout 120s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-lattice-session-output.ss

lattice-negation-rows:
    @timeout 120s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-lattice-negation-output.ss

invalid-program-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-invalid-program-output.ss

product-session-rows:
    @timeout 120s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-product-session-output.ss

index-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-index-program-output.ss

index-rows-alist:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-index-program-output.ss alist

index-composite-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-index-program-output.ss composite

index-composite-rows-alist:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-index-program-output.ss composite alist

index-lattice-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-index-program-output.ss lattice

index-lattice-rows-alist:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-index-program-output.ss lattice alist

_oracle-native name *flags:
    @timeout 90s .cache/ascent/native-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle {{ name }} {{ flags }}

eqrel-rows:
    @just _oracle-native eqrel-program

eqrel-scale-rows:
    @just _oracle-native eqrel-program scale

eqrel-default-rows:
    @just _oracle-native eqrel-program default

trrel-rows:
    @just _oracle-native eqrel-program trrel

trrel-scale-rows:
    @just _oracle-native eqrel-program trrel scale

trrel-uf-rows:
    @just _oracle-native eqrel-program trrel-uf

trrel-uf-scale-rows:
    @just _oracle-native eqrel-program trrel-uf scale

byods-query-rows:
    @just _oracle-native byods-query

typed-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-typed-program-output.ss

module-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-module-program-output.ss

mutual-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-mutual-program-output.ss

scc-order-rows:
    @timeout 90s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-scc-order-output.ss

arity-repetition-rows:
    @timeout 90s .cache/ascent/native-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle arity-repetition

clause-composition-rows:
    @timeout 90s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-clause-composition-output.ss

support-study-reference:
    @timeout 120s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-support-study-output.ss reference

support-study-hypothetical:
    @timeout 120s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-support-study-output.ss hypothetical

support-study-candidate mode="evaluate":
    @timeout 120s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-support-study-output.ss {{ mode }}

candidate-description:
    @timeout 120s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-support-study-output.ss description

candidate-repair-seed mode="repair-seed":
    @timeout 120s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-support-study-output.ss {{ mode }}

support-discriminator-reference:
    @timeout 120s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-support-study-output.ss discriminator-reference

support-discriminator-candidate:
    @timeout 120s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-support-study-output.ss discriminator-evaluate

clause-scale-rows:
    @timeout 90s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-clause-scale-output.ss

divisibility-lattice-rows:
    @timeout 90s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-divisibility-lattice-output.ss

multi-source-session-rows:
    @timeout 90s .cache/ascent/native-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle multi-source-session

byods-session-rows:
    @timeout 90s .cache/ascent/native-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle byods-session

# Verify the immutable paper input envelope before the native complete count.
steensgaard-data directory='.cache/ascent/paper-data/steensgaard':
    @PYTHONPATH="{{ justfile_directory() }}/python/src" python3 -m ascent_test_support.paper_source "{{ directory }}" docs/evidence/scheme-application-admission-20261007/openjdk-source.json
    @just _oracle-native steensgaard-data "{{ directory }}" 440438706

steensgaard-rows:
    @just _oracle-native steensgaard

grouped-eqrel-session-rows:
    @timeout 90s .cache/ascent/native-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle grouped-eqrel-session

oracle: build-dsl-closure
    #!/usr/bin/env bash
    set -euo pipefail
    export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
    if [[ "$(uname -s)" == Darwin ]]; then
        unset SDKROOT DEVELOPER_DIR
        export SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
        export CC=/usr/bin/clang
        export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C linker=/usr/bin/clang -C link-arg=-isysroot -C link-arg=$SDKROOT"
    fi
    # Resolve package identity without passing Cargo through Gambit process ports.
    export GERBIL_PATH="${GERBIL_PATH:-$({{ gxi_command }} -e '(display (getenv "GERBIL_PATH"))' </dev/null 2> >(cat >&2))}"
    # Fresh pipes preserve blocking Cargo stdio after the Gerbil build prerequisite.
    cargo test --locked --manifest-path rust/ascent-oracle/Cargo.toml </dev/null 2>&1 | cat

timed-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-timing-test.ss

size-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .gerbil/size-benchmark
    export ASCENT_SIZE_BENCH_LIB="{{ justfile_directory() }}/.gerbil/size-benchmark/lib"
    export ASCENT_SIZE_RECEIPT="${ASCENT_SIZE_RECEIPT:-{{ justfile_directory() }}/.gerbil/size-benchmark/receipt.sexp}"
    shasum -a 256 program/evaluate.ss t/qualification/ascent-size-reference-evaluate.ss t/performance/size-benchmark.ss tools/build-size-benchmark.ss > "$ASCENT_SIZE_RECEIPT.sources"
    {{ test_library_environment }} just _size-benchmark

_size-benchmark:
    timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} tools/build-size-benchmark.ss
    GERBIL_LOADPATH="$ASCENT_SIZE_BENCH_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 150s {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/size-benchmark.ss

# Whole-solve comparison against the committed narrow-frontier evaluator.
multi-frontier-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .gerbil/multi-frontier
    export ASCENT_MULTI_FRONTIER_LIB="{{ justfile_directory() }}/.gerbil/multi-frontier/lib"
    export ASCENT_MULTI_FRONTIER_RECEIPT="${ASCENT_MULTI_FRONTIER_RECEIPT:-{{ justfile_directory() }}/.gerbil/multi-frontier/receipt.sexp}"
    shasum -a 256 program/evaluate.ss t/qualification/ascent-multi-frontier-reference-evaluate.ss t/performance/multi-frontier-benchmark.ss tools/build-multi-frontier-benchmark.ss > "$ASCENT_MULTI_FRONTIER_RECEIPT.sources"
    {{ test_library_environment }} just _multi-frontier-benchmark

_multi-frontier-benchmark:
    timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} tools/build-multi-frontier-benchmark.ss
    GERBIL_LOADPATH="$ASCENT_MULTI_FRONTIER_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 150s {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/multi-frontier-benchmark.ss

set-size-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .gerbil/set-size
    export ASCENT_SET_SIZE_LIB="{{ justfile_directory() }}/.gerbil/set-size/lib"
    export ASCENT_SET_SIZE_RECEIPT="${ASCENT_SET_SIZE_RECEIPT:-{{ justfile_directory() }}/.gerbil/set-size/receipt.sexp}"
    shasum -a 256 program/evaluate.ss t/qualification/ascent-set-size-reference-evaluate.ss t/performance/set-size-benchmark.ss tools/build-set-size-benchmark.ss > "$ASCENT_SET_SIZE_RECEIPT.sources"
    {{ test_library_environment }} just _set-size-benchmark

_set-size-benchmark:
    timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} tools/build-set-size-benchmark.ss
    GERBIL_LOADPATH="$ASCENT_SET_SIZE_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 150s {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/set-size-benchmark.ss

set-batch-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .gerbil/set-batch
    export ASCENT_SET_BATCH_LIB="{{ justfile_directory() }}/.gerbil/set-batch/lib"
    export ASCENT_SET_BATCH_RECEIPT="${ASCENT_SET_BATCH_RECEIPT:-{{ justfile_directory() }}/.gerbil/set-batch/receipt.sexp}"
    shasum -a 256 table/storage.ss t/qualification/ascent-set-batch-reference.ss t/performance/set-batch-benchmark.ss tools/build-set-batch-benchmark.ss > "$ASCENT_SET_BATCH_RECEIPT.sources"
    {{ test_library_environment }} just _set-batch-benchmark

_set-batch-benchmark:
    timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} tools/build-set-batch-benchmark.ss
    GERBIL_LOADPATH="$ASCENT_SET_BATCH_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 150s {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/set-batch-benchmark.ss

set-emit-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .gerbil/set-emit
    export ASCENT_SET_EMIT_LIB="{{ justfile_directory() }}/.gerbil/set-emit/lib"
    export ASCENT_SET_EMIT_RECEIPT="${ASCENT_SET_EMIT_RECEIPT:-{{ justfile_directory() }}/.gerbil/set-emit/receipt.sexp}"
    shasum -a 256 program/evaluate.ss t/qualification/ascent-set-emit-reference-evaluate.ss t/performance/set-emit-benchmark.ss tools/build-set-emit-benchmark.ss > "$ASCENT_SET_EMIT_RECEIPT.sources"
    {{ test_library_environment }} just _set-emit-benchmark

_set-emit-benchmark:
    timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} tools/build-set-emit-benchmark.ss
    GERBIL_LOADPATH="$ASCENT_SET_EMIT_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 400s {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/set-emit-benchmark.ss

set-emit-allocation:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .gerbil/set-emit
    export ASCENT_SET_EMIT_LIB="{{ justfile_directory() }}/.gerbil/set-emit/lib"
    export ASCENT_SET_EMIT_ALLOCATION_RECEIPT="${ASCENT_SET_EMIT_ALLOCATION_RECEIPT:-{{ justfile_directory() }}/.gerbil/set-emit/allocation.sexp}"
    shasum -a 256 program/evaluate.ss t/qualification/ascent-set-emit-reference-evaluate.ss t/performance/set-emit-allocation.ss tools/build-set-emit-benchmark.ss > "$ASCENT_SET_EMIT_ALLOCATION_RECEIPT.sources"
    {{ test_library_environment }} just _set-emit-allocation

_set-emit-allocation:
    timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} tools/build-set-emit-benchmark.ss
    GERBIL_LOADPATH="$ASCENT_SET_EMIT_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 150s {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/set-emit-allocation.ss

set-source-allocation:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .gerbil/set-source
    export ASCENT_SET_SOURCE_LIB="{{ justfile_directory() }}/.gerbil/set-source/lib"
    export ASCENT_SET_SOURCE_ALLOCATION_RECEIPT="${ASCENT_SET_SOURCE_ALLOCATION_RECEIPT:-{{ justfile_directory() }}/.gerbil/set-source/allocation.sexp}"
    shasum -a 256 program/evaluate.ss program/admission.ss t/qualification/ascent-set-source-reference-evaluate.ss t/performance/set-source-allocation.ss tools/build-set-source-benchmark.ss > "$ASCENT_SET_SOURCE_ALLOCATION_RECEIPT.sources"
    {{ test_library_environment }} just _set-source-allocation

_set-source-allocation:
    timeout 90s {{ gxi_command }} {{ gerbil_test_runtime_options }} tools/build-set-source-benchmark.ss
    GERBIL_LOADPATH="$ASCENT_SET_SOURCE_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 150s {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/set-source-allocation.ss

# Whole-solve positive rule plans: ordered semantics, allocation and raw timing.
positive-plan-benchmark: prepare-test-library
    {{ test_library_environment }} just _positive-plan-benchmark

_positive-plan-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export ASCENT_POSITIVE_PLAN_LIB="{{ justfile_directory() }}/.gerbil/positive-plan/lib"
    export ASCENT_POSITIVE_PLAN_RECEIPT="${ASCENT_POSITIVE_PLAN_RECEIPT:-{{ justfile_directory() }}/.gerbil/positive-plan/receipt.sexp}"
    mkdir -p .gerbil/positive-plan
    shasum -a 256 core/positive-plan.ss program/index.ss program/actor-round.ss program/evaluate.ss program/analysis.ss t/qualification/ascent-positive-plan-reference-analysis.ss t/qualification/ascent-positive-plan-reference-evaluate.ss t/performance/positive-plan-benchmark.ss tools/build-positive-plan-benchmark.ss > "$ASCENT_POSITIVE_PLAN_RECEIPT.sources"
    timeout 150s {{ gxi_command }} {{ gerbil_test_runtime_options }} tools/build-positive-plan-benchmark.ss
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    log="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/run.XXXXXX")"
    trap 'rm -f "$log"' EXIT
    GERBIL_LOADPATH="$ASCENT_POSITIVE_PLAN_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/positive-plan-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 7
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    grep -x 'OK' "$log" >/dev/null

workspace-benchmark: prepare-test-library
    {{ test_library_environment }} just _workspace-benchmark

_workspace-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export ASCENT_WORKSPACE_LIB="{{ justfile_directory() }}/.gerbil/execution-workspace/lib"
    export ASCENT_WORKSPACE_RECEIPT="${ASCENT_WORKSPACE_RECEIPT:-{{ justfile_directory() }}/.gerbil/execution-workspace/receipt.sexp}"
    mkdir -p .gerbil/execution-workspace
    shasum -a 256 core/positive-plan.ss program/evaluate.ss program/analysis.ss t/qualification/ascent-workspace-reference-analysis.ss t/qualification/ascent-workspace-reference-positive.ss t/qualification/ascent-workspace-reference-evaluate.ss t/performance/workspace-benchmark.ss tools/build-workspace-benchmark.ss > "$ASCENT_WORKSPACE_RECEIPT.sources"
    timeout 150s {{ gxi_command }} {{ gerbil_test_runtime_options }} tools/build-workspace-benchmark.ss
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    log="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/run.XXXXXX")"
    trap 'rm -f "$log"' EXIT
    GERBIL_LOADPATH="$ASCENT_WORKSPACE_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/workspace-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 9
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    grep -x 'OK' "$log" >/dev/null

ordered-relations-benchmark: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/ordered-relations/qualify.ss

materialization-benchmark: prepare-test-library
    {{ test_library_environment }} just _materialization-benchmark

_materialization-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export ASCENT_MATERIALIZATION_LIB="{{ justfile_directory() }}/.gerbil/relation-materialization/lib"
    export ASCENT_MATERIALIZATION_RECEIPT="${ASCENT_MATERIALIZATION_RECEIPT:-{{ justfile_directory() }}/.gerbil/relation-materialization/receipt.sexp}"
    mkdir -p .gerbil/relation-materialization
    shasum -a 256 core/binary-relation.ss table/expression.ss t/qualification/ascent-materialization-reference.ss t/performance/materialization-benchmark.ss tools/build-materialization-benchmark.ss > "$ASCENT_MATERIALIZATION_RECEIPT.sources"
    timeout 150s {{ gxi_command }} {{ gerbil_test_runtime_options }} tools/build-materialization-benchmark.ss
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    log="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/run.XXXXXX")"
    trap 'rm -f "$log"' EXIT
    GERBIL_LOADPATH="$ASCENT_MATERIALIZATION_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/materialization-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 8
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    grep -x 'OK' "$log" >/dev/null

index-lifecycle-benchmark: prepare-test-library
    {{ test_library_environment }} just _index-lifecycle-benchmark

_index-lifecycle-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export ASCENT_INDEX_LIFECYCLE_LIB="{{ justfile_directory() }}/.gerbil/index-lifecycle/lib"
    export ASCENT_INDEX_LIFECYCLE_RECEIPT="${ASCENT_INDEX_LIFECYCLE_RECEIPT:-{{ justfile_directory() }}/.gerbil/index-lifecycle/receipt.sexp}"
    mkdir -p .gerbil/index-lifecycle
    shasum -a 256 table/funs.ss table/access.ss table/provider.ss program/evaluate.ss core/positive-plan.ss program/analysis.ss t/qualification/ascent-index-reference-funs.ss t/qualification/ascent-index-reference-provider.ss t/qualification/ascent-index-reference-evaluate.ss t/performance/index-lifecycle-benchmark.ss tools/build-index-lifecycle-benchmark.ss > "$ASCENT_INDEX_LIFECYCLE_RECEIPT.sources"
    timeout 150s {{ gxi_command }} {{ gerbil_test_runtime_options }} tools/build-index-lifecycle-benchmark.ss
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    log="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/run.XXXXXX")"
    trap 'rm -f "$log"' EXIT
    GERBIL_LOADPATH="$ASCENT_INDEX_LIFECYCLE_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 30s {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/index-lifecycle/module-resolution.ss > "$ASCENT_INDEX_LIFECYCLE_RECEIPT.modules"
    test "$(grep -c '/.gerbil/index-lifecycle/lib/.*\.ssi$' "$ASCENT_INDEX_LIFECYCLE_RECEIPT.modules")" -eq 5
    GERBIL_LOADPATH="$ASCENT_INDEX_LIFECYCLE_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/index-lifecycle-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 7
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    grep -x 'OK' "$log" >/dev/null

result-benchmark: prepare-test-library
    {{ test_library_environment }} just _result-benchmark

_result-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    export ASCENT_RESULT_LIB="{{ justfile_directory() }}/.gerbil/result-publication/lib"
    export ASCENT_RESULT_RECEIPT="${ASCENT_RESULT_RECEIPT:-{{ justfile_directory() }}/.gerbil/result-publication/receipt.sexp}"
    mkdir -p .gerbil/result-publication
    shasum -a 256 program/result.ss program/evaluate.ss core/positive-plan.ss program/analysis.ss table/access.ss table/funs.ss table/storage.ss t/qualification/ascent-result-reference-evaluate.ss t/performance/result-benchmark.ss tools/build-result-benchmark.ss > "$ASCENT_RESULT_RECEIPT.sources"
    timeout 150s {{ gxi_command }} {{ gerbil_test_runtime_options }} tools/build-result-benchmark.ss
    mkdir -p "{{ justfile_directory() }}/.cache/ascent/tmp"
    log="$(mktemp "{{ justfile_directory() }}/.cache/ascent/tmp/run.XXXXXX")"
    trap 'rm -f "$log"' EXIT
    GERBIL_LOADPATH="$ASCENT_RESULT_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 30s {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/result-publication/module-resolution.ss > "$ASCENT_RESULT_RECEIPT.modules"
    test "$(grep -c '/.gerbil/result-publication/lib/.*\.ssi$' "$ASCENT_RESULT_RECEIPT.modules")" -eq 3
    GERBIL_LOADPATH="$ASCENT_RESULT_LIB${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 180s {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/result-benchmark.ss 2>&1 | tee "$log"
    test "$(grep -c '^RESULT ' "$log")" -eq 10
    if grep -E 'ERROR|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    grep -x 'OK' "$log" >/dev/null

# Matched finite temporal metadata cost; no speedup claim or added threshold.
temporal-scale:
    @timeout 90s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-temporal-scale-output.ss

# Visible import progress for the composed temporal proof dependency graph.
test-temporal:
    just test-file t/qualification/ascent-temporal-lens-test.ss

# Compile outside the runtime gate; std/make checks current source dependencies.
build-dsl-closure:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .cache/ascent/tmp
    export ASCENT_DSL_BUILD_TOKEN="$(mktemp .cache/ascent/tmp/build-owner.XXXXXX)"
    trap 'rm -f "$ASCENT_DSL_BUILD_TOKEN"' EXIT
    export ASCENT_DSL_BUILD_STARTED="$(date +%s)"
    export GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}"
    compiler=({{ gerbil_command }} env gxi)
    if [[ -n "${GERBIL_PATH:-}" ]]; then
        # The captured package environment is already explicit. Match gxpkg's
        # public env-exec PATH setup without starting its package CLI again.
        export PATH="$GERBIL_PATH/bin:$PATH"
        compiler=({{ gxi_command }})
    fi
    "${compiler[@]}" -:max-heap=3G,debug=q tools/build-test-library.ss dsl
    {{ gxi_command }} t/native/artifact-admission.ss finalize

# Counterbalanced measurements with independent Scheme truth; no speed threshold.
check-retained-benefit:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ gxi_command }} t/native/artifact-admission.ss check
    timeout 120s .cache/ascent/native-library/dsl-closure {{ gerbil_test_runtime_options }} --retained-benefit

# Run every known DSL Suite through std/test in one AOT process.
check-dsl-closure:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ gxi_command }} t/native/artifact-admission.ss check
    test -x .cache/ascent/native-library/dsl-closure
    mkdir -p .cache/ascent/tmp
    output_file="$(mktemp .cache/ascent/tmp/dsl.XXXXXX)"
    trap 'rm -f "$output_file"' EXIT
    timeout "${ASCENT_GXTEST_TIMEOUT:-120s}" .cache/ascent/native-library/dsl-closure {{ gerbil_test_runtime_options }} 2>&1 | tee "$output_file"
    if grep -E 'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi
    awk -f tools/assert-test-cases.awk "$output_file"
    test "$(grep -c '^MODULE-OK ' "$output_file")" -eq 15
    test "$(grep -c '^HARNESS-OK ' "$output_file")" -eq 1
    test "$(grep -cx 'OK' "$output_file")" -eq 1
