# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Formal receipt admission and preserved exploration obligations."""
import unittest

from ascent_workbench.formal import MODEL_ORDER, Obligation, configuration, obligations, validate_output


class FormalTests(unittest.TestCase):
    def test_zero_exit_without_exhaustive_conclusion_is_rejected(self):
        correct = Obligation("correct", configuration("EvidenceInteraction", {}))
        for code, output in ((0, "Progress(1): states left on queue"),
                             (1, "Model checking completed. No error has been found.")):
            with self.assertRaises(RuntimeError):
                validate_output(correct, code, output)

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
        original = {name: items for name, items in plans.items()
                    if name not in {"CachePublication", "ClueSubmission", "TrajectoryClueScope", "AnchoredEvidenceSlice", "ProgressiveEvidenceRead"}}
        self.assertEqual(len(original), 56)
        self.assertEqual(sum(map(len, original.values())), 377)
        self.assertEqual(set(plans) - set(original),
                         {"CachePublication", "ClueSubmission", "TrajectoryClueScope", "AnchoredEvidenceSlice", "ProgressiveEvidenceRead"})
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
            "invalid-declaration-hit": "SoundHit",
            "ack-collapsed": "Acknowledged",
            "drop-first-hit": "FirstHit", "invent-hit": "SoundHit", "dump-graph": "Local",
            "hide-counter": "Family", "wrong-chain": "Traceable",
            "hide-truncation": "HonestPresentation", "gap-as-absent": "Gaps",
            "mask-gap": "Gaps", "count-only-delta": "ExactDelta",
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
