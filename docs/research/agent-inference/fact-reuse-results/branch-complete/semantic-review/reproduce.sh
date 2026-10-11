#!/usr/bin/env bash
set -euo pipefail
artifact="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/ascent-semantic-review.XXXXXX")"
git clone --quiet --branch research/library-evidence-consumer "$artifact/source.bundle" "$work/source"
test "$(git -C "$work/source" rev-parse HEAD)" = 432d2d7fb8073849105de5cb91d649a6a160193f
export PYTHONPATH="$work/source/python/src"
unset DEEPSEEK_API_KEY
python3 "$artifact/replay.py" "$artifact" --check
python3 -m unittest discover -s "$work/source/python/tests" -p test_shared_premise.py
