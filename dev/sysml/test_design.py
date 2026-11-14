# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Refuse incomplete/misbound OpenSysML answers independently of model truth."""
import signal
import time
import unittest

import opensysml
from opensysml.proto import sysml_pb2
from ascent_workbench.design import check_validation, deadline, fixtures


def validation_for(fixture):
    def verdict(name, kind, holds):
        return opensysml.Verdict(sysml_pb2.Verdict(
            element_id=name, kind=kind, holds=holds, instance_id=1,
            status="holds" if holds else "violated"))

    return opensysml.Validation(
        [verdict(name, "constraint", name != fixture.failure) for name in fixture.assertions],
        verdict(fixture.subject, "object", fixture.failure is None))


class DesignVerdicts(unittest.TestCase):
    def setUp(self):
        self.positive, self.negative = list(fixtures())[:2]

    def test_original_matching_fixture_inventory_and_counts(self):
        cases = list(fixtures())
        self.assertEqual(len({case.subject for case in cases}), 40)
        self.assertEqual(sum(case.failure is None for case in cases), 14)
        original = {
            "sameCut", "matchingOnly", "newSuffix", "transitionReplay", "streamingAtCapacity",
            "staleSecondSource", "staleSecondDelta", "wrongOwner", "incompletePrefix",
            "lostSupport", "skippedSuffix", "sharedMutation", "canceledPublication",
            "effectfulReuse", "changedBinding", "staleLocalCut", "cachedCallerSupport",
            "overCapacity", "droppedFallback",
        }
        self.assertEqual({case.subject.split("::")[1] for case in cases
                          if case.subject.startswith("AscentMatching::")}, original)

    def test_exact_positive_and_named_negative(self):
        for case in (self.positive, self.negative):
            check_validation(case, validation_for(case))

    def test_missing_extra_duplicate_and_foreign_assertions_reject(self):
        for fault in ("missing", "extra", "duplicate", "foreign"):
            with self.subTest(fault=fault):
                result = validation_for(self.positive)
                if fault == "missing":
                    result.verdicts.pop()
                elif fault == "extra":
                    result.verdicts.append(result.verdicts[0])
                elif fault == "duplicate":
                    result.verdicts[1] = result.verdicts[0]
                else:
                    result.verdicts[0]._pb.element_id = "Foreign::sourceEvidenceRequired"
                with self.assertRaises(ValueError):
                    check_validation(self.positive, result)

    def test_unresolved_and_execution_error_are_not_counterexamples(self):
        for fault in ("status", "error", "bounded", "summary", "inconsistent"):
            with self.subTest(fault=fault):
                result = validation_for(self.negative)
                if fault == "status":
                    result.verdicts[0]._pb.status = "undecided"
                elif fault == "error":
                    result.verdicts[0]._pb.error = "evaluation exhausted"
                elif fault == "bounded":
                    result.bounded = True
                elif fault == "summary":
                    result.summary = None
                else:
                    result.verdicts[0]._pb.status = "holds"
                with self.assertRaises((ValueError, opensysml.ExecutionError)):
                    check_validation(self.negative, result)

    def test_wrong_failed_assertion_and_false_success_reject(self):
        result = validation_for(self.negative)
        for verdict in result:
            verdict._pb.holds = not verdict.holds
            verdict._pb.status = "holds" if verdict.holds else "violated"
        with self.assertRaises(ValueError):
            check_validation(self.negative, result)
        with self.assertRaises(ValueError):
            check_validation(self.negative, validation_for(self.positive))

    def test_wrong_object_instance_and_summary_reject(self):
        for fault in ("object", "instance", "path", "summary"):
            with self.subTest(fault=fault):
                result = validation_for(self.positive)
                if fault == "object":
                    result.summary._pb.element_id = "AscentDevelopment::other"
                elif fault == "instance":
                    result.verdicts[0]._pb.instance_id = 2
                elif fault == "path":
                    result.verdicts[0]._pb.instance_path = "child"
                else:
                    result.summary._pb.status = "violated"
                with self.assertRaises(ValueError):
                    check_validation(self.positive, result)

    def test_real_deadline_interrupts_and_restores_handler(self):
        previous = signal.getsignal(signal.SIGALRM)
        with self.assertRaises(TimeoutError):
            with deadline(0.01):
                time.sleep(1)
        self.assertEqual(signal.getsignal(signal.SIGALRM), previous)
        self.assertEqual(signal.getitimer(signal.ITIMER_REAL), (0.0, 0.0))
