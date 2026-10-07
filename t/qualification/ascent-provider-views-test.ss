;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? check-exception test-suite)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :gerbil-ascent/table/trrel-uf
                 gerbil-ascent-trrel-uf-state gerbil-ascent-trrel-uf-extension
                 gerbil-ascent-trrel-uf-frontier-extension gerbil-ascent-trrel-uf-snapshot
                 gerbil-ascent-trrel-uf-view-count gerbil-ascent-trrel-uf-view-for-each
                 gerbil-ascent-trrel-uf-view-lookup gerbil-ascent-trrel-uf-observation
                 gerbil-ascent-trrel-uf-validate))
(export ascent-provider-views-test)

(def edges '((0 0) (0 1) (0 2) (1 0) (1 1) (1 2) (2 0) (2 1) (2 2)))
(def (selected mask)
  (let loop ((remaining edges) (bit 1) (out []))
    (if (null? remaining) (reverse out)
      (loop (cdr remaining) (* bit 2)
        (if (odd? (quotient mask bit)) (cons (car remaining) out) out)))))

;;; Independent fixed-size Boolean adjacency/Floyd model, without UF code.
(def (truth inputs)
  (let ((active (make-vector 3 #f)) (matrix (make-vector 9 #f)) (out []))
    (for-each (lambda (edge)
      (vector-set! active (car edge) #t)
      (vector-set! active (cadr edge) #t)
      (vector-set! matrix (+ (* 3 (car edge)) (cadr edge)) #t)) inputs)
    (for-each (lambda (n)
      (when (vector-ref active n) (vector-set! matrix (+ (* 3 n) n) #t))) (iota 3))
    (for-each (lambda (k)
      (for-each (lambda (i)
        (for-each (lambda (j)
          (when (and (vector-ref matrix (+ (* 3 i) k))
                     (vector-ref matrix (+ (* 3 k) j)))
            (vector-set! matrix (+ (* 3 i) j) #t))) (iota 3))) (iota 3))) (iota 3))
    (for-each (lambda (edge)
      (when (vector-ref matrix (+ (* 3 (car edge)) (cadr edge)))
        (set! out (cons edge out)))) edges)
    (reverse out)))

(def (export-view view)
  (let (out [])
    (gerbil-ascent-trrel-uf-view-for-each view (lambda (row) (set! out (cons row out))))
    (reverse out)))
(def (check-rows actual expected)
  (check-equal? (length actual) (length expected))
  (for-each (lambda (row) (check-equal? (and (member row actual) #t) #t)) expected))

(def ascent-provider-views-test
  (test-suite "frozen BYODS Provider views"
    (poo-flow-test-case "all graph prefixes preserve exact frontiers counts and frozen old views"
      (for-each (lambda (mask)
        (for-each (lambda (order)
          (let ((state (gerbil-ascent-trrel-uf-state)) (inputs []) (old []))
            (for-each (lambda (edge)
              (let* ((before (gerbil-ascent-trrel-uf-snapshot state))
                     (physical-before (gerbil-ascent-trrel-uf-observation state))
                     (next (truth (cons edge inputs)))
                     (expected (filter (lambda (row) (not (member row old))) next)))
                (when (pair? expected)
                  (check-exception
                    (gerbil-ascent-trrel-uf-frontier-extension state edge (- (length expected) 1)) true)
                  (check-equal? (gerbil-ascent-trrel-uf-observation state) physical-before)
                  (check-equal? (gerbil-ascent-trrel-uf-validate state) #t))
                (let* ((frontier (gerbil-ascent-trrel-uf-frontier-extension state edge (length expected)))
                       (total (gerbil-ascent-trrel-uf-snapshot state)))
                  (check-equal? (gerbil-ascent-trrel-uf-validate state) #t)
                  (check-rows (export-view frontier) expected)
                  (check-equal? (gerbil-ascent-trrel-uf-view-count frontier) (length expected))
                  (check-rows (export-view total) next)
                  (check-equal? (gerbil-ascent-trrel-uf-view-count total) (length next))
                  (check-rows (export-view before) old)
                  (for-each (lambda (key)
                    (check-rows (gerbil-ascent-trrel-uf-view-lookup total '(0) (list key))
                      (filter (lambda (row) (= (car row) key)) next))) (iota 3))
                  (check-equal? (gerbil-ascent-trrel-uf-view-count
                    (gerbil-ascent-trrel-uf-frontier-extension state edge 0)) 0))
                (set! inputs (cons edge inputs)) (set! old next))) order)))
          (list (selected mask) (reverse (selected mask))))
        (when (= (modulo (+ mask 1) 64) 0)
          (displayln "PROVIDER-VIEWS-CHECKED graphs=" (+ mask 1)) (force-output))) (iota 512)))
    (poo-flow-test-case "balanced largest-component merges retain valid parent chains and external arcs"
      (let (state (gerbil-ascent-trrel-uf-state))
        ;; Four pairs, two size-four SCCs, then size eight: losing roots retain
        ;; multi-level parent chains. External predecessor/successor keys survive.
        (for-each (lambda (edge)
          (gerbil-ascent-trrel-uf-frontier-extension state edge 200)
          (check-equal? (gerbil-ascent-trrel-uf-validate state) #t))
          '((8 0) (7 9) (0 1) (1 0) (2 3) (3 2) (4 5) (5 4) (6 7) (7 6)
            (1 2) (3 0) (5 6) (7 4) (3 4) (7 0)))
        (check-equal? (gerbil-ascent-trrel-uf-observation state) '#(10 3 3))
        (check-equal? (gerbil-ascent-trrel-uf-view-count
                      (gerbil-ascent-trrel-uf-snapshot state)) 83)))
    (poo-flow-test-case "held frontier survives later SCC merges and exported row mutation"
      (let* ((state (gerbil-ascent-trrel-uf-state))
             (frontier (gerbil-ascent-trrel-uf-frontier-extension state '(0 1) 3))
             (old (gerbil-ascent-trrel-uf-snapshot state))
             (expected '((0 0) (1 1) (0 1))))
        (gerbil-ascent-trrel-uf-frontier-extension state '(1 2) 3)
        (gerbil-ascent-trrel-uf-frontier-extension state '(2 0) 3)
        (check-rows (export-view old) expected)
        (check-rows (export-view frontier) expected)
        (let (rows (export-view old)) (set-car! (car rows) 99))
        (check-rows (export-view old) expected)
        (check-rows (export-view frontier) expected)
        (check-equal? (gerbil-ascent-trrel-uf-view-count
                       (gerbil-ascent-trrel-uf-snapshot state)) 9)))
    (poo-flow-test-case "group keys and keyed reads retain exact concrete rows"
      (let (state (gerbil-ascent-trrel-uf-state))
        (gerbil-ascent-trrel-uf-frontier-extension state '(#f 0 1) 3)
        (let (old (gerbil-ascent-trrel-uf-snapshot state))
          (gerbil-ascent-trrel-uf-frontier-extension state '(#t 1 0) 3)
          (let (total (gerbil-ascent-trrel-uf-snapshot state))
            (check-rows (gerbil-ascent-trrel-uf-view-lookup total '(2 0) '(1 #f))
              '((#f 1 1) (#f 0 1)))
            (check-rows (gerbil-ascent-trrel-uf-view-lookup total '(0 1 2) '(#t 1 0))
              '((#t 1 0)))
            (check-equal? (gerbil-ascent-trrel-uf-view-lookup old '(0) '(#t)) [])
            (check-exception (gerbil-ascent-trrel-uf-view-lookup total '(3) '(0)) true)
            (check-exception (gerbil-ascent-trrel-uf-view-lookup total '(0 1) '(#t)) true)))))
    (poo-flow-test-case "compressed cycle total remains queryable without a tuple cache"
      (let (state (gerbil-ascent-trrel-uf-state))
        (for-each (lambda (n)
          (gerbil-ascent-trrel-uf-frontier-extension state (list n (modulo (+ n 1) 64)) 4096)) (iota 64))
        (let ((view (gerbil-ascent-trrel-uf-snapshot state)) (visited 0))
          (check-equal? (gerbil-ascent-trrel-uf-view-count view) 4096)
          (check-equal? (gerbil-ascent-trrel-uf-observation state) '#(64 1 0))
          (check-equal? (length (gerbil-ascent-trrel-uf-view-lookup view '(0) '(7))) 64)
          (gerbil-ascent-trrel-uf-view-for-each view (lambda (_) (set! visited (+ visited 1))))
          (check-equal? visited 4096)
          (check-equal? (gerbil-ascent-trrel-uf-observation state) '#(64 1 0)))))
    (poo-flow-test-case "list adapter preserves public extension row order"
      (let (state (gerbil-ascent-trrel-uf-state))
        (check-equal? (gerbil-ascent-trrel-uf-extension state [] [] '(0 1) 3)
          '((0 0) (1 1) (0 1)))
        (check-equal? (gerbil-ascent-trrel-uf-extension state [] [] '(1 2) 3)
          '((2 2) (1 2) (0 2)))
        (check-equal? (gerbil-ascent-trrel-uf-extension state [] [] '(2 0) 3)
          '((1 0) (2 1) (2 0)))))))
