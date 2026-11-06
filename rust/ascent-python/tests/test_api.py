"""Installed-wheel qualification; never loads CFFI or a Scheme VM."""
import threading
import unittest
import ascent


def program():
    result = ascent.Program()
    result.relation("edge", ["integer", "integer"], source=True)
    result.relation("reach", ["integer", "integer"])
    x, y, z = [ascent.Term.var(i) for i in range(3)]
    result.rule(ascent.Atom("reach", [x, y]), [ascent.Atom("edge", [x, y])])
    result.rule(ascent.Atom("reach", [x, z]), [ascent.Atom("reach", [x, y]), ascent.Atom("edge", [y, z])])
    return result


class LibraryTests(unittest.TestCase):
    def test_actual_wheel_recursion_replacement_and_snapshot(self):
        engine = ascent.Engine(workers=4)
        session = engine.open(program())
        session.replace("edge", [[1, 2], [2, 3], [1, 2]])
        first = session.run()
        self.assertEqual(first.rows("reach"), [[1, 2], [1, 3], [2, 3]])
        session.replace("edge", [[4, 5]])
        self.assertEqual(session.run().rows("reach"), [[4, 5]])
        self.assertEqual(len(first.rows("reach")), 3)
        with self.assertRaises(ValueError):
            session.replace("reach", [[8, 9]])
        with self.assertRaises(ValueError):
            session.replace("edge", [[False, 0]])
        session.replace("edge", [[2**100, -(2**130)]])
        self.assertEqual(session.run().rows("reach"), [[2**100, -(2**130)]])

    def test_owned_symbol_values_keep_equality_across_python_roundtrips(self):
        declared = ascent.Program.read_rule_sources(["(ascent (relation input ((v symbol?))) (relation output ((v symbol?))) ((output X) <-- (input X)))"])
        session = ascent.Engine(4).open(declared)
        session.replace("input", [[ascent.Symbol("a")], [ascent.Symbol("a")]])
        observed = session.run().rows("output")
        self.assertEqual(observed, [[ascent.Symbol("a")]])
        self.assertEqual(len({observed[0][0], ascent.Symbol("a")}), 1)

    def test_exhaustion_preserves_last_completed_and_can_cancel(self):
        session = ascent.Engine(2).open(program())
        session.replace("edge", [[1, 2]])
        before = session.run()
        session.replace("edge", [[3, 4]])
        with self.assertRaises(RuntimeError):
            session.run(max_states=0)
        self.assertEqual(session.last_completed().rows("reach"), before.rows("reach"))
        cancellation = ascent.Cancellation()
        cancellation.cancel()
        with self.assertRaises(RuntimeError):
            session.run(cancellation=cancellation)

    def test_python_threads_use_owned_values(self):
        engine = ascent.Engine(4)
        output, errors = [], []

        def work(index):
            try:
                session = engine.open(program())
                session.replace("edge", [[index, index + 1]])
                output.append(session.run().rows("reach"))
            except Exception as error:
                errors.append(error)

        threads = [threading.Thread(target=work, args=(i,)) for i in range(12)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=10)
            self.assertFalse(thread.is_alive())
        self.assertFalse(errors)
        self.assertEqual(len(output), 12)



class RustDriverTests(unittest.TestCase):
    def test_rust_owns_case_execution_comparison_and_failures(self):
        import ascent
        program = ascent.Program.read_rule_sources([
            "(ascent (relation input ((v integer?))) (relation output ((v integer?))) ((output x) <-- (input x)))"
        ])
        case = ascent.VerificationCase(program, {"input": [[2], [1], [2]]},
                                      {"input": [[1], [2]], "output": [[1], [2]]})
        samples = case.run([1, 4, 8, 12], samples=2, limits=ascent.Limits(max_facts=4, max_states=4))
        self.assertEqual(len(samples), 8)
        self.assertEqual({s.workers for s in samples}, {1, 4, 8, 12})
        self.assertTrue(all(s.facts == 4 and s.elapsed_ns > 0 for s in samples))
        wrong = ascent.VerificationCase(program, {"input": [[1]]}, {"input": [[1]], "output": []})
        with self.assertRaises(AssertionError):
            wrong.run([1], samples=1)
        with self.assertRaises(RuntimeError):
            case.run([4], samples=1, limits=ascent.Limits(max_facts=3))


class DownstreamLoadingTests(unittest.TestCase):
    def test_installed_dsl_loader_does_not_require_a_compiler(self):
        import os
        import subprocess
        import sys
        import tempfile
        code = '''
import ascent
p = ascent.Program.read_rule_sources(["(ascent (relation input ((v integer?))) (relation output ((v integer?))) ((output x) <-- (input x)))"])
c = ascent.VerificationCase(p, {"input": [[1]]}, {"input": [[1]], "output": [[1]]})
c.run([1, 4], samples=1)
engine = ascent.Engine(4)
text = "(ascent (relation input ((v integer?))) (relation next ((v integer?))) (relation total ((v integer?))) ((next Y) <-- (input X) (let Y (X) (+ X 1))) ((total T) <-- (aggregate T gerbil-ascent-sum (Y) (next Y))))"
with engine.open_sources(text) as session:
    session.run()
    session.replace({"input": [[2**100], [2]]})
    assert session.run(queries=["total"])["relations"]["total"] == [[2**100 + 4]]
'''
        with tempfile.TemporaryDirectory() as directory:
            subprocess.run([sys.executable, "-c", code], cwd=directory,
                           env=dict(os.environ, PATH=directory, PYTHONPATH="", GERBIL_PATH=directory, GERBIL_HOME=directory, CARGO_HOME=directory, RUSTUP_HOME=directory),
                           check=True, capture_output=True, timeout=10)

class SourceApiTests(unittest.TestCase):
    def test_native_source_api_guard_limits_generations_and_owned_results(self):
        source = """(ascent (relation input ((v integer?))) (relation output ((v integer?)))
          ((output X) <-- (input X) (if (X) (and (>= X 0) (even? X)))))"""
        with ascent.Engine(4) as engine, engine.open_sources(source, limits=ascent.FactLimits(input=3)) as session:
            session.run()
            session.replace({"input": [[-1], [2**100], [3]]})
            before = session.run(queries=["output"])
            self.assertEqual(before["relations"]["output"], [[2**100]])
            result = session.result(before)
            self.assertEqual(result.rows("output")["value"]["format"], "native-value-graph.v1")
            with self.assertRaises(ascent.EngineError):
                session.replace({"input": [[7], [7], [7], [7]]})
            self.assertEqual(session.run(queries=["output"])["sourceGeneration"], before["sourceGeneration"])
            self.assertTrue(result.rows("output"))
            session.replace({"input": [[8]]})
            with self.assertRaises(ValueError):
                result.rows("output")
        with self.assertRaises(ValueError):
            session.run()

    def test_inert_catalog_roundtrip_uses_rust_without_compilation(self):
        source = """(ascent-fragment (relation input ((v symbol?))) (relation output ((v symbol?)))
          ((output X) <-- (input X)))"""
        with ascent.Engine() as engine:
            catalog = engine.read_rules(source)
            catalog["relations"][0]["rows"] = [["a"]]
            catalog["queries"] = ["output"]
            with engine.open(catalog) as session:
                self.assertEqual(session.run()["relations"], {"output": [["a"]]})
            with engine.open_rule_sources(source) as session:
                self.assertEqual(session.projection["status"], "supported")
                session.run()
                session.replace({"input": [["a"], ["b"]]})
                self.assertEqual(session.run(queries=["output"])["relations"]["output"], [["a"], ["b"]])

    def test_guard_failure_and_finite_limit_validation_are_native(self):
        source = """(ascent (relation input ((v integer?))) (relation output ((v integer?)))
          ((output X) <-- (input X) (if (X) (or 0 (even? "bad")))))"""
        with ascent.Engine() as engine, engine.open_sources(source) as session:
            initial = session.run()
            with self.assertRaisesRegex(ascent.EngineError, "guard must return a boolean"):
                session.replace({"input": [[0]]})
            self.assertEqual(session.run()["relations"], initial["relations"])
        policy = ascent.FactLimits(input=3)
        self.assertEqual(policy.wire(), {"input": 3})
        self.assertEqual((policy.input, policy.derived, policy.output), (3, None, None))
        for ceiling in [0, -1, True, 1.5, "unlimited"]:
            with self.assertRaises(ascent.EngineError):
                ascent.FactLimits(input=ceiling)

class InitialDataTests(unittest.TestCase):
    def test_named_symbols_share_their_interned_value_graph_node(self):
        text = "(ascent (relation input ((tag symbol?) (v integer?))))"
        with ascent.Engine() as engine, engine.open_sources(text) as session:
            session.run()
            session.replace({"input": [["a", 1], ["a", 2]]})
            with session.result(session.run()) as result:
                nodes = result.rows("input")["value"]["nodes"]
                self.assertEqual(len([n for n in nodes if n["type"] == "symbol" and n["value"] == "a"]), 1)

    def test_native_fixed_rows_and_fact_rules_survive_catalog_projection(self):
        text = "(ascent (relation fixed ((x integer?)) '((1) (1) (2))) (relation input ((x integer?))) (relation output ((x integer?))) ((output X) <-- (fixed X)) (fact (output 7)))"
        with ascent.Engine(4) as engine, engine.open_sources(text) as session:
            self.assertEqual(session.run(queries=["output"])["relations"]["output"], [[1], [2], [7]])
            projected = session.projection
            self.assertEqual(projected["status"], "supported")
            with engine.open({**projected["program"], "queries": ["output"]}) as control:
                self.assertEqual(control.run()["relations"]["output"], [[1], [2], [7]])
            with self.assertRaises(ascent.EngineError):
                session.replace({"fixed": []})


class DomainPolicyTests(unittest.TestCase):
    def test_native_catalog_domains_and_unknown_fields_cannot_be_ignored(self):
        source = "(ascent (relation input ((x integer?))) (relation output ((x integer?))) ((output X) <-- (input X)))"
        with ascent.Engine(4) as engine:
            catalog = engine.read_rules(source)
            catalog["relations"][0]["columns"][0]["domain"] = [1, 2]
            catalog["relations"][1]["columns"][0]["domain"] = [2]
            with engine.open(catalog) as session:
                session.run()
                session.replace({"input": [[2]]})
                before = session.run()
                for value in [1, 3, True]:
                    with self.assertRaises(ascent.EngineError):
                        session.replace({"input": [[value]]})
                    self.assertEqual(session.run()["relations"], before["relations"])
            catalog["relations"][0]["columns"][0]["ignored_predicate"] = "bad"
            with self.assertRaises(ascent.EngineError):
                engine.open(catalog)


if __name__ == "__main__":
    unittest.main()
