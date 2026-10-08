#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
# Exercise process exits, discovered coverage and swallowed GxTest failures.
set -euo pipefail
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p .cache/ascent/tmp
export SOURCE_GATE_FIXTURE="$scratch"
cat > "$scratch/runner" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >> "$SOURCE_GATE_FIXTURE/roster"
for module in "$@"; do
    printf 'MODULE %s\n' "$module"
    if [[ "$SOURCE_GATE_MODE" != empty ]]; then
        printf 'CASE fixture\nCASE-OK fixture\n'
    fi
    printf 'MODULE-OK %s\n' "$module"
done
[[ "$SOURCE_GATE_MODE" != marker ]] || echo 'ERROR CHECK fixture'
echo 'HARNESS-OK fixture'
[[ "$SOURCE_GATE_MODE" == missing ]] || echo OK
[[ "$SOURCE_GATE_MODE" != exit ]] || exit 23
RUNNER
chmod +x "$scratch/runner"
for mode in pass exit marker missing empty; do
    export SOURCE_GATE_MODE="$mode"
    : > "$scratch/roster"
    status=0
    GERBIL_BUILD_CORES=3 bash tools/test-source-parallel.sh "$scratch/runner" > "$scratch/output" 2>&1 || status=$?
    if [[ "$mode" == pass ]]; then
        test "$status" -eq 0
        printf '%s\n' t/qualification/*-test.ss | sort > "$scratch/expected"
        sort "$scratch/roster" > "$scratch/actual"
        cmp "$scratch/expected" "$scratch/actual"
        grep -q '^SOURCE-TESTS-OK ' "$scratch/output"
    else
        test "$status" -ne 0
        ! grep -q '^SOURCE-TESTS-OK ' "$scratch/output"
        [[ "$mode" != exit ]] || test "$status" -eq 23
    fi
    printf 'SOURCE-GATE-CONTROL-OK %s\n' "$mode"
done
if GERBIL_BUILD_CORES=invalid bash tools/test-source-parallel.sh "$scratch/runner" > "$scratch/output" 2>&1; then
    exit 1
fi
echo 'SOURCE-GATE-CONTROL-OK invalid-capacity'
