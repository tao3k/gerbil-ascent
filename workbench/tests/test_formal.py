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
        self.assertEqual(len(plans), 52)
        self.assertEqual(sum(map(len, plans.values())), 336)  # Prior 331 plus five Rayon publication obligations.
        lifetime = {o.name: o for o in plans["ReaderLifetime"]}
        self.assertEqual(lifetime["sealed-round-unfair"].expected, 13)
        self.assertEqual(lifetime["single-reader-global-fairness"].expected, 0)
        self.assertIn("ExplorationBound = 4", plans["ProviderViews"][0].configuration.constants)
        self.assertIn("GenerationCutoff = 4", plans["NativeSessionPublication"][0].configuration.constants)

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
