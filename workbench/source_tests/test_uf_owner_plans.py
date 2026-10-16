# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Independent ordered products with explicitly shared Scheme owner identities."""
import hashlib
import itertools
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_uf_selector_init import sexp, truth

ROOT = Path(__file__).resolve().parents[2]


class UFOwnerPlanTests(unittest.TestCase):
    def test_shared_axes_and_owner_occurrences_through_original_scheme_api(self):
        cases = []
        axes = [[False, 0, 1], [False, 2], [0, 1]]
        for owners in itertools.product(range(3), repeat=3):
            for indexed in (False, True):
                for columns, keys in [([], []), ([1], [False]), ([2], [False]),
                                      ([1], [0]), ([2], [0]), ([2], [99]),
                                      ([1, 2], [False, 0]), ([2, 1], [0, False]),
                                      ([0, 2], [1, False]), ([1, 1], [False, 0]),
                                      ([1, 2, 1], [0, False, 0])]:
                    cases.append([axes, list(owners), columns, keys, indexed])
        source = ROOT / 'core/relation-view.ss'
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        cache = ROOT / '.cache/ascent/uf-owner-oracle'
        cache.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=cache) as directory:
            inputs = Path(directory) / 'cases.sexp'
            inputs.write_text(sexp(cases))
            child = subprocess.run(['gxi', '-:max-heap=1G,debug=q',
                                    't/qualification/fixtures/uf-owner-plans/observe.ss', str(inputs)],
                                   cwd=ROOT, env=dict(os.environ, GERBIL_PATH=str(ROOT / '.gerbil')),
                                   capture_output=True, text=True, timeout=45)
            (cache / 'native.stdout').write_text(child.stdout)
            (cache / 'native.stderr').write_text(child.stderr)
            self.assertEqual(child.returncode, 0, child.stderr)
            observed = json.loads(child.stdout)
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), digest)
        self.assertEqual(len(observed), len(cases))
        for (axes, owners, columns, keys, indexed), consumers in zip(cases, observed):
            blocks = [[[i], axes[owner], axes[owner]] for i, owner in enumerate(owners)]
            with self.subTest(owners=owners, columns=columns, keys=keys, indexed=indexed):
                self.assertEqual(consumers, [truth(blocks, columns, keys)] * 3)
        (cache / 'receipt.json').write_text(json.dumps({
            'sourceSha256': digest, 'cases': len(cases), 'consumers': 3,
            'status': 'pass', 'scope': 'shared-owner Scheme source, not a Rust wheel'}, indent=2) + '\n')
