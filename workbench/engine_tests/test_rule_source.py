# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Native ASCENT text through the actual installed library, not a host compiler."""
import os
from pathlib import Path
import unittest
from unittest.mock import patch

from ascent_engine import Engine, EngineError


RULES = """(ascent-fragment
  (relation edge ((from symbol?) (to symbol?)))
  (relation bad ((value symbol?)))
  (relation path ((from symbol?) (to symbol?)))
  (relation usable ((from symbol?) (to symbol?)))
  ((path X Y) <-- (edge X Y))
  ((path X Y) <-- (edge X Z) (path Z Y))
  ((usable X Y) <-- (path X Y) (not (bad Y))))"""


class NativeRuleSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        library = None if os.environ.get("ASCENT_ENGINE_BACKEND") == "api" else os.environ.get(
            "ASCENT_ENGINE_LIBRARY", Path(__file__).parents[2] / ".gerbil/lib/libascent.dylib")
        cls.engine = Engine(library)

    def run_catalog(self, source, rows, queries):
        catalog = self.engine.read_rules(source)
        program = {**catalog, "queries": queries}
        for relation in program["relations"]:
            relation["rows"] = rows.get(relation["name"], [])
        with self.engine.open(program) as session:
            result = session.run()
        self.assertTrue(result["complete"])
        return result["relations"]

    def test_recursion_negation_and_python_only_consumer(self):
        with patch.dict(os.environ, {"PATH": "/unavailable", "GERBIL_PATH": "/unavailable"}), \
                patch("subprocess.Popen", side_effect=AssertionError("consumer invoked a compiler")):
            result = self.run_catalog(RULES,
                {"edge": [["a", "b"], ["b", "c"]], "bad": [["c"]]}, ["path", "usable"])
        self.assertCountEqual(result["path"], [["a", "b"], ["a", "c"], ["b", "c"]])
        self.assertEqual(result["usable"], [["a", "b"]])

    def test_checked_comparison_and_literal(self):
        source = """(ascent-fragment
          (relation input ((id exact-integer?) (tag symbol?)))
          (relation ordered ((left exact-integer?) (right exact-integer?)))
          ((ordered X Y) <-- (input X (lit 'selected)) (input Y Tag)
            (if (X Y) (< X Y))))"""
        result = self.run_catalog(source,
            {"input": [[1, "selected"], [2, "other"], [3, "selected"]]}, ["ordered"])
        self.assertCountEqual(result["ordered"], [[1, 2], [1, 3]])

    def test_fragment_merge_has_one_relation_contract(self):
        source = "(ascent-fragment (relation edge ((from symbol?) (to symbol?))))"
        catalog = self.engine.read_rules(source, RULES)
        self.assertEqual(1, sum(row["name"] == "edge" for row in catalog["relations"]))
        conflict = source.replace("from symbol?", "from exact-integer?")
        with self.assertRaises(EngineError):
            self.engine.read_rules(conflict, RULES)
        with self.assertRaises(EngineError):
            self.engine.read_rules(RULES, RULES)

    def test_reader_evaluation_sharing_and_host_code_are_rejected(self):
        invalid = ["(import :std/os/process)", "(begin (display 42))",
            "#.(begin (setenv \"ASCENT_READER_EXECUTED\" \"yes\") 1)",
            "#0=(ascent-fragment #0#)", RULES + " (display 42)",
            RULES.replace("symbol?", "(lambda (x) #t)", 1),
            RULES.replace("(not (bad Y))", "(guard (Y) (lambda (Y) #t))")]
        for source in invalid:
            with self.subTest(source=source), self.assertRaises(EngineError):
                self.engine.read_rules(source)
        self.assertNotIn("ASCENT_READER_EXECUTED", os.environ)
        self.assertTrue(self.engine.read_rules(RULES)["rules"])

    def test_native_semantic_admission_rejects_bad_arity_binding_and_strata(self):
        invalid = [RULES.replace("(edge X Y))", "(edge X))", 1),
            RULES.replace("((path X Y) <-- (edge X Y))", "((path X Missing) <-- (edge X Y))"),
            RULES.replace("(not (bad Y))", "(not (bad Missing))"),
            RULES.replace("(edge X Y)", "(missing X Y)", 1),
            """(ascent-fragment (relation input ((x symbol?)))
                 (relation result ((x symbol?)))
                 ((result X) <-- (input X) (not (result X))))"""]
        for source in invalid:
            with self.subTest(source=source), self.assertRaises(EngineError):
                self.engine.read_rules(source)

    def test_source_text_budgets_and_unsupported_terms_fail_closed(self):
        for sources in [(), (" " * 65537,), (RULES,) * 17,
                        (RULES.replace("(edge X Y)", "(edge _ Y)", 1),)]:
            with self.subTest(count=len(sources)), self.assertRaises(EngineError):
                self.engine.read_rules(*sources)


if __name__ == "__main__":
    unittest.main()
