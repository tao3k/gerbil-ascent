# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Native Session contract through Python transport; no Python inference oracle."""
from pathlib import Path
from importlib.resources import files
import json
import subprocess
import sys
import unittest

from ascent import Engine
from ascent.trajectory import ClueExchange


PROJECTION = """
(define-evidence (project)
 (sources clue factor link) (outputs clue factor link)
 (relation clue (id digest claim polarity role source))
 (relation factor (id digest name value))
 (relation link (claim target label id digest)))
(define-evidence (select)
 (sources clue factor binding) (outputs question)
 (relation clue (id digest claim polarity role source))
 (relation factor (id digest name value))
 (relation binding (name value))
 (relation question (claim))
 ((question C) <-- (clue I D C _ _ _) (factor I D N V) (binding N V)))
"""


def exchange(extra=None):
    engine = Engine()
    facts = {"clue": [["known", "sha", "gc-claim", "support", "observation", "receipt"]],
             "factor": [["known", "sha", "topic", "gc"]], "link": []}
    if extra is not None:
        facts["clue"].append(["additional", "sha", "elsewhere" if extra == "unrelated" else "gc-claim",
                              "counter", "observation", "receipt"])
    return engine, ClueExchange(engine, [PROJECTION], "project", facts, {"receipt": "sha"})


def resume_fixture():
    request = json.load(sys.stdin)
    engine, owner = exchange(request.pop("extra", None))
    try:
        print(json.dumps(owner.slice(request)))
    finally:
        owner.close()


class CheckpointTransport(unittest.TestCase):
    def setUp(self):
        source = files("ascent").joinpath("checkpoint_rules.ss")
        self.engine = Engine()
        self.session = self.engine.evidence(source.read_text(), "make-evidence-checkpoint", trusted=True)
        self.addCleanup(self.session.close)

    def evaluate(self, facts):
        self.session.replace(facts)
        result = self.session.run()
        self.assertTrue(result["complete"])
        handle = self.session.result(result)
        self.addCleanup(handle.close)
        return result["relations"]

    def facts(self):
        return {"requirement": [("test",)], "contract": [("test", "checker")],
                "receipt": [("r", "test", "checker", "PASS")], "completed_outcome": [("PASS",)],
                "verified": [("r",)], "quiescent": [("r",)],
                "support_declaration": [("test", "checker", "scope", "manifest", "enumerator", 1, 1, 0)],
                "support_witness": [("r", "scope", "manifest", "enumerator")],
                "required_command": [("test", "checker", "child", 7)],
                "required_binding": [("test", "checker", "runtime")], "binding": [("r", "runtime", "sha")],
                "current_binding": [("runtime", "sha")], "command": [("r", "child", 7)],
                "command_observation": [("r", "child", 7, False, True, True)]}

    def test_python_boolean_transport_is_not_integer_truthiness(self):
        for timeout, accepted in [(False, True), (0, False), (True, False)]:
            with self.subTest(timeout=timeout, cell_type=type(timeout).__name__):
                facts = self.facts()
                facts["command_observation"] = [("r", "child", 7, timeout, True, True)]
                result = self.evaluate(facts)
                self.assertEqual(bool(result["historical_complete"]), accepted)

    def test_missing_bound_input_is_not_an_empty_success(self):
        facts = self.facts()
        facts["binding"] = []
        result = self.evaluate(facts)
        self.assertTrue(result["historical_complete"])
        self.assertEqual(result["applicable"], [])
        self.assertEqual(result["binding_gap"], [["r", "runtime"]])

    def test_missing_exit_witness_cannot_promote_declared_pass(self):
        facts = self.facts()
        facts["command_observation"] = []
        self.assertEqual(self.evaluate(facts)["historical_complete"], [])

    def test_omission_is_not_a_legitimate_empty_declaration(self):
        facts = self.facts()
        facts.update(required_binding=[], binding=[], current_binding=[], command=[])
        self.assertEqual(self.evaluate(facts)["reusable"], [])
        facts["support_declaration"] = [("test", "checker", "scope", "empty-manifest", "enumerator", 0, 0, 0)]
        facts["support_witness"] = [("r", "scope", "empty-manifest", "enumerator")]
        facts["required_command"] = []
        self.assertEqual(self.evaluate(facts)["reusable"], [["test", "r"]])


class ReadCheckpointProcesses(unittest.TestCase):
    def resumed(self, checkpoint, extra=None, **fields):
        directory = str(Path(__file__).resolve().parent)
        code = "import sys; sys.path.insert(0, sys.argv[1]); from test_checkpoint_contract import resume_fixture; resume_fixture()"
        result = subprocess.run([sys.executable, "-c", code, directory],
            input=json.dumps(dict(checkpoint=checkpoint, extra=extra, **fields)),
            text=True, capture_output=True, check=True, timeout=30)
        return json.loads(result.stdout)

    def initial(self):
        engine, owner = exchange()
        try:
            return owner.slice_selected([PROJECTION], "select", {"bindings": [["topic", "gc"]]})
        finally:
            owner.close()

    def test_fresh_process_rederives_snapshot_without_replaying_unrelated_updates(self):
        first = self.initial()
        self.assertEqual(len(first["brief"]["families"]), 1)
        refreshed = self.resumed(first["checkpoint"], extra="unrelated")
        self.assertEqual(refreshed["brief"]["mode"], "refresh")
        self.assertEqual(refreshed["brief"]["families"], [])
        self.assertGreater(refreshed["brief"]["delta"]["retained"], 0)
        self.assertFalse(refreshed["brief"]["executionAuthorized"])

    def test_new_counterevidence_is_displayed_then_acknowledged_across_processes(self):
        first = self.initial()
        changed = self.resumed(first["checkpoint"], extra="counter")
        family = changed["brief"]["families"][0]
        self.assertTrue(family["conflict"])
        self.assertEqual({row["polarity"] for row in family["observations"]}, {"support", "counter"})
        repeated = self.resumed(changed["checkpoint"], extra="counter")
        self.assertEqual(repeated["brief"]["families"], [])
        self.assertEqual(repeated["brief"]["mode"], "incremental")
        opened = self.resumed(repeated["checkpoint"], extra="counter", questions=["caller-new-hypothesis"])
        self.assertTrue(opened["brief"]["explorationOpen"])
        self.assertEqual(opened["brief"]["families"][0]["claim"], "caller-new-hypothesis")
        self.assertTrue(opened["brief"]["families"][0]["unknown"])


class SelectedComponentTransport(unittest.TestCase):
    def test_unselected_source_is_not_required_but_selected_source_remains_mandatory(self):
        manifest = {"schema": "ascent.evidence-components.v1", "components": [
            {"id": "chosen", "source": "chosen.ss", "exports": ["make"], "dependencies": []},
            {"id": "elsewhere", "source": "not-retained.ss", "exports": [], "dependencies": []}]}
        source = "(define-evidence (make) (sources) (outputs fact) (relation fact (value) '((1))))"
        engine = Engine()
        with engine.components(manifest, {"chosen.ss": source}, "chosen", trusted=True) as module:
            self.assertEqual(module.components, ["chosen"])
            with module.call("make") as declaration:
                session = declaration.open_session()
                try:
                    result = session.run()
                    self.assertTrue(result["complete"])
                    self.assertEqual(result["relations"]["fact"], [[1]])
                    session.result(result).close()
                finally:
                    session.close()
        with self.assertRaises(ValueError):
            engine.components(manifest, {}, "chosen", trusted=True)


if __name__ == "__main__":
    unittest.main()
