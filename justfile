# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

set shell := ["bash", "-euo", "pipefail", "-c"]

# Match the repository's mrr-gerbil environment boundary. Homebrew's configured
# compiler must not inherit Nix compiler flags, tools, or its macOS SDK. Resolve the
# active Homebrew OpenSSL library after clearing inherited search paths; Gerbil
# release metadata can retain a removed Cellar directory after a formula upgrade.
gerbil_environment := if os() == "macos" {
    "env -u CC -u CFLAGS -u CPPFLAGS -u LDFLAGS -u CPATH -u C_INCLUDE_PATH -u CPLUS_INCLUDE_PATH -u LIBRARY_PATH -u NIX_CFLAGS_COMPILE -u NIX_LDFLAGS -u DEVELOPER_DIR -u SDKROOT PATH=\"/usr/bin:/bin:$PATH\" LIBRARY_PATH=\"$(brew --prefix openssl@3)/lib\""
} else { "env" }
gerbil_command := gerbil_environment + " gerbil"
# gxpkg env only selects the package prefix and prepends its bin directory.
# The captured environment already fixes the toolchain; apply that boundary
# directly instead of importing the package-management CLI for every script.
gerbil_package_prefix := '${GERBIL_PATH:-' + justfile_directory() + '/.gerbil}'
gxi_command := gerbil_environment + ' GERBIL_PATH="' + gerbil_package_prefix + '" PATH="' + gerbil_package_prefix + '/bin:/usr/bin:/bin:$PATH" gxi'

# Production, tests and AOT objects share the standard package library.
package_library := gerbil_package_prefix + '/lib'

# Compilation is bounded by real inactivity, not optimized-build wall time.
# Runtime scenarios retain their separate fixed deadlines in the compiled runner.
build_supervisor := 'PYTHONPATH="' + justfile_directory() + '/workbench/src" python3 -m ascent_workbench.supervision --cpu-progress --'
test_supervisor := 'PYTHONPATH="' + justfile_directory() + '/workbench/src" python3 -m ascent_workbench.supervision'

gerbil_test_runtime_options := "-:max-heap=1G,debug=q"
# BEGIN GENERATED PREPARATION HEAP
preparation_runtime_options := "-:max-heap=3G,live-ratio=50,debug=q"
# END GENERATED PREPARATION HEAP
test_library_environment := 'GERBIL_PATH="' + gerbil_package_prefix + '" ASCENT_TEST_LIBRARY="' + gerbil_package_prefix + '/lib" ASCENT_PERFORMANCE_MODULES="' + justfile_directory() + '/.cache/ascent/compiled-library/modules.sexp" GERBIL_LOADPATH="' + gerbil_package_prefix + '/lib:' + justfile_directory() + '${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" '

default:
    @just --list

# Use the SDK package entrypoint; it owns profile flags and build dispatch.
build:
    GERBIL_BUILD_CORES="${GERBIL_BUILD_CORES:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || getconf NPROCESSORS_ONLN)}" {{ gerbil_command }} build

# Linked production closure; upstream REPL utilities handle source reloads.
develop:
    {{ gerbil_environment }} GERBIL_PATH="{{ gerbil_package_prefix }}" "{{ gerbil_package_prefix }}/bin/ascent-develop"

check-policy:
    ASP_GERBIL_SCHEME_POLICY=1 GERBIL_BUILD_CORES="${GERBIL_BUILD_CORES:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || getconf NPROCESSORS_ONLN)}" {{ gerbil_command }} build

# A new fixed study; the historical lookup baseline and its gates remain intact.
performance-uf-selected:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .cache/ascent/uf-selected-study
    study="$(mktemp -d "$PWD/.cache/ascent/uf-selected-study/run.XXXXXX")"
    {{ build_supervisor }} {{ gxi_command }} -:max-heap=3G,debug=q t/performance/uf-lookup/selected-build.ss "$study" "{{ package_library }}"
    GERBIL_LOADPATH="$study/lib${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 90s {{ gxi_command }} -:max-heap=3G,debug=q :gerbil-ascent/t/performance/uf-lookup/runner all "$study/receipts" "$study/contract.sexp"

# Runtime source loading is a separate gate from compiled compiled qualification.
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
    test_args=(-v 5 "$test_module")
    if [[ -n "${ASCENT_TEST_LIBRARY:-}" ]]; then
        compiled="$ASCENT_TEST_LIBRARY/gerbil-ascent/${test_module%.ss}.ssi"
        test -f "$compiled"
        test_module="$compiled"
        test_args=(-v 5 "$test_module")
        runner=({{ gxi_command }} {{ gerbil_test_runtime_options }} :gerbil/tools/gxtest)
    elif [[ -d "$test_module" ]]; then
        # BEGIN GENERATED PREPARATION RUNNER
        runner=({{ gxi_command }} {{ gerbil_test_runtime_options }} t/harness/test.ss batched "{{ heap }}")
        # END GENERATED PREPARATION RUNNER
        test_args=("$test_module")
    else
        runner=({{ gerbil_command }} -:max-heap={{ heap }},debug=q test)
    fi
    inactivity="${ASCENT_GXTEST_TIMEOUT:-120s}"
    inactivity="${inactivity%s}"
    {{ test_supervisor }} --startup-seconds "$inactivity" --idle-seconds "$inactivity" -- "${runner[@]}" "${test_args[@]}" 2>&1 | tee "$output_file"
    if grep -E 'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi
    awk -f "{{ justfile_directory() }}/t/harness/assert-cases.awk" "$output_file"
    if [[ -d "$test_module" ]]; then grep -F 'MODULE-OK ' "$output_file" >/dev/null; else grep -Fx "MODULE-OK $test_module" "$output_file" >/dev/null; fi
    grep -F 'HARNESS-OK' "$output_file" >/dev/null
    grep -x 'OK' "$output_file" >/dev/null
    printf '[ascent-test] PASS %s (%ss)\n' "{{ path }}" "$((SECONDS - started))"

# Scheme GxTest owns every Suite; the Scheme pool uses GERBIL_BUILD_CORES for directories.
test heap='2G': prepare-semantic-library
    ASCENT_GXTEST_TIMEOUT="${ASCENT_GXTEST_TIMEOUT:-180s}" just test-file t/qualification "{{ heap }}"

# One compiler invocation; upstream make owns threads, ordering and currentness.
prepare-test-library:
    {{ build_supervisor }} {{ gxi_command }} {{ preparation_runtime_options }} t/harness/build.ss library

# Prepare the source Suite dependencies; GxTest still loads every Suite source.
prepare-semantic-library:
    {{ build_supervisor }} {{ gxi_command }} {{ preparation_runtime_options }} t/harness/build.ss semantics t/qualification/*-test.ss

# Scheme performance Suites use the declared Gerbil testing isolation profile.
test-performance-contracts: prepare-test-library
    #!/usr/bin/env bash
    set -euo pipefail
    output="$(mktemp)"
    trap 'rm -f "$output"' EXIT
    library="{{ package_library }}/gerbil-ascent/t/performance"
    modules=()
    for name in ascent-withdrawal-support-performance ascent-uf-plan-performance ascent-change-plan-performance ascent-source-cut-allocation ascent-component-index-performance ascent-actor-credit-performance ascent-trrel-uf-performance ascent-steensgaard-performance ascent-relation-view-performance scheme-library-lifecycle-performance; do
        modules+=("$library/$name-test.ssi")
    done
    {{ test_library_environment }} timeout "${ASCENT_GXTEST_TIMEOUT:-120s}" {{ gxi_command }} -:max-heap=2G,debug=q t/harness/test.ss isolated 2G "${modules[@]}" 2>&1 | tee "$output"
    if grep -E 'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow' "$output" >/dev/null; then exit 1; fi
    awk -f t/harness/assert-cases.awk "$output"
    test "$(grep -c '^MODULE-OK ' "$output")" -eq "${#modules[@]}"
    grep -F 'HARNESS-OK' "$output" >/dev/null
    grep -x 'OK' "$output" >/dev/null

# Compiled paired weighted view controls and complete delta export.
performance-uf-weighted: prepare-test-library
    {{ test_library_environment }} {{ build_supervisor }} {{ gxi_command }} -:max-heap=3G,debug=q t/performance/run.ss uf-weighted "{{ package_library }}"

performance-uf-membership: prepare-test-library
    {{ test_library_environment }} {{ build_supervisor }} {{ gxi_command }} -:max-heap=3G,debug=q t/performance/run.ss uf-membership "{{ package_library }}"

performance-uf-query: prepare-test-library
    {{ test_library_environment }} {{ build_supervisor }} {{ gxi_command }} -:max-heap=3G,debug=q t/performance/run.ss uf-query "{{ package_library }}"

performance-uf-selector-init: prepare-test-library
    {{ test_library_environment }} {{ build_supervisor }} {{ gxi_command }} -:max-heap=3G,debug=q t/performance/run.ss uf-selector-init "{{ package_library }}"

performance-uf-owner-plans: prepare-test-library
    {{ test_library_environment }} {{ build_supervisor }} {{ gxi_command }} -:max-heap=3G,debug=q t/performance/run.ss uf-owner-plans "{{ package_library }}"

performance-uf-compact-query: prepare-test-library
    {{ test_library_environment }} {{ build_supervisor }} {{ gxi_command }} -:max-heap=3G,debug=q t/performance/run.ss uf-compact-query "{{ package_library }}"

performance-uf-initialization: prepare-test-library
    {{ test_library_environment }} {{ build_supervisor }} {{ gxi_command }} -:max-heap=3G,debug=q t/performance/run.ss uf-initialization "{{ package_library }}"

performance-uf-plan: prepare-test-library
    {{ test_library_environment }} {{ build_supervisor }} {{ gxi_command }} -:max-heap=3G,debug=q t/performance/run.ss uf-plan "{{ package_library }}"

# Paired actor source transactions; evaluator work is outside this interval.
performance-source-cut: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss source-cut "{{ package_library }}"

# Paired complete actor rounds with wide ready queues and active assignments.
performance-actor-admission baseline='admission' lane='qualification': prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss actor-admission "{{ package_library }}" "{{ baseline }}" "{{ lane }}"

# Matched physical index build, extension and lookup with projection controls.
performance-index-projection: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss index-projection "{{ package_library }}"

# Complete fresh-engine expression execution, matched directly.
performance-expression-plan: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss expression-plan "{{ package_library }}"

# Complete positive proof production and independent replay, matched directly.
performance-proof-replay: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss proof-replay "{{ package_library }}"

# Cold typed-expression compilation with matched compiled semantic checks.
performance-typed-domain: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss typed-domain "{{ package_library }}"

# Matched complete independent absence verification using the public ASP API.
performance-nonmembership-index: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss nonmembership-index "{{ package_library }}"

# Matched complete temporal projection through the public ASP benchmark API.
performance-temporal-projection: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss temporal-projection "{{ package_library }}"

# Matched SCC commit and complete construction control through ASP benchmarks.
performance-uf-commit: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss uf-commit "{{ package_library }}"

# Matched cold slot compilation and compiled traversal with shape controls.
performance-slot-projection: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss slot-projection "{{ package_library }}"

# Matched full proof production, replay and checker with source controls.
performance-stratified-model: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss stratified-model "{{ package_library }}"

# Matched complete operator compilation with shared lexical dependencies.
performance-operator-scope: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss operator-scope "{{ package_library }}"

# Grounded provenance maintenance with independent frozen semantics.
performance-provenance-maintenance: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss provenance-maintenance "{{ package_library }}"

performance-component-workspace: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss component-workspace "{{ package_library }}"

performance-component-scope: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss component-scope "{{ package_library }}"

# Paired strict-dependency admission and complete cold/warm public solves.
performance-strata-preflight: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss strata-preflight "{{ package_library }}"

# Paired ordered index build/extension/lookup and complete compiled solve control.
performance-index-build: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss index-build "{{ package_library }}"

# Paired persistent source-log kernels and complete public source transactions.
performance-source-log: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss source-log "{{ package_library }}"

# Paired compiled selected frames and complete dependency updates/append lifecycle.
performance-selected-activation: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss selected-activation "{{ package_library }}"

# Paired compiled storage batch preflight and complete retained-engine updates.
performance-storage-batch: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss storage-batch "{{ package_library }}"

# Paired compiled curried index build, extension and prefix/full reads.
performance-index-sharing: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss index-sharing "{{ package_library }}"

# Paired compiled engine-owned physical index entries and complete indexed solves.
performance-index-entry: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss index-entry "{{ package_library }}"

# Paired compiled general callbacks, ordered pattern bindings and complete solves.
performance-rule-bindings: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss rule-bindings "{{ package_library }}"

# Paired compiled finite evidence generation and verification.
performance-finite-replay: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss finite-replay "{{ package_library }}"

# Paired compiled inert traversal and complete certificate verification.
performance-bounded-datum: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss bounded-datum "{{ package_library }}"

# Paired compiled complete-provenance generation.
performance-provenance-index: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss provenance-index "{{ package_library }}"

# Paired compiled source-selection over compiled declaration dependencies.
performance-update-dependencies: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss update-dependencies "{{ package_library }}"

# Paired compiled index construction, extension and evaluated-key lookup.
performance-scalar-index: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss scalar-index "{{ package_library }}"

performance-finite-mapping: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss finite-mapping "{{ package_library }}"

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

check-retained-inference-conformance: prepare-quint
    mkdir -p .cache/ascent/retained-inference-conformance
    .cache/ascent/tools/quint/node_modules/.bin/quint repl -q --backend typescript -r packages/proofs/quint/RetainedInference.qnt::RetainedInference conformance .exit > .cache/ascent/retained-inference-conformance/quint.json
    cd packages/proofs/lean && lake env lean --run RetainedInference.lean ../../../.cache/ascent/retained-inference-conformance/quint.json ../../../t/qualification/fixtures/inference-reuse/conformance.json

check-materialized-movie-conformance: prepare-quint check-retained-inference-conformance
    mkdir -p .cache/ascent/complex-movie-conformance
    .cache/ascent/tools/quint/node_modules/.bin/quint repl -q --backend typescript -r packages/proofs/quint/MaterializedMovieQuery.qnt::MaterializedMovieQuery conformance .exit > .cache/ascent/complex-movie-conformance/quint.json
    cd packages/proofs/lean && lake env lean --run MaterializedMovieQuery.lean ../../../.cache/ascent/complex-movie-conformance/quint.json ../../../t/qualification/fixtures/complex-movie/conformance.json

check-movie-cast-conformance: prepare-quint check-materialized-movie-conformance
    mkdir -p .cache/ascent/movie-cast-conformance
    .cache/ascent/tools/quint/node_modules/.bin/quint repl -q --backend typescript -r packages/proofs/quint/MovieCastQuery.qnt::MovieCastQuery conformance .exit > .cache/ascent/movie-cast-conformance/quint.json
    cd packages/proofs/lean && lake build MovieCastQuery && lake env lean --run MovieCastQueryConformance.lean ../../../.cache/ascent/movie-cast-conformance/quint.json ../../../t/qualification/fixtures/movie-cast/conformance.json

check-scoped-query-conformance: prepare-quint
    mkdir -p .cache/ascent/scoped-query-conformance
    .cache/ascent/tools/quint/node_modules/.bin/quint repl -q --backend typescript -r packages/proofs/quint/ScopedQuery.qnt::ScopedQuery conformance .exit > .cache/ascent/scoped-query-conformance/quint.json
    cd packages/proofs/lean && lake build ScopedQuery && lake env lean --run ScopedQueryConformance.lean ../../../.cache/ascent/scoped-query-conformance/quint.json ../../../t/qualification/fixtures/scoped-query/conformance.json

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

# Library-maintainer gate; no Quint toolchain is required by Python consumers.


# Restore the declared dependency before importing its process Guard.
prepare-lean:
    cd packages/proofs/lean && timeout --kill-after=3s 30s lake update LeanPoo

# Run each focused check through the locked LeanPoo process Guard.
check-lean-file file: prepare-lean
    cd packages/proofs/lean && PYTHONPATH="{{justfile_directory()}}/workbench/src" python3 -m ascent_workbench.lean_guard file "{{file}}"

check-lean-proofs: prepare-lean
    cd packages/proofs/lean && PYTHONPATH="{{justfile_directory()}}/workbench/src" python3 -m ascent_workbench.lean_guard build

# Install the locked Quint tool and checksum-pinned compiler/checker backend once.
prepare-quint:
    bash packages/proofs/quint/prepare.sh

# Lean kernel checking and exhaustive Quint protocol exploration are independent.
# Both parent exit statuses are required; cached model results are never reused.
check-formal: prepare-lean prepare-quint
    PYTHONPATH=workbench/src:python/src python3 -m ascent_workbench.formal all

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
    PYTHONPATH=workbench/src:python/src python3 -m ascent_workbench.formal quint "{{ group }}"

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

# Exact-set gate and matched exploratory timing for compiled retained updates.
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
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss binding "{{ package_library }}"

strata-benchmark: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss strata "{{ package_library }}"

# Run one unchanged SS fixture through the compiled qualification harness.
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
    awk -f t/harness/assert-cases.awk "$output"
    test "$(grep -c '^MODULE-OK ' "$output")" -eq 3
    grep -F 'HARNESS-OK' "$output" >/dev/null
    grep -x 'OK' "$output" >/dev/null

check-model-source-closure:
    {{ gxi_command }} t/harness/artifact-admission.ss check
    {{ test_library_environment }} timeout 120s .cache/ascent/compiled-library/dsl-closure {{ gerbil_test_runtime_options }} --source-closure

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
    @timeout 90s .cache/ascent/compiled-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle byods-lattice-session

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
    @timeout 90s .cache/ascent/compiled-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle integrated-corpus

mutual-corpus-rows:
    @timeout 120s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-mutual-program-output.ss

lattice-session-corpus-rows:
    @timeout 120s .cache/ascent/compiled-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle lattice-session

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

_oracle-scheme name *flags:
    @timeout 90s .cache/ascent/compiled-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle {{ name }} {{ flags }}

eqrel-rows:
    @just _oracle-scheme eqrel-program

eqrel-scale-rows:
    @just _oracle-scheme eqrel-program scale

eqrel-default-rows:
    @just _oracle-scheme eqrel-program default

trrel-rows:
    @just _oracle-scheme eqrel-program trrel

trrel-scale-rows:
    @just _oracle-scheme eqrel-program trrel scale

trrel-uf-rows:
    @just _oracle-scheme eqrel-program trrel-uf

trrel-uf-scale-rows:
    @just _oracle-scheme eqrel-program trrel-uf scale

byods-query-rows:
    @just _oracle-scheme byods-query

typed-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-typed-program-output.ss

module-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-module-program-output.ss

mutual-rows:
    @timeout 60s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-mutual-program-output.ss

scc-order-rows:
    @timeout 90s {{ gerbil_command }} {{ gerbil_test_runtime_options }} t/qualification/ascent-scc-order-output.ss

arity-repetition-rows:
    @timeout 90s .cache/ascent/compiled-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle arity-repetition

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
    @timeout 90s .cache/ascent/compiled-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle multi-source-session

byods-session-rows:
    @timeout 90s .cache/ascent/compiled-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle byods-session

# Verify the immutable paper input envelope before the compiled complete count.
steensgaard-data directory='.cache/ascent/paper-data/steensgaard':
    @PYTHONPATH="{{ justfile_directory() }}/workbench/src:{{ justfile_directory() }}/python/src" python3 -m ascent_workbench.paper_source "{{ directory }}" t/fixtures/paper-inputs/openjdk-source.json
    @just _oracle-scheme steensgaard-data "{{ directory }}" 440438706

steensgaard-rows:
    @just _oracle-scheme steensgaard

grouped-eqrel-session-rows:
    @timeout 90s .cache/ascent/compiled-library/dsl-closure {{ gerbil_test_runtime_options }} --oracle grouped-eqrel-session

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
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss size "{{ package_library }}"

# Whole-solve comparison against the committed narrow-frontier evaluator.
multi-frontier-benchmark:
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss multi-frontier "{{ package_library }}"

set-size-benchmark:
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss set-size "{{ package_library }}"

set-batch-benchmark:
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss set-batch "{{ package_library }}"

set-emit-benchmark:
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss set-emit "{{ package_library }}"

set-emit-allocation:
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss set-emit-allocation "{{ package_library }}"

set-source-allocation:
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss set-source-allocation "{{ package_library }}"

# Whole-solve positive rule plans: ordered semantics, allocation and raw timing.
positive-plan-benchmark: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss positive-plan "{{ package_library }}"

workspace-benchmark: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss workspace "{{ package_library }}"

ordered-relations-benchmark: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/ordered-relations/qualify.ss

materialization-benchmark: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss materialization "{{ package_library }}"

index-lifecycle-benchmark: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss index-lifecycle "{{ package_library }}"

result-benchmark: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss result "{{ package_library }}"

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
    "${compiler[@]}" -:max-heap=3G,debug=q t/harness/build.ss dsl
    {{ gxi_command }} t/harness/artifact-admission.ss finalize

# Counterbalanced measurements with independent Scheme truth; no speed threshold.
check-retained-benefit:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ gxi_command }} t/harness/artifact-admission.ss check
    timeout 120s .cache/ascent/compiled-library/dsl-closure {{ gerbil_test_runtime_options }} --retained-benefit

# Run every known DSL Suite through std/test in one AOT process.
check-dsl-closure:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ gxi_command }} t/harness/artifact-admission.ss check
    test -x .cache/ascent/compiled-library/dsl-closure
    mkdir -p .cache/ascent/tmp
    output_file="$(mktemp .cache/ascent/tmp/dsl.XXXXXX)"
    trap 'rm -f "$output_file"' EXIT
    timeout "${ASCENT_GXTEST_TIMEOUT:-120s}" .cache/ascent/compiled-library/dsl-closure {{ gerbil_test_runtime_options }} 2>&1 | tee "$output_file"
    if grep -E 'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi
    awk -f t/harness/assert-cases.awk "$output_file"
    test "$(grep -c '^MODULE-OK ' "$output_file")" -eq 15
    test "$(grep -c '^HARNESS-OK ' "$output_file")" -eq 1
    test "$(grep -cx 'OK' "$output_file")" -eq 1

check-rule-conformance: prepare-quint
    mkdir -p .cache/ascent/rule-conformance
    .cache/ascent/tools/quint/node_modules/.bin/quint repl -q --backend typescript -r packages/proofs/quint/EvidenceLifecycle.qnt::EvidenceLifecycle conformance .exit > .cache/ascent/rule-conformance/quint.json
    cmp .cache/ascent/rule-conformance/quint.json t/qualification/fixtures/evidence-lifecycle/conformance.json
