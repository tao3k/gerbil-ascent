# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

from ascent import Engine, EngineError, ResourceLimitError
from ascent.datalog import read_datalog, evaluate_datalog as evaluate
from ascent.derivations import EvidenceChain


class TranslationTests(unittest.TestCase):
    def test_inferred_types_reject_mixed_and_join_conflicts(self):
        for facts in ({"a": [[1], ["1"]], "b": []},
                      {"a": [[True]], "b": [[1]]}):
            with self.assertRaisesRegex(ValueError, "incompatible"):
                read_datalog(facts, "out(X) <= a(X) & b(X)",
                                {"answer": "out(X)"}, schema="infer")

    def test_empty_numeric_relations_get_types_from_operator_constraints(self):
        program, _ = read_datalog({"a": []}, "out(X) <= a(X) & (X < 10)",
                                     {"answer": "out(X)"}, schema="infer")
        self.assertTrue(all(r["columns"] == [{"kind": "integer"}] for r in program["relations"]))

    def test_scalar_types_remain_distinct(self):
        program, _ = read_datalog({"input": [[1], ["1"]]},
                                     "result(X) <= input(X)", {"answer": "result(X)"})
        self.assertEqual(program["relations"][0]["rows"], [[1], ['1']])
        self.assertEqual(program["relations"][0]["columns"],[{"kind":"value"}])

    def test_dependency_slice_includes_every_alternative_and_negative_premise(self):
        program, _ = read_datalog({"a": [], "b": [], "deny": [], "noise": []},
            "out(X) <= a(X) & ~deny(X)\nout(X) <= b(X)\nunused(X) <= noise(X) & (X < 1)",
            {"answer": "out(X)"})
        self.assertEqual({r["name"] for r in program["relations"]}, {"out", "a", "b", "deny"})
        self.assertEqual(len(program["rules"]), 2)

    def test_unsupported_or_unsafe_rules_fail_closed(self):
        for rule in ("out(X) <= a(X) & (X < 1)", "out(X) <= ~a(X)",
                     "out(X) <= a(X + 1)", "out(X) <= missing(X)",
                     "out(X) <= a(X)\nout(X,Y) <= a(X) & a(Y)"):
            with self.subTest(rule=rule), self.assertRaises(ValueError):
                read_datalog({"a": []}, rule, {"answer": "out(X)"})

    def test_source_authority_and_query_projection_cannot_change(self):
        with self.assertRaisesRegex(ValueError, "source facts"):
            read_datalog({"a": [], "out": [["forged"]]}, "out(X) <= a(X)", {"a": "out(X)"})
        with self.assertRaisesRegex(ValueError, "distinct"):
            read_datalog({"a": []}, "out(X,Y) <= a(X) & a(Y)", {"a": "out(X,X)"})


class NativeDatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine=Engine()

    @classmethod
    def tearDownClass(cls):cls.engine.shutdown()

    def test_loaded_engine_advertises_checked_operator_surface(self):
        self.assertFalse(hasattr(self.engine,'request'))
        self.assertEqual(evaluate(self.engine,{'n':[[2],[3]]},
            'out(Y) <= n(X) & where("even?", X) & bind(Y, X + 1)',
            {'answer':'out(Y)'},schema='infer')[0],{'answer':[(3,)]})

    def test_inferred_integer_order_is_native_numeric_not_symbol_order(self):
        result, _ = evaluate(self.engine, {"a": [[2], [10], [-1]]},
            "pair(X,Y) <= a(X) & a(Y) & (X < Y)",
            {"answer": "pair(X,Y)"}, schema="infer")
        self.assertEqual(result["answer"], [(-1, 2), (-1, 10), (2, 10)])

    def test_inferred_operator_chain_and_aggregate(self):
        result, _ = evaluate(self.engine, {"a": [[2], [10]]},
            'next(Y) <= a(X) & bind(Y, X + 1)\n'
            'total(T) <= reduce(T, "sum", next(Y), Y)',
            {"answer": "total(T)"}, schema="infer")
        self.assertEqual(result["answer"], [(14,)])

    def test_long_symbols_and_literals_preserve_complete_values(self):
        value = "full-evidence-" * 100
        facts = {"a": [[value], ["short"], [""]]}
        rules = 'out(X) <= a(X)\npicked(X) <= a(X) & a(' + repr(value) + ')'
        for schema in (None, "infer"):
            result, _ = evaluate(self.engine, facts, rules,
                                 {"answer": "out(X)", "literal": "picked(X)"}, schema=schema)
            self.assertEqual(result["answer"], [("",), (value,), ("short",)])
            self.assertEqual(result["answer"], result["literal"])

    def test_recursive_closure_and_component_reuse(self):
        result, receipt = evaluate(self.engine, {"edge": [["a", "b"], ["b", "c"]]},
            "path(X,Y) <= edge(X,Y)\npath(X,Y) <= edge(X,Z) & path(Z,Y)", {"answer": "path(X,Y)"})
        self.assertEqual(result["answer"], [("a", "b"), ("a", "c"), ("b", "c")])
        self.assertEqual(receipt["freshComponents"], receipt["repeatReusedComponents"])

    def test_mixed_scalar_identity_survives_native_roundtrip(self):
        result, _ = evaluate(self.engine, {"input": [[1], ["1"]]},
                             "out(X) <= input(X)", {"answer": "out(X)"})
        self.assertEqual(result["answer"], [(1,), ("1",)])

    def test_exact_repeat_keeps_native_session_without_reimporting_outputs(self):
        facts = {"input": [[str(n)] for n in range(2100)]}
        program, _ = read_datalog(facts, "out(X) <= input(X)", {"answer": "out(X)"})
        with EvidenceChain(self.engine, [r for r in program["relations"] if r["source"]]) as chain:
            first=chain.query(program)
            second=chain.query(program)
            self.assertEqual(first["result"], second["result"])
            self.assertEqual(len(second["result"]["relations"]["out"]), 2100)
            self.assertTrue(second["retainedCompleted"])
            self.assertEqual(second["freshComponents"], [])
            self.assertEqual(first["pathIdentity"], second["pathIdentity"])
            self.assertTrue(first['evaluated'])
            self.assertFalse(second['evaluated'])
            self.assertEqual(first['evaluationCount'],1)
            self.assertEqual(second['evaluationCount'],1)

    def test_total_input_fact_limit_is_not_relaxed_by_repeat_fix(self):
        from ascent import FactLimits
        program, _ = read_datalog({"a": [[str(n)] for n in range(2050)],
                                      "b": [[str(n)] for n in range(2050)]},
                                     "out(X) <= a(X) & b(X)", {"answer": "out(X)"})
        with self.assertRaises(ResourceLimitError):
            with EvidenceChain(self.engine, [r for r in program["relations"] if r["source"]],
                               limits=FactLimits(input=4096)):
                pass

    def test_native_admission_rejects_negative_cycle(self):
        with self.assertRaises(ValueError):
            evaluate(self.engine, {"domain": [["a"]]},
                "left(X) <= domain(X) & ~right(X)\nright(X) <= domain(X) & ~left(X)",
                {"answer": "left(X)"})

    def test_replacement_invalidates_negative_results(self):
        rules = "out(X) <= domain(X) & ~denied(X)"
        first, _ = read_datalog({"domain": [["a"]], "denied": []}, rules, {"answer": "out(X)"})
        second, _ = read_datalog({"domain": [["a"]], "denied": [["a"]]}, rules, {"answer": "out(X)"})
        with EvidenceChain(self.engine, [r for r in first["relations"] if r["source"]]) as chain:
            old = chain.query(first)
            self.assertEqual(old["result"]["relations"]["out"], [['a']])
            chain.replace([r for r in second["relations"] if r["source"]])
            new = chain.query(second)
            self.assertEqual(new["result"]["relations"]["out"], [])
            self.assertEqual(new["reusedComponents"], [])

    def test_checked_arithmetic_filters_and_identity(self):
        result, _ = evaluate(self.engine, {"n": [[1], [2], [8], [12]]},
            'picked(Y) <= n(X) & where("even?", X) & (X < 10) & bind(Y, X + 1)\n'
            'copied(Y) <= n(X) & bind(Y, X)',
            {"selected": "picked(Y)", "copied": "copied(Y)"},
            schema={"n": ["integer"], "picked": ["integer"], "copied": ["integer"]})
        self.assertEqual(result["selected"], [(3,), (9,)])
        self.assertEqual(result["copied"], [(1,), (2,), (8,), (12,)])

    def test_all_checked_reducers_grouped_and_empty(self):
        for operator, expected in (("count", [("a", 2), ("b", 1), ("empty", 0)]),
                                   ("sum", [("a", 7), ("b", 9), ("empty", 0)]),
                                   ("min", [("a", 2), ("b", 9)]),
                                   ("max", [("a", 5), ("b", 9)])):
            with self.subTest(operator=operator):
                inputs = "" if operator == "count" else ", V"
                result, _ = evaluate(self.engine,
                    {"group": [["a"], ["b"], ["empty"]], "n": [["a", 2], ["a", 5], ["b", 9]]},
                    f'out(G,T) <= group(G) & reduce(T, "{operator}", n(G,V){inputs})',
                    {"answer": "out(G,T)"},
                    schema={"group": ["symbol"], "n": ["symbol", "integer"], "out": ["symbol", "integer"]})
                self.assertEqual(result["answer"], expected)

    def test_aggregate_dependency_and_operator_change_do_not_reuse_wrong_claim(self):
        facts = {"n": [[2], [5]]}
        schema = {"n": ["integer"], "sum": ["integer"], "out": ["integer"]}
        first, _ = read_datalog(facts,
            'sum(T) <= reduce(T, "sum", n(X), X)\nout(Y) <= sum(T) & bind(Y, T + 1)',
            {"answer": "out(Y)"}, schema=schema)
        second, _ = read_datalog(facts,
            'sum(T) <= reduce(T, "sum", n(X), X)\nout(Y) <= sum(T) & bind(Y, T + 2)',
            {"answer": "out(Y)"}, schema=schema)
        with EvidenceChain(self.engine, [r for r in first["relations"] if r["source"]]) as chain:
            self.assertEqual(chain.query(first)["result"]["relations"]["out"], [[8]])
            changed = chain.query(second)
            self.assertEqual(changed["result"]["relations"]["out"], [[9]])
            self.assertEqual([r["relations"] for r in changed["reusedComponents"]], [["sum"]])
            repeated = chain.query(second)
            self.assertEqual(repeated["result"], changed["result"])
            self.assertEqual(repeated["pathIdentity"], changed["pathIdentity"])
            self.assertTrue(repeated["retainedCompleted"])
            self.assertEqual(repeated["freshComponents"], [])

    def test_operator_errors_remain_native_rejections(self):
        for body in ('n(X) & where("system", X)', 'n(X) & where("<", X)',
                     'n(X) & reduce(Y, "count", n(Z), Z)',
                     'n(X) & reduce(Y, "sum", n(Z))'):
            with self.subTest(body=body), self.assertRaises(ValueError):
                evaluate(self.engine, {"n": [[1]]}, "out(X) <= " + body,
                         {"answer": "out(X)"}, schema={"n": ["integer"], "out": ["integer"]})
        with self.assertRaises(ValueError):
            evaluate(self.engine, {"n": [["text"]]}, 'out(Y) <= n(X) & bind(Y, X + 1)',
                     {"answer": "out(Y)"}, schema={"n": ["symbol"], "out": ["integer"]})

    def test_native_rejects_aggregate_recursion(self):
        with self.assertRaises(ValueError):
            evaluate(self.engine, {"n": [[1]]},
                'out(T) <= n(X) & reduce(T, "sum", out(Y), Y)',
                {"answer": "out(T)"}, schema={"n": ["integer"], "out": ["integer"]})


if __name__ == "__main__":
    unittest.main()
