;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/core/relation-view :gerbil-ascent/table/trrel-uf
        :gerbil-ascent/t/performance/uf-boundary/fixture
        (prefix-in :gerbil-ascent/t/performance/uf-boundary/reference-trrel-uf old-))
(export ascent-uf-boundary-test)
(def (rows state) (gerbil-ascent-view-rows (gerbil-ascent-trrel-uf-freeze state #f)))
(def (exercise scenario grouped? scalar?)
  (let* ((input (map (lambda (row) (map (cut quotient <> 4) row)) (boundary-input scenario)))
         (input (if grouped? (map (cut cons 'group <>) input) input))
         (old (old-gerbil-ascent-trrel-uf-state)) (new (gerbil-ascent-trrel-uf-state)))
    (for-each (lambda (row)
      (let ((expected (old-gerbil-ascent-trrel-uf-count-insert! old row 2000000))
            (actual (if scalar? (relation-view-count (gerbil-ascent-trrel-uf-insert! new row 2000000))
                      (gerbil-ascent-trrel-uf-count-insert! new row 2000000))))
        (check-equal? actual expected))) input)
    (check-equal? (gerbil-ascent-trrel-uf-validate new) #t)
    (check-equal? (gerbil-ascent-trrel-uf-observation new) (old-gerbil-ascent-trrel-uf-observation old))
    (let* ((actual (rows new))
           (expected (gerbil-ascent-view-rows (old-gerbil-ascent-trrel-uf-freeze old #f)))
           (seen (list->hash-table (map (cut cons <> #t) actual))))
      (check-equal? (length actual) (length expected))
      (check-equal? (hash-length seen) (length expected))
      (check-equal? (andmap (cut hash-get seen <>) expected) #t))))
(def ascent-uf-boundary-test
  (test-suite "dense UF differences and SCC boundary retirement"
    (test-case "complete paired trajectories and grouped scalar frontiers"
      (for-each (lambda (s) (exercise s #f #f) (exercise s #t #t))
        '(bridge partial complete overlap weighted small)))
    (test-case "failed dense difference and SCC admission is physically atomic"
      (for-each (lambda (s)
        (let* ((input (map (lambda (row) (map (cut quotient <> 4) row)) (boundary-input s)))
               (last (last input))
               (old (old-gerbil-ascent-trrel-uf-state)) (new (gerbil-ascent-trrel-uf-state)))
          (for-each (lambda (row)
            (old-gerbil-ascent-trrel-uf-count-insert! old row 2000000)
            (gerbil-ascent-trrel-uf-count-insert! new row 2000000)) (take input (- (length input) 1)))
          (let* ((needed (old-gerbil-ascent-trrel-uf-count-insert! old last 2000000))
                 (cut (gerbil-ascent-trrel-uf-freeze new #f)) (saved (gerbil-ascent-view-rows cut))
                 (physical (gerbil-ascent-trrel-uf-resource-observation new)))
            (check-exception (gerbil-ascent-trrel-uf-count-insert! new last (- needed 1)) true)
            (check-equal? (gerbil-ascent-trrel-uf-resource-observation new) physical)
            (check-equal? (rows new) saved)
            (check-equal? (gerbil-ascent-trrel-uf-count-insert! new last needed) needed)
            (check-equal? (gerbil-ascent-view-rows cut) saved)
            (check-equal? (gerbil-ascent-trrel-uf-validate new) #t)))) '(bridge partial complete)))))
