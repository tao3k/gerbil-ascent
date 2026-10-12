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

# A new fixed study; the historical lookup baseline and its gates remain intact.
performance-uf-selected:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .cache/ascent/uf-selected-study
    study="$(mktemp -d "$PWD/.cache/ascent/uf-selected-study/run.XXXXXX")"
    timeout 120s {{ gxi_command }} -:max-heap=3G,debug=q t/performance/uf-lookup/selected-build.ss "$study" "{{ package_library }}"
    GERBIL_LOADPATH="$study/lib${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 90s {{ gxi_command }} -:max-heap=3G,debug=q :gerbil-ascent/t/performance/uf-lookup/runner all "$study/receipts" "$study/contract.sexp"

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
    test_args=(-v 5 "$test_module")
    if [[ -n "${ASCENT_TEST_LIBRARY:-}" ]]; then
        compiled="$ASCENT_TEST_LIBRARY/gerbil-ascent/${test_module%.ss}.ssi"
        test -f "$compiled"
        test_module="$compiled"
        test_args=(-v 5 "$test_module")
        runner=({{ gxi_command }} {{ gerbil_test_runtime_options }} :gerbil/tools/gxtest)
    elif [[ -d "$test_module" ]]; then
        runner=({{ gxi_command }} {{ gerbil_test_runtime_options }} t/native/test.ss batched "{{ heap }}")
        test_args=("$test_module")
    else
        runner=({{ gerbil_command }} -:max-heap={{ heap }},debug=q test)
    fi
    timeout "${ASCENT_GXTEST_TIMEOUT:-120s}" "${runner[@]}" "${test_args[@]}" 2>&1 | tee "$output_file"
    if grep -E 'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow' "$output_file" >/dev/null; then exit 1; fi
    awk -f "{{ justfile_directory() }}/t/native/assert-cases.awk" "$output_file"
    if [[ -d "$test_module" ]]; then grep -F 'MODULE-OK ' "$output_file" >/dev/null; else grep -Fx "MODULE-OK $test_module" "$output_file" >/dev/null; fi
    grep -F 'HARNESS-OK' "$output_file" >/dev/null
    grep -x 'OK' "$output_file" >/dev/null
    printf '[ascent-test] PASS %s (%ss)\n' "{{ path }}" "$((SECONDS - started))"

# Native GxTest owns every Suite; the Scheme pool uses GERBIL_BUILD_CORES for directories.
test heap='2G':
    ASCENT_GXTEST_TIMEOUT="${ASCENT_GXTEST_TIMEOUT:-180s}" just test-file t/qualification "{{ heap }}"

# One compiler invocation; upstream make owns threads, ordering and currentness.
prepare-test-library:
    {{ gxi_command }} -:max-heap=3G,debug=q t/native/build.ss library

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
    {{ test_library_environment }} timeout "${ASCENT_GXTEST_TIMEOUT:-120s}" {{ gxi_command }} -:max-heap=2G,debug=q t/native/test.ss isolated 2G "${modules[@]}" 2>&1 | tee "$output"
    if grep -E 'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow' "$output" >/dev/null; then exit 1; fi
    awk -f t/native/assert-cases.awk "$output"
    test "$(grep -c '^MODULE-OK ' "$output")" -eq "${#modules[@]}"
    grep -F 'HARNESS-OK' "$output" >/dev/null
    grep -x 'OK' "$output" >/dev/null

# Paired actor source transactions; evaluator work is outside this interval.
performance-source-cut: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss source-cut "{{ package_library }}"

# Paired complete actor rounds with wide ready queues and active assignments.
performance-actor-admission baseline='admission' lane='qualification': prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss actor-admission "{{ package_library }}" "{{ baseline }}" "{{ lane }}"

# Matched physical index build, extension and lookup with projection controls.
performance-index-projection: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss index-projection "{{ package_library }}"

# Complete fresh-engine expression execution, matched natively.
performance-expression-plan: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss expression-plan "{{ package_library }}"

# Complete positive proof production and independent replay, matched natively.
performance-proof-replay: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss proof-replay "{{ package_library }}"

# Cold typed-expression compilation with matched native semantic checks.
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

# Matched cold slot compilation and native traversal with shape controls.
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

# Paired ordered index build/extension/lookup and complete native solve control.
performance-index-build: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss index-build "{{ package_library }}"

# Paired persistent source-log kernels and complete public source transactions.
performance-source-log: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss source-log "{{ package_library }}"

# Paired native selected frames and complete dependency updates/append lifecycle.
performance-selected-activation: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss selected-activation "{{ package_library }}"

# Paired native storage batch preflight and complete retained-engine updates.
performance-storage-batch: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss storage-batch "{{ package_library }}"

# Paired native curried index build, extension and prefix/full reads.
performance-index-sharing: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss index-sharing "{{ package_library }}"

# Paired native engine-owned physical index entries and complete indexed solves.
performance-index-entry: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss index-entry "{{ package_library }}"

# Paired native general callbacks, ordered pattern bindings and complete solves.
performance-rule-bindings: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss rule-bindings "{{ package_library }}"

# Paired native finite evidence generation and verification.
performance-finite-replay: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss finite-replay "{{ package_library }}"

# Paired native inert traversal and complete certificate verification.
performance-bounded-datum: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss bounded-datum "{{ package_library }}"

# Paired native complete-provenance generation.
performance-provenance-index: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss provenance-index "{{ package_library }}"

# Paired native source-selection over compiled declaration dependencies.
performance-update-dependencies: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/run.ss update-dependencies "{{ package_library }}"

# Paired native index construction, extension and evaluated-key lookup.
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
check-native-evidence-conformance: prepare-quint
    mkdir -p .cache/ascent/native-evidence-conformance
    .cache/ascent/tools/quint/node_modules/.bin/quint repl -q --backend typescript -r packages/proofs/quint/NativeEvidenceLifecycle.qnt::NativeEvidenceLifecycle conformance .exit > .cache/ascent/native-evidence-conformance/quint.json
    cmp .cache/ascent/native-evidence-conformance/quint.json t/qualification/fixtures/native-evidence/conformance.json

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
    models+=(OwnedLookup WeightedExport RectangleCompaction RectangleExport ScopedWitness BranchScopedWitness ScopedComposition ScopedReachabilityMask ScopedQuery MovieCastQuery NativeEvidenceLifecycle NativeDslOwnership EvidenceCacheAdmission)
    case "$group" in
      all) ;;
      Nonmembership) models=(CertificateMaterial TerminalTraversal ExecutionFeedback Withholding ProofShapeAdmission ProofPrefix CountProbe NegativeProbe NumericProbe PositiveNonmembershipSession SessionTransaction NativeSessionPublication) ;;
      ProviderViews) models=(ProviderViews ReaderLifetime RectangleExport RectangleCompaction WeightedExport OwnedLookup) ;;
      *) found=0; for model in "${models[@]}"; do if [[ "$model" = "$group" ]]; then found=1; fi; done; [[ "$found" = 1 ]] || { echo "Unknown Quint feature: $group" >&2; exit 2; }; models=("$group") ;;
    esac
    export QUINT_HOME="$PWD/.cache/ascent/tools/quint-backends"
    export OUT_DIR="$PWD/.cache/ascent/quint-output"
    export no_proxy="127.0.0.1,localhost${no_proxy:+,$no_proxy}"
    export NO_PROXY="127.0.0.1,localhost${NO_PROXY:+,$NO_PROXY}"
    quint=.cache/ascent/tools/quint/node_modules/.bin/quint
    jar="$QUINT_HOME/apalache-dist-0.62.1/apalache/lib/apalache.jar"
    retain_run=0
    if [[ -n "${ASCENT_FORMAL_RUN_DIR:-}" ]]; then
      mkdir "$ASCENT_FORMAL_RUN_DIR"
      temp=$(cd "$ASCENT_FORMAL_RUN_DIR" && pwd)
      retain_run=1
    else
      temp=$(mktemp -d)
    fi
    server_pid=
    cleanup() {
      if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
      if [[ "$retain_run" = 0 ]]; then rm -rf "$temp"; fi
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
        NativeEvidenceLifecycle) constants="GenerationCutoff = $cutoff\nInputLimit = 0\nMutation = \"none\""; invariants='TypeOK CurrentResult IndependentExplanation FrozenObservation RejectionAtomic ClosedOwners'; constraint=ExplorationBound ;;
        NativeDslOwnership) constants='ScopeCapacity = 2\nMutation = "none"'; invariants='ChargedExpansion IsolatedDefinitions NoForeignReference LiveValues'; constraint=ExplorationBound ;;
        EvidenceCacheAdmission) constants='Mutation = "none"'; invariants='ExactSource ExactBackend ExactPolicy FailureRevoked LiveAdmission' ;;
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
        MovieCastQuery) constants='Mutation = "none"'; invariants='ExactEvidence ExactAnswer ExactTrace Private' ;;
        ScopedQuery) constants='Mutation = "none"'; invariants='ExactHops ExactReach ExactShortest ExactPredecessors ExactWitnesses ExactBranches ExactGroups ExactTraces Private' ;;
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
        OwnedLookup) constants='Mutation = "none"'; invariants='FrozenExact OrderedExact RejectedStable' ;;
        WeightedExport) constants='Mutation = "none"'; invariants='FrozenExact OrderedExact IndependentReads AxisExact CountExact SharedPlanExact' ;;
        RectangleCompaction) constants='Mutation = "none"'; invariants='OrderedExact WeightedCount IndependentReaders' ;;
        RectangleExport) constants='Mutation = "none"'; invariants='FrozenExact OrderedExact IndependentReads CountExact' ;;
        ProviderViews) constants="Rows = {0,1,2}\nBudget = 2\nMutation = \"none\"\nExplorationBound = $views_cutoff"; invariants='AtomicPublication FrozenRead ReaderAlive CurrentReply LogicalBudget'; constraint=Explore ;;
        ReaderLifetime) constants='Rows = {0,1,2}\nReaders = {1,2}\nBudget = 2\nMutation = "none"'; invariants='ReaderAlive AcceptedCurrent CreditBalance'; properties=ReaderCompletion; specification=spec ;;
        ReadyComponents) constants='Tasks = {1,2,3}\nCapacity = 2\nMutation = "none"'; invariants='Partition Prerequisites CapacityBound CompleteReturn DependencySnapshot CompletedDelivery' ;;
        TransitiveComponents) constants='Nodes = {1,2,3}\nMutation = "none"'; invariants='ReachExact SCCExact ParentRoots PrivateArcs RefusalAtomic ActiveExact DeltaExact ParentChains MemberPartition SizeExact WeightedDeltaExact DifferenceExact ExcessWeightExact SparseMassExact' ;;
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
            NativeEvidenceLifecycle) sed 's/InputLimit = 0/InputLimit = 1/' "$base" > "$temp/$model-finite.cfg"; execute caller-finite "$temp/$model-finite.cfg" 0; fault stale CurrentResult; fault coupled IndependentExplanation; fault rewrite FrozenObservation; fault reject RejectionAtomic; fault close ClosedOwners ;;
            NativeDslOwnership) fault scope IsolatedDefinitions; fault failed ChargedExpansion; fault reset ChargedExpansion; fault foreign NoForeignReference ;;
            EvidenceCacheAdmission) fault source ExactSource; fault backend ExactBackend; fault policy ExactPolicy; fault retain FailureRevoked ;;
            SessionTransaction) fault early AtomicSnapshot; fault stale NoStaleCommit 13; fault global AtomicSnapshot; fault reuse AtomicSnapshot ;;
            ProviderFrontier) sed 's/Seeded = FALSE/Seeded = TRUE/' "$base" > "$temp/seeded.cfg"; execute seeded "$temp/seeded.cfg" 0; sed 's/Fault = "none"/Fault = "overlap"/' "$base" > "$temp/overlap.cfg"; execute overlap "$temp/overlap.cfg" 0; fault raw FrontierComplete; fault foreign FrontierComplete; fault omit DeliveredExact; for mutation in early old initial replace; do fault "$mutation" ConsumerSnapshot; done ;;
            ProviderReplay) fault scope PublishedExact; fault early JournalExact; fault drop JournalExact; fault kind OrderExact; fault cut HeldExact; fault reject RefusalAtomic ;;
            ProviderAdmission) fault nocap MatchingExact; fault set MatchingExact; fault allwitness CountCaps; fault early NoEarlyCallbacks; fault borrow DetachedPacket; fault retain FailedCacheRevoked ;;
            ProviderRouting) for mutation in drop order representative prefix; do fault "$mutation" CompleteExact; done ;;
            OwnedLookup) fault export OrderedExact; fault order OrderedExact; fault empty OrderedExact; fault duplicate OrderedExact; fault shared OrderedExact; fault borrow FrozenExact; fault retire FrozenExact; fault reject RejectedStable ;;
            WeightedExport) fault selected-order AxisExact; fault plan-axis SharedPlanExact; fault order OrderedExact; fault alias FrozenExact; fault shared IndependentReads; fault axis AxisExact; fault mass CountExact ;;
            RectangleCompaction) fault heavy OrderedExact; fault order OrderedExact; fault alias OrderedExact; fault mass WeightedCount; fault shared IndependentReaders ;;
            RectangleExport) fault order OrderedExact; fault alias FrozenExact; fault shared IndependentReads ;;
            ProviderViews) fault alias FrozenRead; fault retire ReaderAlive; fault early AtomicPublication; fault stale CurrentReply; fault budget LogicalBudget ;;
            ReaderLifetime) for mutation in stuck unfair global; do fault "$mutation" ReaderCompletion 13; done; fault retire ReaderAlive; fault credit CreditBalance; fault aba AcceptedCurrent;
              sed -e 's/Readers = {1,2}/Readers = {1}/' -e 's/Mutation = "none"/Mutation = "global"/' "$base" > "$temp/single.cfg"; execute single-reader-global-fairness "$temp/single.cfg" 0;
              sed -e 's/SPECIFICATION spec/SPECIFICATION roundSpec/' -e 's/PROPERTIES ReaderCompletion/PROPERTIES ReaderCompletion RoundCompletion/' "$base" > "$temp/round.cfg"; execute sealed-round "$temp/round.cfg" 0;
              sed -e 's/Mutation = "none"/Mutation = "unfair"/' -e '/^INVARIANTS /d' -e '/^PROPERTIES /d' "$temp/round.cfg" > "$temp/round-unfair.cfg"; printf 'PROPERTY RoundCompletion\n' >> "$temp/round-unfair.cfg"; execute sealed-round-unfair "$temp/round-unfair.cfg" 13 RoundCompletion ;;
            ReadyComponents) for capacity in 1 3; do sed "s/Capacity = 2/Capacity = $capacity/" "$base" > "$temp/$model-capacity.cfg"; execute "capacity-$capacity" "$temp/$model-capacity.cfg" 0; done; fault prerequisite Prerequisites; fault early CompleteReturn; fault snapshot DependencySnapshot; fault tail CompletedDelivery; fault credit CompletedDelivery ;;
            TransitiveComponents) fault split SCCExact; fault stale ReachExact; fault reject RefusalAtomic; for mutation in raw diagonal old; do fault "$mutation" DeltaExact; done; fault chain ParentChains; fault members MemberPartition; fault size SizeExact; fault adjacency PrivateArcs; fault weight WeightedDeltaExact; fault excess ExcessWeightExact; fault sparseSelf SparseMassExact ;;
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
            MovieCastQuery) fault global ExactEvidence; fault early ExactEvidence; fault union ExactAnswer; fault forget ExactTrace ;;
            ScopedQuery) fault unbounded ExactHops; fault independentSides ExactWitnesses; fault global ExactWitnesses; fault forgetPredecessor ExactPredecessors; fault forgetTrace ExactTraces ;;
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
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss binding "{{ package_library }}"

strata-benchmark: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss strata "{{ package_library }}"

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
    awk -f t/native/assert-cases.awk "$output"
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

size-benchmark: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss size "{{ package_library }}"

# Whole-solve comparison against the committed narrow-frontier evaluator.
multi-frontier-benchmark: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss multi-frontier "{{ package_library }}"

set-size-benchmark: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss set-size "{{ package_library }}"

set-batch-benchmark: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss set-batch "{{ package_library }}"

set-emit-benchmark: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss set-emit "{{ package_library }}"

set-emit-allocation: prepare-test-library
    {{ test_library_environment }} {{ gxi_command }} {{ gerbil_test_runtime_options }} t/performance/reference-run.ss set-emit-allocation "{{ package_library }}"

set-source-allocation: prepare-test-library
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
    "${compiler[@]}" -:max-heap=3G,debug=q t/native/build.ss dsl
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
    awk -f t/native/assert-cases.awk "$output_file"
    test "$(grep -c '^MODULE-OK ' "$output_file")" -eq 15
    test "$(grep -c '^HARNESS-OK ' "$output_file")" -eq 1
    test "$(grep -cx 'OK' "$output_file")" -eq 1
