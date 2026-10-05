#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
set -euo pipefail

cd "$(dirname "$0")/.."
jobs="${1:-2}"
if [[ "$#" -gt 1 || ! "$jobs" =~ ^[1-9][0-9]*$ ]]; then
    printf 'usage: bash tools/check-mvp.sh [positive-worker-count]\n' >&2
    exit 2
fi

# The Scheme runner owns compilation, source/carrier binding, admission,
# Case verdicts, process isolation, failure propagation and worker draining.
# These are existing native scenarios, not a second semantic harness.
export GERBIL_LOADPATH="$PWD${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}"
gerbil env gxi -:max-heap=1G,debug=q t/harness/run.ss test-pool "$jobs" \
    t/qualification/scheme-library-contract-test.ss \
    t/qualification/scheme-closure-contract-test.ss \
    t/qualification/scheme-session-deletion-test.ss \
    t/qualification/ascent-finite-evidence-test.ss \
    t/qualification/ascent-positive-nonmembership-test.ss \
    t/qualification/ascent-actor-session-test.ss \
    t/qualification/ascent-byods-invariants-test.ss

# Artifact tamper controls retain their exclusive lane. Do not promote a
# module to parallel admission merely because this profile selects it.
gerbil env gxi -:max-heap=1G,debug=q t/harness/run.ss test-pool 1 \
    t/qualification/scheme-artifact-test.ss

printf 'MVP-NATIVE-OK modules=8 modelCalls=0 rustRuntime=false\n'
