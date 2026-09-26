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
    output="$(GERBIL_LOADPATH="{{ justfile_directory() }}${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" timeout 120s gerbil {{ gerbil_test_runtime_options }} env gxtest "{{ path }}" 2>&1)" || { status=$?; printf '%s\n' "$output"; exit "$status"; }
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

ascent-pairs:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-binary-program-pairs.ss

ascent-guarded:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-binary-program-guarded.ss

ascent-candidates:
    @timeout 90s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-closure-candidates-output.ss

rule-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-rule-program-output.ss

aggregate-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-aggregate-program-output.ss

lattice-rows:
    @timeout 60s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-lattice-program-output.ss

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
    cargo test --locked --manifest-path rust/ascent-oracle/Cargo.toml
