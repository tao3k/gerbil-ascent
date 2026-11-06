"""Admission of explicit phase-experiment inputs; inference stays in Rust."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "rayon_control", Path(__file__).resolve().parents[2] / "tools/ci/rayon-control.py")
CONTROL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONTROL)


class RayonControlInputs(unittest.TestCase):
    def test_only_one_complete_cargo_graph_supplies_the_pair(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rows = []
            for name in ("process_throughput", "ascent-scheme-worker"):
                executable = root / name
                executable.write_bytes(name.encode())
                rows.append({"reason": "compiler-artifact", "target": {"name": name},
                             "executable": str(executable)})
            graph = root / "build.jsonl"
            graph.write_text("\n".join(json.dumps(row) for row in rows))
            self.assertEqual(set(CONTROL.artifacts(graph)), {"process_throughput", "ascent-scheme-worker"})
            for invalid in (rows[:1], rows + rows[:1]):
                graph.write_text("\n".join(json.dumps(row) for row in invalid))
                with self.subTest(rows=len(invalid)), self.assertRaises(ValueError):
                    CONTROL.artifacts(graph)

    def test_missing_executable_is_not_recovered_from_another_build(self):
        with tempfile.TemporaryDirectory() as directory:
            graph = Path(directory) / "build.jsonl"
            graph.write_text(json.dumps({"reason": "compiler-artifact", "target": {"name": "process_throughput"},
                                         "executable": str(Path(directory) / "absent")}))
            with self.assertRaises(FileNotFoundError):
                CONTROL.artifacts(graph)

    def test_wrong_machine_never_enters_the_production_benchmark(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "results"
            arguments = ["rayon-control", "--reference-source", directory, "--reference-build", "absent",
                         "--candidate-build", "absent", "--output", str(output), "--expected-cpus", "3"]
            with patch.object(sys, "argv", arguments), patch.object(CONTROL.os, "cpu_count", return_value=2), \
                    patch.object(CONTROL.MATRIX, "run_case") as execute, self.assertRaises(SystemExit):
                CONTROL.main()
            execute.assert_not_called()
            self.assertFalse(output.exists())
