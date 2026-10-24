;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object :gerbil-ascent/core/relation-view
        :gerbil-ascent/t/performance/view-export/fixture
        (only-in :gerbil-ascent/table/eqrel gerbil-ascent-eqrel-state gerbil-ascent-eqrel-replay-insert!)
        (prefix-in :gerbil-ascent/t/performance/view-export/reference-eqrel old-)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine)
        (prefix-in :gerbil-ascent/t/performance/view-export/reference-evaluate old-))
(export ascent-view-export-test)
(def ascent-view-export-test
  (test-suite "Complete frozen view publication and ordered export"
    (test-case "complete engines preserve matrix closure and historical export order"
      (for-each (lambda (scenario)
        (let* ((old (ve-prepare #t scenario)) (new (ve-prepare #f scenario))
               (expected (ve-expected old scenario)))
          (check-equal? (ve-consume old scenario #t) expected)
          (check-equal? (ve-consume new scenario #f) expected)))
        '(eqrel grouped retained cold small uf derived native)))
    (test-case "synchronous emission matches frozen frontiers over all three-node graphs"
      (let (edges (apply append (map (lambda (a) (map (cut list a <>) (iota 3))) (iota 3))))
        (for-each (lambda (mask)
          (let ((old (old-gerbil-ascent-eqrel-state)) (new (gerbil-ascent-eqrel-state)))
            (for-each (lambda (edge bit)
              (when (not (= 0 (bitwise-and mask (arithmetic-shift 1 bit))))
                (let ((rows []) (count #f)
                      (view (old-gerbil-ascent-eqrel-insert! old edge 100)))
                  (gerbil-ascent-eqrel-replay-insert! new edge 100
                    (lambda (n) (set! count n) (lambda (row) (set! rows (cons row rows)))))
                  (check-equal? count (relation-view-count view))
                  (check-equal? (reverse rows) (gerbil-ascent-view-rows view))))) edges (iota 9)))) (iota 512))))
    (test-case "budget rejection precedes writer selection and declined output retains state"
      (let ((state (gerbil-ascent-eqrel-state)) (called? #f))
        (check-exception (gerbil-ascent-eqrel-replay-insert! state '(1 2) 3
                           (lambda (_) (set! called? #t) #f)) true)
        (check-equal? called? #f)
        (gerbil-ascent-eqrel-replay-insert! state '(1 2) 4
          (lambda (n) (check-equal? n 4) #f))
        (gerbil-ascent-eqrel-replay-insert! state '(2 1) 0
          (lambda (n) (check-equal? n 0) #f))))
    (test-case "repeated exports detach rows and preserve held cuts after source append"
      (let* ((program (ve-program 'small))
             (new (gerbil-ascent-make-engine program #t))
             (old (old-gerbil-ascent-make-engine program #t))
             (first ((.ref new '.run))) (old-first ((.ref old '.run))) (saved (ve-project first))
             (rows ((.ref first 'rows-of) 'reach)))
        (set-car! (car rows) 999)
        (check-equal? (ve-project first) saved)
        (for-each (lambda (row)
          (for-each (lambda (engine) ((.ref engine '.append-source!) 'reach row)) (list old new))
          (check-equal? (ve-project ((.ref new '.run))) (ve-project ((.ref old '.run)))) )
          '((1 2) (2 0) (2 3)))
        (check-equal? (ve-project first) saved)
        (check-equal? (eq? ((.ref new '.run)) ((.ref new '.run))) #t)))))
