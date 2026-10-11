#!/bin/sh
set -eu
artifact=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ascent-shared-replay.XXXXXX")
tar -xzf "$artifact/raw.tar.gz" -C "$work"
mkdir "$work/source"
cp -R "$work/frozen/inputs/." "$work/source/"
export PYTHONPATH="$work/source/python/src:$work/frozen/api-runtime"
# Caller supplies a compatible local Darwin CPython/CFFI environment; no provider is called.
"${PYTHON:-python3}" -m ascent_test_support.evidence_chain_study shared-check "$work/frozen" "$work/run"
"${PYTHON:-python3}" -m ascent_test_support.evidence_chain_study shared-report "$work/frozen" "$work/run"
cmp "$artifact/report.json" "$work/run/report.json"
printf 'REPLAY-OK %s\n' "$work"
