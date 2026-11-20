# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Formal receipt admission and preserved exploration obligations."""
import unittest
from pathlib import Path
import tempfile
import threading
import time
from unittest.mock import patch

import ascent_workbench.formal as formal

from ascent_workbench.formal import MODEL_ORDER, Obligation, configuration, obligations, validate_output


class FormalTests(unittest.TestCase):
    def test_preparation_work_preserves_all_observation_and_source_controls(self):
        controls = {item.name: item for item in obligations(configuration("PreparationWork", {}))}
        self.assertEqual(controls["correct"].expected, 0)
        faults = {name: item.property for name, item in controls.items() if name != "correct"}
        self.assertEqual(faults, {
            "darwin-source-roots": "BoundedSourceEntries",
            "compact-isolated-source": "SourceGcIsolation",
            "ignore-ordinary-gc": "SourceGcIsolation",
            "drop-isolated-source": "SourceQueueCoverage",
            "last-interface-alias-wins": "IndexedDispatchExact",
            "reuse-unadmitted-interface": "InterfaceSelectionExact",
            "reuse-reloaded-interface": "InterfaceSelectionExact",
            "reuse-compiling-interface": "InterfaceSelectionExact",
            "reuse-consumer-interface": "InterfaceSelectionExact",
            "reuse-missing-interface": "InterfaceSelectionExact",
            "expand-admitted-interface": "InterfaceSelectionExact",
            "drop-qualified-interface": "InterfaceSelectionExact",
            "drop-syntax-interface": "InterfaceSelectionExact",
            "reuse-unknown-interface": "InterfaceSelectionExact",
            "raise-heap-for-gc": "HeapLimitUnchanged",
            "skip-heap-cap": "HeapSelectionBounded",
            "occupancy-as-cumulative": "CumulativeCapabilityRequired",
            "key-by-commit": "ContentKeyExact",
            "key-by-generated-manifest": "ContentKeyExact",
            "reuse-missing-payload": "CompleteCacheBundle",
            "reuse-missing-receipt": "CompleteCacheBundle",
            "hide-compiler-failure": "CompilerWorkComplete",
            "hide-changed-input": "CompilerWorkComplete",
            "hide-job": "JobsExact", "forget-import": "ImportsExact",
            "sum-nested": "AllocationNotNested", "publish-partial": "Complete",
            "sum-helper-cpu": "CompilerCpuPartition",
            "restore-outputs-only": "RestoredSourceClock",
            "restore-stale-source": "RestoredSourceCurrent",
            "ignore-generation": "Current", "clamp-counter": "OrderedCounter",
            "ignore-negative-raw": "OrderedCounter",
            "bootstrap-inventory": "InventoryDataOnly",
            "eager-catalog": "OnlyDemandedCompilation",
            "compile-source-suite": "SourceCarriersRemainSource",
            "compile-source-consumer": "SourceCarriersRemainSource",
            "reuse-stale-input": "ReuseCurrentInputs",
            "expand-producer-catalog": "OnlyConsumerRoots",
            "prune-unadmitted-catalog": "UnadmittedCatalogPresent",
            "batch-source-roots": "BoundedSourceEntries",
            "retain-source-roots": "ExitedVmReleasesEntries",
            "drop-demanded-support": "DemandedSupportRetained",
            "drop-cached-support": "CachedSupportRetained",
        })
        self.assertTrue(all(controls[name].expected == 12 for name in faults))

    def test_positive_dsl_preserves_capture_scope_and_root_controls(self):
        controls = {item.name: item for item in obligations(configuration("PositiveDslAdmission", {}))}
        self.assertEqual(controls["correct"].expected, 0)
        self.assertEqual({name: item.property for name, item in controls.items() if name != "correct"}, {
            "early": "CallbacksOutside", "leak": "ScopeRestored", "skip-root": "PublicationChecked",
        })
        self.assertTrue(all(item.expected == 12 for name, item in controls.items() if name != "correct"))

    def test_archive_work_retains_source_lease_cache_and_cost_controls(self):
        controls = {item.name: item for item in obligations(configuration("ArchiveWork", {}))}
        self.assertEqual(controls["correct"].expected, 0)
        self.assertEqual({name: item.property for name, item in controls.items() if name != "correct"}, {
            "omit-lease": "LeaseExclusive", "split-by-profile": "ProfilesShareWork",
            "count-hit-as-work": "NativeCostExact", "ignore-source": "SourceCurrent",
            "hide-pending": "ReceiptComplete", "hide-failure": "ReceiptComplete",
            "hide-unknown": "ReceiptComplete", "link-shared": "PrivateOutputStable",
        })
        self.assertTrue(all(item.expected == 12 for name, item in controls.items() if name != "correct"))

    def test_zero_exit_without_exhaustive_conclusion_is_rejected(self):
        correct = Obligation("correct", configuration("EvidenceCacheAdmission", {}))
        for code, output in ((0, "Progress(1): states left on queue"),
                             (1, "Model checking completed. No error has been found.")):
            with self.assertRaises(RuntimeError):
                validate_output(correct, code, output)


    def test_verification_schedule_preserves_every_exact_obligation_and_duplicate(self):
        from collections import Counter
        from ascent_workbench.formal import verification_schedule
        from ascent_workbench.formal_models import MODEL_ORDER
        configs = [configuration(name, {}) for name in MODEL_ORDER]
        ordered = verification_schedule(configs)
        self.assertEqual(Counter(ordered), Counter(configs))
        self.assertLess([base.model for base in ordered].index('PreparationWork'), 4)
        def signature(configurations):
            return Counter((base.model, item.name, item.configuration.text(), item.expected, item.property)
                           for base in configurations for item in obligations(base))
        self.assertEqual(signature(ordered), signature(configs))
        repeated = [configs[0], configs[-1], configs[0]]
        self.assertEqual(Counter(verification_schedule(repeated)), Counter(repeated))

    def test_one_model_checks_concurrently_without_dropping_or_rewriting_controls(self):
        from collections import Counter
        base = configuration("ActorRoundCredits", {})
        checks = {f"{base.model}-{item.name}": item for item in obligations(base)}
        barrier = threading.Barrier(2)
        lock = threading.Lock()
        seen = []
        active = set()
        peak = [0]
        with tempfile.TemporaryDirectory() as temporary:
            runner = formal.Runner.__new__(formal.Runner)
            runner.environment = {}
            runner.output = Path(temporary)
            runner.jar = Path("unchanged-checker.jar")
            runner.deadline = time.monotonic() + 10
            compiled = []
            runner.compile = lambda configurations: compiled.extend(configurations)
            def run(argv, label):
                with lock:
                    seen.append(label)
                    position = len(seen)
                    active.add(label)
                    peak[0] = max(peak[0], len(active))
                try:
                    self.assertIn("-Xmx1G", argv)
                    self.assertEqual(argv[argv.index("-workers") + 1], "1")
                    if position <= 2:
                        barrier.wait(timeout=3)
                    item = checks[label]
                    return item.expected, ("Model checking completed. No error has been found."
                                           if item.expected == 0 else
                                           f"Invariant {item.property} is violated")
                finally:
                    with lock:
                        active.remove(label)
            runner.run = run
            with patch.object(formal, "capacity", return_value=2):
                result = runner.quint_checks((base.model,))
            self.assertEqual(peak[0], 2)
            self.assertFalse(active)
            self.assertEqual(Counter(seen), Counter(checks.keys()))
            self.assertEqual(compiled, [base])
            self.assertEqual(result, {base.model: len(checks)})
            for label, item in checks.items():
                self.assertEqual((runner.output / f"{label}.cfg").read_text(),
                                 item.configuration.text())

    def test_parallel_checks_keep_counterexample_rejection_and_deadline(self):
        base = configuration("ActorRoundCredits", {})
        with tempfile.TemporaryDirectory() as temporary:
            runner = formal.Runner.__new__(formal.Runner)
            runner.environment = {}
            runner.output = Path(temporary)
            runner.jar = Path("unchanged-checker.jar")
            runner.deadline = time.monotonic() + 10
            runner.compile = lambda configurations: None
            calls = []
            def run(argv, label):
                calls.append(label)
                return 0, "Model checking completed. No error has been found."
            runner.run = run
            with patch.object(formal, "capacity", return_value=2), self.assertRaises(RuntimeError):
                runner.quint_checks((base.model,))
            self.assertTrue(calls)
            calls.clear()
            runner.deadline = time.monotonic() - 1
            with self.assertRaises(TimeoutError):
                runner.check(base, obligations(base)[0])
            self.assertFalse(calls, "an expired budget must not start another checker")

    def test_compiler_cost_controls_cover_real_scope_and_invalidation(self):
        checks = {item.name: item for item in obligations(configuration("CompilerCost", {}))}
        self.assertEqual(checks.pop("correct").expected, 0)
        self.assertEqual(set(checks), {"drop-rule-fallback", "ignore-constructor-override", "reuse-term-validation-result", "ignore-validation-protocol", "accept-custom-provider-fast-path", "accept-missing-metadata-cache", "accept-unissued-shape", "ignore-shape-revision", "policy-as-production-build", "source-before-prepared-library", "sum-pass-walls", "skip-changed-cache-write", "projection-index-first-only", "missing-options-as-default", "skip-complete-admission", "retain-duplicate-admission", "retain-tiny-range-scan", "decode-net-as-heap-events", "accept-foreign-module-catalog", "ignore-source-cost-gap", "choose-copy-by-time", "ignore-writer-overlap", "accept-tied-writers", "reuse-unadmitted-projection", "reuse-other-suite-roots", "drop-projection-dependency", "drop-latency-controls", "attribute-non-c-output", "infer-flat-linker-output", "multiply-link-cost-by-edges", "execute-cached-source", "skip-head-admission", "promote-net-stack-counter", "ignore-producer-order", "match-producer-name", "ambiguous-producer", "reuse-changed-reference", "reuse-damaged-interface", "cross-parent-cost", "ambiguous-parent-cost", "count-link-metadata", "ignore-compiler-origin", "accept-multiple-targets", "host-boundary", "ignore-compiler-failure", "ignore-compiler-input",
                                    "publish-partial-ggc", "keep-unrequested-old-output", "clean-production",
                                    "promote-vm-counter", "sum-nested-passes", "record-failed-build", "reuse-old-options"})
        self.assertTrue(all(item.expected == 12 for item in checks.values()))

    def test_batched_lean_renderings_cannot_drop_duplicate_or_add_sources(self):
        from ascent_workbench.formal import renderings_from_batch
        self.assertEqual(renderings_from_batch('[["a","source-a"],["b","source-b"]]', ['a','b']),
                         {'a': 'source-a', 'b': 'source-b'})
        for bad in ['[]', '[["a","x"]]', '[["a","x"],["a","y"]]',
                    '[["a","x"],["b","y"],["c","extra"]]', '{}', '[["a",null]]', 'truncated']:
            with self.subTest(output=bad), self.assertRaises(RuntimeError):
                renderings_from_batch(bad, ['a','b'])

    def test_counterexample_must_match_property_and_exit(self):
        fault = next(o for o in obligations(configuration("EvidenceCacheAdmission", {})) if o.name == "source")
        validate_output(fault, 12, "Invariant ExactSource is violated")
        for code, output in ((0, "Invariant ExactSource is violated"), (12, "Invariant Other is violated"),
                             (13, "Temporal property ExactSource was violated")):
            with self.assertRaises(RuntimeError):
                validate_output(fault, code, output)



    def test_bounds_and_fixture_property_namespace_are_preserved(self):
        with self.assertRaises(ValueError):
            configuration("ActorSession", {"ASCENT_FORMAL_SESSION_GENERATION_CUTOFF": "2"})
        with self.assertRaises(ValueError):
            configuration("ActorRound", {"ASCENT_FORMAL_GENERATION_CUTOFF": "١"})
        fault = next(o for o in obligations(configuration("ProviderAdmission", {})) if o.name == "nocap")
        self.assertEqual(fault.property, "ProviderAdmissionFixture_ProviderAdmission_MatchingExact")
        self.assertIn("INVARIANTS " + fault.property, fault.configuration.text())


if __name__ == "__main__":
    unittest.main()
