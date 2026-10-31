;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :gerbil-ascent/candidate/support-height grounded-support-heights)
        (only-in :gerbil-ascent/candidate/provenance-maintenance candidate-provenance-heights provenance-maintenance-rows)
        (only-in :gerbil-ascent/t/performance/support-height/fixture height-prepare height-consume height-verify!))
(export ascent-support-height-test)
(def ascent-support-height-test
  (test-suite "Dependency-driven grounded proof heights"
    (test-case "late shorter support propagates through conjunction and repeated premises"
      (let ((edges '((0 source seed ()) (1 rule a (0)) (2 rule b (1))
                     (3 rule long (2)) (4 source shortcut ()) (3 rule short (4))
                     (5 rule conjunction (2 2 3)) (5 rule cycle (5))))
            (alive (list->hash-table-eqv '((0 . #t) (1 . #t) (2 . #t) (3 . #t) (4 . #t) (5 . #t)))))
        (for-each (lambda (ordered)
                    (let (heights (grounded-support-heights ordered alive (make-hash-table) void))
                      (check (map (cut hash-ref heights <>) '(0 1 2 3 4 5)) => '(0 1 2 1 0 3))))
                  (list edges (reverse edges) (append (drop edges 4) (take edges 4))))))
    (test-case "empty rules seed height one and removed sources cannot seed cycles"
      (let* ((alive (list->hash-table-eqv '((0 . #t) (1 . #t) (2 . #t))))
             (removed (list->hash-table '((retired . #t))))
             (heights (grounded-support-heights
                        '((0 source retired ()) (0 rule cycle (1)) (1 rule back (0)) (2 rule empty ()))
                        alive removed void)))
        (check (hash-get heights 0) => #f)
        (check (hash-get heights 1) => #f)
        (check (hash-ref heights 2) => 1)))
    (test-case "complete admitted height compaction lifecycle matches frozen and independent truth"
      (for-each (lambda (scenario)
                  (let ((prior (height-prepare #t scenario)) (current (height-prepare #f scenario)))
                    (height-verify! prior) (height-verify! current)
                    (check (height-consume current scenario) => (height-consume prior scenario))))
                '(chain withdrawn small)))
    (test-case "every insufficient height budget leaves accepted rows untouched"
      (let* ((prepared (height-prepare #f 'small)) (state (cadr prepared))
             (rows (provenance-maintenance-rows state)))
        (let-values (((expected work) (candidate-provenance-heights state)))
          (for-each (lambda (budget)
                      (check-exception (candidate-provenance-heights state budget) (lambda (_) #t))
                      (check (provenance-maintenance-rows state) => rows)) (iota (- work 1) 1))
          (let-values (((actual measured) (candidate-provenance-heights state work)))
            (check actual => expected) (check measured => work)))))))
