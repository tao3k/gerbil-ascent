;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Bounded, inert rule proposals against a caller-owned snapshot.
;;; A receipt is an observation of one candidate, not source admission.
;;; Shared bounded proposal data and source snapshot value types.
(export make-reasoning-snapshot reasoning-snapshot?
        reasoning-snapshot-identity
        reasoning-snapshot-generation reasoning-snapshot-digest
        reasoning-snapshot-relations
        make-reasoning-diagnostic reasoning-diagnostic?
        reasoning-diagnostic-code
        reasoning-diagnostic-path reasoning-diagnostic-detail
        make-reasoning-candidate reasoning-candidate-relations
        reasoning-candidate-facts reasoning-candidate-rules
        reasoning-candidate-query reasoning-candidate-limits
        make-candidate-rejection candidate-rejection?
        candidate-rejection-diagnostic
        +max-relations+ +max-rules+ +max-input-facts+
        +max-derived-facts+ +max-output-facts+)

(defstruct reasoning-snapshot (identity generation digest relations))
(defstruct reasoning-diagnostic (code path detail))
(defstruct reasoning-candidate (relations facts rules query limits))
(defstruct candidate-rejection (diagnostic))

(def +max-relations+ 64)
(def +max-rules+ 64)
(def +max-input-facts+ 1024)
(def +max-derived-facts+ 4096)
(def +max-output-facts+ 4096)

;;; Candidate rows may be caller-owned pairs. Copy nested pairs at the
;;; receipt boundary so later edits to a proposal cannot rewrite evidence.
