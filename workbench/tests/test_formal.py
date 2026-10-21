# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Formal receipt admission and preserved exploration obligations."""
import unittest

from ascent_workbench.formal import MODEL_ORDER, Obligation, configuration, obligations, validate_output


class FormalTests(unittest.TestCase):
    def test_preparation_work_preserves_all_observation_and_source_controls(self):
        controls = {item.name: item for item in obligations(configuration("PreparationWork", {}))}
        self.assertEqual(controls["correct"].expected, 0)
        faults = {name: item.property for name, item in controls.items() if name != "correct"}
        self.assertEqual(faults, {
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
        correct = Obligation("correct", configuration("EvidenceInteraction", {}))
        for code, output in ((0, "Progress(1): states left on queue"),
                             (1, "Model checking completed. No error has been found.")):
            with self.assertRaises(RuntimeError):
                validate_output(correct, code, output)

    def test_integrated_checkpoint_extensions_retain_all_fault_controls(self):
        for model, faults in [('ModelApplicability', 7), ('CheckpointProjection', 8), ('ProgressWitness', 11)]:
            with self.subTest(model=model):
                checks = obligations(configuration(model, {}))
                self.assertEqual(len(checks), faults + 1)
                self.assertEqual(checks[0].expected, 0)
                self.assertTrue(all(item.expected == 12 for item in checks[1:]))

    def test_compiler_cost_controls_cover_real_scope_and_invalidation(self):
        checks = {item.name: item for item in obligations(configuration("CompilerCost", {}))}
        self.assertEqual(checks.pop("correct").expected, 0)
        self.assertEqual(set(checks), {"skip-changed-cache-write", "projection-index-first-only", "missing-options-as-default", "skip-complete-admission", "retain-duplicate-admission", "retain-tiny-range-scan", "decode-net-as-heap-events", "accept-foreign-module-catalog", "ignore-source-cost-gap", "choose-copy-by-time", "ignore-writer-overlap", "accept-tied-writers", "reuse-unadmitted-projection", "reuse-other-suite-roots", "drop-projection-dependency", "drop-latency-controls", "attribute-non-c-output", "infer-flat-linker-output", "multiply-link-cost-by-edges", "execute-cached-source", "skip-head-admission", "promote-net-stack-counter", "ignore-producer-order", "match-producer-name", "ambiguous-producer", "reuse-changed-reference", "reuse-damaged-interface", "cross-parent-cost", "ambiguous-parent-cost", "count-link-metadata", "ignore-compiler-origin", "accept-multiple-targets", "host-boundary", "ignore-compiler-failure", "ignore-compiler-input",
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
        fault = next(o for o in obligations(configuration("EvidenceInteraction", {})) if o.name == "stale")
        validate_output(fault, 12, "Invariant Safety is violated")
        for code, output in ((0, "Invariant Safety is violated"), (12, "Invariant Other is violated"),
                             (13, "Temporal property Safety was violated")):
            with self.assertRaises(RuntimeError):
                validate_output(fault, code, output)

    def test_original_scope_and_all_controls_remain(self):
        plans = {model: obligations(configuration(model, {"ASCENT_FORMAL_GENERATION_CUTOFF": "4"}))
                 for model in MODEL_ORDER}
        snapshot_controls = {"skip-snapshot-root", "retain-snapshot-intermediate"}
        self.assertEqual({item.name for item in plans["ClosedDslLowering"]},
                         {"correct", "partial", "retry", "rejectOwner"} | snapshot_controls)
        original = {name: tuple(item for item in items
                                if not (name == "ClosedDslLowering" and item.name in snapshot_controls))
                    for name, items in plans.items()
                    if name not in {"CachePublication", "ClueSubmission", "TrajectoryClueScope", "AnchoredEvidenceSlice", "ProgressiveEvidenceRead", "PreparationAdmission", "PreparationWork", "ArchiveWork", "EvidenceCheckpoint", "ClueQueryResume", "CompilerCost", "ModelApplicability", "CheckpointProjection", "ProgressWitness", "PositiveDslAdmission"}}
        self.assertEqual(len(original), 56)
        self.assertEqual(sum(map(len, original.values())), 377)
        self.assertEqual(set(plans) - set(original),
                         {"CachePublication", "ClueSubmission", "TrajectoryClueScope", "AnchoredEvidenceSlice", "ProgressiveEvidenceRead", "PreparationAdmission", "PreparationWork", "ArchiveWork", "EvidenceCheckpoint", "ClueQueryResume", "CompilerCost", "ModelApplicability", "CheckpointProjection", "ProgressWitness", "PositiveDslAdmission"})
        self.assertEqual(sum(len(v) for k, v in original.items()
                             if k not in {"TrajectoryExploration", "TrajectoryEvidenceChain",
                                          "TrajectoryRuleEvolution"}), 349)
        self.assertEqual(set(o.name for o in plans["TrajectoryEvidenceChain"]),
                         {"correct", "guess-equal", "skip-check", "drop-history",
                          "stale-packet", "stale-result", "wrong-contract", "write",
                          "close-options", "authorize", "force-next",
                          "context-leaks-result", "same-count-prefix"})
        self.assertEqual(set(o.name for o in plans["TrajectoryRuleEvolution"]),
                         {"correct", "future-leak", "late-snapshot", "erase-counterexample",
                          "publish-unreviewed", "publish-stale",
                          "ignore-counterexample", "select-action",
                          "ignore-rule-revision", "same-count-replacement"})
        progressive = {o.name: o for o in plans["ProgressiveEvidenceRead"]}
        self.assertEqual({name: o.property for name, o in progressive.items() if name != "correct"}, {
            "replay-seen": "NoReplay", "ack-hidden": "NoHiddenAcknowledgement",
            "forget-on-rescope": "PreserveSeen", "reuse-stale": "SourceBound",
            "scope-is-removal": "ScopeIsNotRemoval", "close-exploration": "Open",
        })
        self.assertTrue(all(o.expected == 12 for name, o in progressive.items() if name != "correct"))
        anchored = {o.name: o for o in plans["AnchoredEvidenceSlice"]}
        self.assertEqual({name: o.property for name, o in anchored.items() if name != "correct"}, {
            "index-only-hit": "SoundHit",
            "mix-witnesses": "SoundHit",
            "invalid-declaration-hit": "SoundHit",
            "ack-collapsed": "Acknowledged",
            "ack-before-delivery": "DeliveryAcknowledged",
            "reuse-unverified-delivery": "VerifiedReuse",
            "drop-first-hit": "FirstHit", "invent-hit": "SoundHit", "dump-graph": "Local",
            "hide-counter": "Family", "wrong-chain": "Traceable",
            "hide-truncation": "HonestPresentation", "gap-as-absent": "Gaps",
            "mask-gap": "Gaps", "count-only-delta": "ExactDelta",
            "hide-discovery": "DiscoveryExact", "invent-discovery": "DiscoveryExact",
            "select-action": "Open", "close-scope": "Open",
        })
        self.assertTrue(all(o.expected == 12 for name, o in anchored.items() if name != "correct"))
        cache = {o.name: o for o in plans["CachePublication"]}
        clue = {o.name: o for o in plans["ClueSubmission"]}
        self.assertEqual(set(clue), {"correct", "stale-cas", "drop-history", "promote-hypothesis"})
        self.assertEqual(clue["stale-cas"].property, "CompareAndSwap")
        self.assertEqual(clue["drop-history"].property, "Durable")
        self.assertEqual(clue["promote-hypothesis"].property, "HypothesisSeparation")
        scope = {o.name: o for o in plans["TrajectoryClueScope"]}
        self.assertEqual({name: o.property for name, o in scope.items() if name != "correct"}, {
            "mix-catalog-source": "CurrentBinding",
            "promote-hypothesis": "ObservationAuthority",
            "negate-absence": "OpenWorld",
            "accept-stale": "CurrentBinding",
            "accept-missing-receipt": "CurrentBinding",
            "drop-on-expand": "ScopeConservative",
            "close-scope": "OpenExploration",
            "force-choice": "OpenExploration",
            "drop-history": "DurableHistory",
            "hide-counterevidence": "ConflictVisible",
            "misattribute-counter": "CorrectReferences",
            "inherit-old-receipt": "ObservationAuthority",
        })
        self.assertEqual(scope["correct"].expected, 0)
        self.assertTrue(all(o.expected == 12 for name, o in scope.items() if name != "correct"))
        self.assertEqual(set(cache), {"correct", "late-revoke", "early-publish",
                                      "mask-error", "mask-witness", "skip-witness"})
        self.assertEqual(cache["correct"].expected, 0)
        for name, invariant in (("late-revoke", "RevokedAliases"),
                                ("early-publish", "CompletePublication"),
                                ("mask-error", "ErrorIdentity"),
                                ("mask-witness", "ErrorIdentity"),
                                ("skip-witness", "CompletePublication")):
            self.assertEqual(cache[name].expected, 12)
            self.assertEqual(cache[name].property, invariant)
        delta = {o.name: o for o in plans["DeltaClosure"]}
        self.assertEqual(set(delta), {"correct", "drop", "early", "allold", "overlap"})
        for name, invariant in (("drop", "Complete"), ("early", "Complete"),
                                ("allold", "NoOldWork"), ("overlap", "UniqueWitness")):
            self.assertEqual(delta[name].expected, 12)
            self.assertEqual(delta[name].property, invariant)
        weighted = {o.name: o for o in plans["WeightedExport"]}
        for name, invariant in (("owner-buffer-stale", "OwnerWorkspaceReuseExact"),
                                ("route-share", "SharedAxisRouteExact"),
                                ("owner-occurrence", "OwnerConstructionExact"),
                                ("owner-representative", "OwnerConstructionExact"),
                                ("owner-plan-order", "OwnerConstructionExact"),
                                ("admit-early", "StreamAdmissionComplete"),
                                ("admit-priority", "StreamAdmissionExact"),
                                ("admit-last", "StreamFirstSlots")):
            self.assertEqual(weighted[name].expected, 12)
            self.assertEqual(weighted[name].property, invariant)
        lifetime = {o.name: o for o in plans["ReaderLifetime"]}
        self.assertEqual(lifetime["sealed-round-unfair"].expected, 13)
        self.assertEqual(lifetime["single-reader-global-fairness"].expected, 0)
        self.assertIn("ExplorationBound = 4", plans["ProviderViews"][0].configuration.constants)
        self.assertIn("GenerationCutoff = 4", plans["SessionPublication"][0].configuration.constants)

    def test_trajectory_faults_are_checked_as_state_invariants(self):
        for model in ("TrajectoryExploration", "TrajectoryEvidenceChain",
                      "TrajectoryRuleEvolution"):
            for fault in obligations(configuration(model, {}))[1:]:
                with self.subTest(model=model, fault=fault.name):
                    self.assertEqual(fault.expected, 12)
                    self.assertIn(fault.property, fault.configuration.invariants)
                    self.assertEqual(fault.configuration.properties, ())

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
