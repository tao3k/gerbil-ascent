;;; -*- Gerbil -*-
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in "declaration.ss" ascent-rule-module)
        (only-in :gerbil-ascent/program/func gerbil-ascent-program)
        (only-in :clan/poo/object .ref with-slots))
(export make-recorded-module source-capacity)

;; : (-> Fragment Sources FactLimit FactLimit FactLimit RuleModule)
;;; Intentional raw data record: the explanation callback emits a recorded-only transport hash, never an extensible object or provenance authority.
(def (make-recorded-module fragment sources (input-limit +inf.0)
                           (derived-limit +inf.0) (output-limit +inf.0))
  ;; with-slots expands at each use; no fields are hoisted or cached.
  (with-slots (relations rules) fragment
    (let* ((program (gerbil-ascent-program relations rules
                      input-limit derived-limit output-limit sources)))
      (ascent-rule-module program
        (lambda (program result query scope)
          (hash ("status" "recorded-only") ("query" query) ("scope" scope)
                ("dependencies" (.ref program 'rules))
                ("gap" "Declaration dependencies and current source rows are not per-row proof or execution authority")))))))

;; Admission observation only: count every supplied tuple, including unchanged
;; and backend-resource rows. Never derive deltas or bypass the Program limit.
;; : (-> Sources PositiveInteger CapacityObservation)
(def (source-capacity sources limit)
  (unless (and (list? sources) (exact-integer? limit) (> limit 0))
    (error "explicit source inventory and positive capacity required"))
  (let ((seen (make-hash-table)) (counts []) (total 0))
    (for-each (lambda (source)
      (let ((name (hash-ref source "relation")) (rows (hash-ref source "rows")))
        (unless (and (string? name) (list? rows) (andmap list? rows)
                     (not (hash-get seen name)))
          (error "unique tuple source inventory required"))
        (hash-put! seen name #t)
        (let (count (length rows))
          (set! total (+ total count))
          (set! counts (cons (list name count) counts))))) sources)
    (hash ("status" (if (> total limit) "DENY" "WITHIN_CAPACITY"))
          ("limit" limit) ("sourceOccurrences" total) ("relations" (reverse counts))
          ("scope" "Capacity observation only; no inference, proof, retry or execution admission"))))
