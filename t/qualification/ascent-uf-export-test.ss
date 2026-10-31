;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/core/relation-view
        :gerbil-ascent/t/performance/uf-export/fixture
        (only-in :gerbil-ascent/table/trrel-uf gerbil-ascent-trrel-uf-state
                 gerbil-ascent-trrel-uf-insert! gerbil-ascent-trrel-uf-replay-insert!
                 gerbil-ascent-trrel-uf-freeze gerbil-ascent-trrel-uf-observation gerbil-ascent-trrel-uf-validate)
        (prefix-in :gerbil-ascent/t/performance/uf-export/reference-trrel-uf old-))
(import (prefix-in :gerbil-ascent/program/view-state current-)
        (prefix-in :gerbil-ascent/t/performance/uf-export/reference-view-state historical-))
(export ascent-uf-export-test)
(def ascent-uf-export-test
  (test-suite "Sparse UF export and immutable cut capture"
    (test-case "all fixed engine and capture scenarios preserve independent truth"
      (for-each (lambda (scenario)
        (let* ((old (ue-prepare #t scenario)) (new (ue-prepare #f scenario))
               (expected (ue-expected old scenario)))
          (check-equal? (ue-consume old scenario #t) expected)
          (check-equal? (ue-consume new scenario #f) expected)))
        '(sparse grouped retained capture cold small packed eqrel)))
    (test-case "consecutive empty frontiers cross source and derived events"
      (for-each (lambda (eqrel?)
        (let* ((specs (list (cons (quote source) (quote ((0 1) (0 1))))
                            (cons (quote derived) (quote ((0 1) (0 1))))
                            (cons (quote append) (quote ((0 1) (1 0) (1 0))))))
               (cut (gerbil-ascent-explicit-view (quote ((0 0) (0 1) (1 0) (1 1))) 4))
               (old (map (lambda (entry) (historical-gerbil-ascent-view-journal-event (car entry) (cdr entry) eqrel?)) specs))
               (new (map (lambda (entry) (current-gerbil-ascent-view-journal-event (car entry) (cdr entry) eqrel?)) specs)))
          (check-equal? (gerbil-ascent-view-rows (current-gerbil-ascent-view-export-cut cut new eqrel?))
                        (gerbil-ascent-view-rows (historical-gerbil-ascent-view-export-cut cut old eqrel?)))))
        (list #f #t)))
    (test-case "all three-node graphs preserve synchronous frontier and read-only rejection"
      (let (edges (apply append (map (lambda (a) (map (cut list a <>) (iota 3))) (iota 3))))
        (for-each (lambda (mask)
          (let ((old (old-gerbil-ascent-trrel-uf-state)) (new (gerbil-ascent-trrel-uf-state)))
            (for-each (lambda (edge bit)
              (when (not (= 0 (bitwise-and mask (arithmetic-shift 1 bit))))
                (let* ((view (old-gerbil-ascent-trrel-uf-insert! old edge 100))
                       (count (relation-view-count view)) (before (gerbil-ascent-trrel-uf-observation new))
                       (called? #f) (rows []))
                  (when (> count 0)
                    (check-exception (gerbil-ascent-trrel-uf-replay-insert! new edge (- count 1)
                                       (lambda (_) (set! called? #t) #f)) true)
                    (check-equal? called? #f)
                    (check-equal? (gerbil-ascent-trrel-uf-observation new) before)
                    (check-equal? (gerbil-ascent-trrel-uf-validate new) #t))
                  (gerbil-ascent-trrel-uf-replay-insert! new edge count
                    (lambda (n) (check-equal? n count) (lambda (row) (set! rows (cons row rows)))))
                  (check-equal? (reverse rows) (gerbil-ascent-view-rows view))))) edges (iota 9)))) (iota 512))))
    (test-case "borrowed immutable members survive merge retirements and public mutation"
      (for-each (lambda (indexed?)
        (let ((state (gerbil-ascent-trrel-uf-state)))
          (gerbil-ascent-trrel-uf-insert! state '(0 1) 100)
          (let* ((held (gerbil-ascent-trrel-uf-freeze state indexed?))
                 (saved (gerbil-ascent-view-rows held)) (public (gerbil-ascent-view-rows held)))
            (set-car! (car public) 999)
            (for-each (cut gerbil-ascent-trrel-uf-insert! state <> 100) '((1 0) (1 2) (2 0) (2 3) (3 2)))
            (check-equal? (gerbil-ascent-trrel-uf-validate state) #t)
            (check-equal? (gerbil-ascent-view-rows held) saved)
            (check-equal? (relation-view-count held) 3)
            (check-equal? (gerbil-ascent-view-contains? held '(2 2)) #f)))) '(#f #t)))
    (test-case "rectangle writers detach arbitrary prefixes and member spines"
      (for-each (lambda (prefix)
        (let* ((lefts '(1 2)) (rights '(3 4))
               (blocks (list (make-rectangle prefix lefts rights))) (rows []))
          (gerbil-ascent-write-rectangles! blocks (lambda (row) (set! rows (cons row rows))))
          (check-equal? (reverse rows) (map (cut append prefix <>) '((1 3) (1 4) (2 3) (2 4))))
          (set-car! (car rows) 999)
          (check-equal? lefts '(1 2)) (check-equal? rights '(3 4))
          (let (again [])
            (gerbil-ascent-write-rectangles! blocks (lambda (row) (set! again (cons row again))))
            (check-equal? (reverse again) (map (cut append prefix <>) '((1 3) (1 4) (2 3) (2 4)))))))
        '(() (#f) (scope label))))))
