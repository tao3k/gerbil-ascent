;;; -*- Gerbil -*-
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/rules/interface (only-in :clan/poo/object .ref))
(export make-recorded-module source-capacity)

(def (make-recorded-module fragment sources (input-limit +inf.0)
                           (derived-limit +inf.0) (output-limit +inf.0))
  (let* ((program (gerbil-ascent-program (.ref fragment 'relations) (.ref fragment 'rules)
                    input-limit derived-limit output-limit sources)))
    (ascent-rule-module program
      (lambda (program result query scope)
        (hash ("status" "recorded-only") ("query" query) ("scope" scope)
              ("dependencies" (.ref program 'rules))
              ("gap" "Declaration dependencies and current source rows are not per-row proof or execution authority"))))))

;; Admission observation only: count every supplied tuple, including unchanged
;; and backend-resource rows. Never derive deltas or bypass the Program limit.
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
