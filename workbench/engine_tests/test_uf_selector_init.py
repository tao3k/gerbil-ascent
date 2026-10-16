# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Independent finite oracle against the original public Scheme query API.

This exercises Scheme source admission directly. Rust wheel semantics and AOT
performance remain separate checks; no historical wheel is relabeled current.
"""
import hashlib
import itertools
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def sexp(value):
    if isinstance(value, list):
        return '(' + ' '.join(map(sexp, value)) + ')'
    if value is False:
        return '#f'
    if isinstance(value, (int, float)):
        return repr(value)
    return json.dumps(value)


def truth(blocks, columns, keys):
    if len(columns) != len(keys) or any(type(c) is not int or c < 0 for c in columns):
        return ['rejected']
    width = len(blocks[0][0]) + 2
    if any(c >= width for c in columns):
        return ['rejected']
    rows = [prefix + [left, right] for prefix, xs, ys in blocks for left in xs for right in ys]
    # Scheme distinguishes #f from numeric zero. Python equality alone does not.
    def same(a, b):
        return type(a) is type(b) and a == b
    return ['accepted', [r for r in rows if all(same(r[c], k) for c, k in zip(columns, keys))]]


class UFSelectorInitTests(unittest.TestCase):
    def test_complete_queries_and_rejected_suffixes_match_native_api(self):
        cases = []
        for grouped in (False, True):
            blocks = [[([g] if grouped else []), [False, 0, 1], [False, 0, 1]]
                      for g in range(4)]
            # Distinct group descriptors; binary descriptors use disjoint owners.
            if not grouped:
                blocks = [[[], [g * 3, g * 3 + 1], [g * 3, g * 3 + 1]] for g in range(4)]
            width = 3 if grouped else 2
            for columns in itertools.product(range(width), repeat=3):
                for values in itertools.product((False, 0, 1), repeat=3):
                    cases.append([blocks, list(columns), list(values)])
            for columns, keys in [([0, 0, width], [0, 1, 0]),
                                  ([0, 0, -1], [0, 1, 0]),
                                  ([0, 0, 'bad'], [0, 1, 0]),
                                  ([0, 0, 1], [0, 1]),
                                  ([0, 0], [0, 1, 0]),
                                  ([0, 0, 1.0], [0, 1, 0]),
                                  ([0, width, -1], [99, 0, 0])]:
                cases.append([blocks, columns, keys])
            cases.append([blocks, [width - 2, width - 1] * 32, [0, 1] * 32])
        source = ROOT / 'core/relation-view.ss'
        before = hashlib.sha256(source.read_bytes()).hexdigest()
        cache = ROOT / '.cache/ascent/uf-selector-oracle'
        cache.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=cache) as directory:
            input_file = Path(directory) / 'cases.sexp'
            input_file.write_text(sexp(cases))
            env = dict(os.environ, GERBIL_PATH=str(ROOT / '.gerbil'))
            child = subprocess.run(['gxi', '-:max-heap=1G,debug=q',
                                    't/qualification/fixtures/uf-selector-init/observe.ss', str(input_file)],
                                   cwd=ROOT, env=env, capture_output=True, text=True, timeout=45)
            (cache / 'native.stdout').write_text(child.stdout)
            (cache / 'native.stderr').write_text(child.stderr)
            self.assertEqual(child.returncode, 0, child.stderr)
            observed = json.loads(child.stdout)
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), before)
        self.assertEqual(len(observed), len(cases))
        for case, consumers in zip(cases, observed):
            with self.subTest(columns=case[1], keys=case[2]):
                expected = truth(*case)
                self.assertEqual(consumers, [expected] * 3)
        (cache / 'receipt.json').write_text(json.dumps({
            'sourceSha256': before, 'cases': len(cases), 'consumers': 3,
            'status': 'pass', 'scope': 'public Scheme API, not a rebuilt Rust wheel'}, indent=2) + '\n')
