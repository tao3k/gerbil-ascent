;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :gerbil-ascent/candidate/types make-reasoning-candidate)
        (only-in :gerbil-ascent/candidate/reasoning reasoning-source-snapshot)
        (only-in :gerbil-ascent/candidate/provenance
          candidate-positive-proof candidate-verify-positive-proof positive-proof-status positive-proof-nodes positive-proof-roots
          proof-node-id proof-node-kind proof-node-relation proof-node-row proof-node-label proof-node-inputs)
        (rename-in (only-in :gerbil-ascent/t/performance/proof-replay/reference
          candidate-positive-proof candidate-verify-positive-proof positive-proof-status positive-proof-nodes positive-proof-roots
          proof-node-id proof-node-kind proof-node-relation proof-node-row proof-node-label proof-node-inputs)
          (candidate-positive-proof old-produce) (candidate-verify-positive-proof old-verify)
          (positive-proof-status old-status) (positive-proof-nodes old-nodes) (positive-proof-roots old-roots)
          (proof-node-id old-id) (proof-node-kind old-kind) (proof-node-relation old-relation)
          (proof-node-row old-row) (proof-node-label old-label) (proof-node-inputs old-inputs)))
(export ascent-proof-replay-test)
(def (project proof status nodes roots id kind relation row label inputs)
  (list (status proof) (roots proof)
        (map (lambda (node) (list (id node) (kind node) (relation node) (row node) (label node) (inputs node))) (nodes proof))))
(def (compare input spec rows budget (valid? #t))
  (let ((a (old-produce input spec 'digest 'complete rows budget))
        (b (candidate-positive-proof input spec 'digest 'complete rows budget)))
    (check-equal? (project b positive-proof-status positive-proof-nodes positive-proof-roots proof-node-id proof-node-kind proof-node-relation proof-node-row proof-node-label proof-node-inputs)
                  (project a old-status old-nodes old-roots old-id old-kind old-relation old-row old-label old-inputs))
    (check-equal? (candidate-verify-positive-proof input spec 'digest 'complete rows b 5120)
                  (old-verify input spec 'digest 'complete rows a 5120))
    (when (eq? (positive-proof-status b) 'complete)
      (check-equal? (candidate-verify-positive-proof input spec 'digest 'complete rows b 5120) valid?))
    b))
(def (path-spec limit)
  (make-reasoning-candidate '((path . 2)) []
    (list (vector '(path ?x ?y) '((edge ?x ?y)) 1)
          (vector '(path ?x ?z) '((path ?x ?y) (edge ?y ?z)) 2))
    (vector '(path ?x ?y) 0) (list 64 limit 4096)))
(def ascent-proof-replay-test
  (test-suite "ordered proof queues and independent replay indexes"
    (test-case "all tiny directed graphs agree with independent transitive closure"
      (let (edges '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)))
        (for-each (lambda (mask)
          (let* ((selected (filter-map (lambda (edge bit)
                            (and (not (zero? (bitwise-and mask (arithmetic-shift 1 bit)))) edge)) edges (iota 6)))
                 (input (reasoning-source-snapshot 'source 0 (list (list 'edge 2 selected))))
                 (reach (make-vector 9 #f)))
            (for-each (lambda (edge) (vector-set! reach (+ (* 3 (car edge)) (cadr edge)) #t)) selected)
            (for-each (lambda (k) (for-each (lambda (i) (for-each (lambda (j)
              (when (and (vector-ref reach (+ (* 3 i) k)) (vector-ref reach (+ (* 3 k) j)))
                (vector-set! reach (+ (* 3 i) j) #t))) (iota 3))) (iota 3))) (iota 3))
            (let (rows (filter-map (lambda (i) (and (vector-ref reach i) (list (quotient i 3) (modulo i 3)))) (iota 9)))
              (for-each (lambda (budget) (compare input (path-spec 4096) rows budget)) '(1 2 4 8 16 32 64 128 256 512))))) (iota 64))))
    (test-case "every work boundary and derived cap preserves round admission"
      (let* ((input (reasoning-source-snapshot 'source 0 '((edge 2 ((0 1) (1 2) (2 0))))))
             (rows (apply append (map (lambda (i) (map (lambda (j) (list i j)) (iota 3))) (iota 3)))))
        (for-each (lambda (budget) (compare input (path-spec 4096) rows budget)) (iota 100 1))
        (for-each (lambda (limit) (compare input (path-spec limit) rows 1000)) (iota 12 1))))
    (test-case "duplicate source positions false facts and repeated labels retain first evidence"
      (let* ((input (reasoning-source-snapshot 'source 0 '((edge 1 ((#f) (#f) (1))))))
             (spec (make-reasoning-candidate [] (list (vector 'edge '(2) 42) (vector 'edge '(3) 42)) [] (vector '(edge ?x) 0) '(64 4096 4096)))
             (proof (compare input spec '((#f) (1) (2) (3)) 1000)))
        (check-equal? (map proof-node-label (positive-proof-nodes proof)) '(1 3 42 42))
        (set-car! (proof-node-row (car (positive-proof-nodes proof))) 99)
        (check-equal? (candidate-verify-positive-proof input spec 'digest 'complete '((#f) (1) (2) (3)) proof 5120) #f)
        (compare input spec '((#f) (1) (2) (3)) 1000)))
    (test-case "duplicate rule labels retain first-match independent rejection"
      (let* ((input (reasoning-source-snapshot 'source 0 '((edge 1 ((1))) (other 1 ((2))))))
             (spec (make-reasoning-candidate '((out . 1)) []
               (list (vector '(out ?x) '((edge ?x)) 7) (vector '(out ?x) '((other ?x)) 7))
               (vector '(out ?x) 0) '(64 4096 4096))))
        (compare input spec '((1) (2)) 1000 #f)))))
