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
    @timeout 15s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-rule-program-output.ss

aggregate-rows:
    @timeout 15s gerbil {{ gerbil_test_runtime_options }} t/qualification/ascent-aggregate-program-output.ss

oracle:
    cargo test --locked --manifest-path rust/ascent-oracle/Cargo.toml
