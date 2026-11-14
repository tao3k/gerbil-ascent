;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/core/relation-view :gerbil-ascent/table/trrel-uf
        :gerbil-ascent/t/performance/uf-frontier/fixture
        (prefix-in :gerbil-ascent/t/performance/uf-frontier/reference-trrel-uf old-))
(export ascent-uf-frontier-test)
(def (compressed row)
  (map (lambda (n) (if (< n 257) (quotient n 4) (+ 65 (quotient (- n 257) 4)))) row))
(def (exercise scenario grouped? scalar?)
  (let* ((input (map compressed (frontier-input scenario)))
         (input (if grouped? (map (cut cons 'g <>) input) input))
         (old (old-gerbil-ascent-trrel-uf-state)) (new (gerbil-ascent-trrel-uf-state)))
    (for-each (lambda (row)
      (let (expected (old-gerbil-ascent-trrel-uf-insert! old row 2000000))
        (if scalar?
          (check-equal? (gerbil-ascent-view-rows (gerbil-ascent-trrel-uf-insert! new row 2000000))
                        (gerbil-ascent-view-rows expected))
          (check-equal? (gerbil-ascent-trrel-uf-count-insert! new row 2000000) (relation-view-count expected)))))
      (take input (- (length input) 1)))
    (let* ((row (last input)) (expected (old-gerbil-ascent-trrel-uf-insert! old row 2000000))
           (needed (relation-view-count expected))
           (before (gerbil-ascent-trrel-uf-freeze new #f)) (saved (gerbil-ascent-view-rows before))
           (physical (gerbil-ascent-trrel-uf-resource-observation new)))
      (check-exception (gerbil-ascent-trrel-uf-insert! new row (- needed 1)) true)
      (check-equal? (gerbil-ascent-trrel-uf-resource-observation new) physical)
      (let (seen (list->hash-table (map (cut cons <> #t) saved)))
        (let (current (gerbil-ascent-view-rows (gerbil-ascent-trrel-uf-freeze new #f)))
          (check-equal? (length current) (length saved))
          (check-equal? (andmap (cut hash-get seen <>) current) #t)))
      (let* ((frontier (gerbil-ascent-trrel-uf-insert! new row needed))
             (rows (gerbil-ascent-view-rows frontier)))
        (check-equal? rows (gerbil-ascent-view-rows expected))
        (check-equal? (relation-view-count frontier) needed)
        (gerbil-ascent-trrel-uf-count-insert! new (reverse row) 2000000)
        (check-equal? (gerbil-ascent-view-rows frontier) rows)
        (check-equal? (gerbil-ascent-view-rows before) saved))
      (check-equal? (gerbil-ascent-trrel-uf-validate new) #t))))
(def ascent-uf-frontier-test
  (test-suite "UF scalar publication and weighted admission"
    (test-case "exact ordered scalar frontiers, rejection and retained cuts"
      (for-each (lambda (s) (exercise s #f #t) (exercise s #t #t)) '(scalar weighted heavy)))
    (test-case "weighted counting and scalar retry use the same difference"
      (for-each (lambda (s) (exercise s #f #f)) '(weighted heavy partial)))))
