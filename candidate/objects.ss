;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import
  (only-in :clan/poo/object .o)
  "func.ss")

(export CandidateAPI)

(def CandidateAPI
  (.o
    inspect: candidate-inspect
    snapshot: reasoning-source-snapshot
    attempt: reasoning-attempt
    receipt-digest: reasoning-receipt-candidate-digest
    receipt-status: reasoning-receipt-status
    receipt-rows: reasoning-receipt-rows
    capture: candidate-finite-evidence
    verify: candidate-verify-finite-evidence
    closure: gerbil-ascent-closure-candidates
    count: candidate-positive-counts
    stratify: candidate-stratified-provenance
    withhold: reasoning-withhold-source-snapshot
    compare: reasoning-compare-attempts
    open-withdrawal: candidate-open-withdrawal-session))
