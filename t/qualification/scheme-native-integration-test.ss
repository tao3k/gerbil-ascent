;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception
                 test-case test-suite)
        (only-in :gerbil-ascent/program/interface
                 relational-fragment relational-finite-view
                 relational-lattice-fragment relational-compose
                 relational-export relational-open-session
                 relational-session-run relational-session-replace-source!
                 relational-session-prepare-transaction relational-session-transaction!
                 relational-query
                 relational-op-source relational-op-union
                 relational-op-join relational-op-project
                 relational-op-fix relational-op-fragment
                 relational-op-function relational-op-apply))

(export scheme-native-integration-test)

(def (same-rows? actual expected)
  (and (= (length actual) (length expected))
       (andmap (lambda (row) (if (member row expected) #t #f))
               actual)))

;;; A separate finite model for the combined language path. It computes
;;; closure by a four-vertex matrix, then joins weights, counts distinct
;;; weighted facts, and takes the maximum per lattice key.
(def (reference-result edges blocked roots mapping seeds)
  (let (matrix (make-vector 16 #f))
    (def (slot from to)
      (+ (* 4 (- from 1)) (- to 1)))
    (for-each
     (lambda (edge)
       (vector-set! matrix (slot (car edge) (cadr edge)) #t))
     edges)
    (for-each
     (lambda (pivot)
       (for-each
        (lambda (from)
          (for-each
           (lambda (to)
             (when (and (vector-ref matrix (slot from pivot))
                        (vector-ref matrix (slot pivot to)))
               (vector-set! matrix (slot from to) #t)))
           '(1 2 3 4)))
        '(1 2 3 4)))
     '(1 2 3 4))
    (let (weighted [])
      (for-each
       (lambda (from)
         (for-each
          (lambda (to)
            (when (and (vector-ref matrix (slot from to))
                       (not (member (list from to) blocked)))
              (for-each
               (lambda (entry)
                 (when (= to (caar entry))
                   (let (row (list from (caadr entry)))
                     (unless (member row weighted)
                       (set! weighted (cons row weighted))))))
               mapping)))
          '(1 2 3 4)))
       '(1 2 3 4))
      (let ((counts
             (map
              (lambda (root)
                (list (car root)
                      (length
                       (filter (lambda (row) (= (car row) (car root)))
                               weighted))))
              roots))
            (best [])
            (all (append weighted seeds)))
        (for-each
         (lambda (row)
           (unless (assq (car row) best)
             (let (values
                   (map cadr
                        (filter (lambda (candidate)
                                  (= (car candidate) (car row)))
                                all)))
               (set! best (cons (list (car row) (apply max values)) best)))))
         all)
        (values counts best)))))

(def (check-result-against-model solution counts best
                                 edges blocked roots mapping seeds)
  (let-values (((expected-counts expected-best)
                (reference-result edges blocked roots mapping seeds)))
    (check-equal?
     (same-rows? (relational-query solution counts 'cardinality)
                 expected-counts) #t)
    (check-equal?
     (same-rows? (relational-query solution best 'best)
                 expected-best) #t)))

(def (edge-source)
  (let (raw-edge
        (relational-op-source 'raw-edge 2
                              '((1 2) (1 3) (2 3) (3 4))))
    (let (step
          (relational-op-function
           2
           (lambda (path)
             (relational-op-project
              (relational-op-join path raw-edge 1 0) '(0 3)))))
      (relational-op-fragment
       (relational-op-fix
        2 (lambda (path)
            (relational-op-union
             raw-edge (relational-op-apply step path))))
       'edge))))

(def (blocked-source)
  (relational-fragment
   (import)
   (source (blocked (from to) '((1 3))))
   (private)
   (export (blocked blocked))))

(def (root-source)
  (relational-fragment
   (import)
   (source (root (node) '((1) (2) (3))))
   (private)
   (export (root root))))

(def (allowed-fragment edge-handle blocked-handle)
  (relational-fragment
   (import (edge edge-handle) (blocked blocked-handle))
   (source)
   (private (allowed (from to)))
   (export (allowed allowed))
   (rule (allowed ?x ?y)
     (edge ?x ?y)
     (not (blocked ?x ?y)))))

(def (weighted-fragment allowed-handle weight-handle)
  (relational-fragment
   (import (allowed allowed-handle) (weight weight-handle))
   (source)
   (private (weighted (from value)))
   (export (weighted weighted))
   (rule (weighted ?x ?w)
     (allowed ?x ?y)
     (weight ?y ?w))))

(def (count-fragment root-handle weighted-handle)
  (relational-fragment
   (import (root root-handle) (weighted weighted-handle))
   (source)
   (private (cardinality (node count)))
   (export (cardinality cardinality))
   (rule (cardinality ?root ?n)
     (root ?root)
     (reduce ?n (count) (weighted ?root ?w)))))

(def (best-fragment weighted-handle best-handle)
  (relational-fragment
   (import (weighted weighted-handle) (best best-handle))
   (source)
   (private)
   (export)
   (rule (best ?root ?value)
     (weighted ?root ?value))))

(def scheme-native-integration-test
  (test-suite "native Scheme combined language lifecycle"
    (test-case "views, negation, reduction and lattice survive withdrawal"
      (let* ((edges (edge-source))
             (blocked (blocked-source))
             (roots (root-source))
             (view (relational-finite-view
                    'weight 1 1
                    '(((2) (5)) ((3) (7)) ((3) (11)))))
             (allowed
              (allowed-fragment
               (relational-export edges 'edge)
               (relational-export blocked 'blocked)))
             (weighted
              (weighted-fragment
               (relational-export allowed 'allowed)
               (relational-export view 'weight)))
             (counts
              (count-fragment
               (relational-export roots 'root)
               (relational-export weighted 'weighted)))
             (best
              (relational-lattice-fragment 'best 2 [] 'max))
             (best-rule
              (best-fragment
               (relational-export weighted 'weighted)
               (relational-export best 'best)))
             (session
              (relational-open-session
               (relational-compose
                (list edges blocked roots view allowed weighted
                      counts best best-rule)
                32 64 128)))
             (first (relational-session-run session)))
        (check-equal?
         (same-rows? (relational-query first counts 'cardinality)
                     '((1 1) (2 2) (3 0))) #t)
        (check-equal?
         (same-rows? (relational-query first best 'best)
                     '((1 5) (2 11))) #t)
        (check-result-against-model
         first counts best
         '((1 2) (1 3) (2 3) (3 4)) '((1 3))
         '((1) (2) (3)) '(((2) (5)) ((3) (7)) ((3) (11))) '())
        (relational-session-replace-source!
         session blocked 'blocked '((1 2)))
        (let (second (relational-session-run session))
          (check-equal?
           (same-rows? (relational-query second counts 'cardinality)
                       '((1 2) (2 2) (3 0))) #t)
          (check-equal?
           (same-rows? (relational-query second best 'best)
                       '((1 11) (2 11))) #t)
          (check-equal?
           (same-rows? (relational-query first counts 'cardinality)
                       '((1 1) (2 2) (3 0))) #t)
          (check-equal?
           (same-rows? (relational-query first best 'best)
                       '((1 5) (2 11))) #t)
          (relational-session-replace-source!
           session edges 'raw-edge '((1 2)))
          (let (third (relational-session-run session))
            (check-equal?
             (same-rows? (relational-query third counts 'cardinality)
                         '((1 0) (2 0) (3 0))) #t)
            (check-equal? (relational-query third best 'best) '())
            (check-equal?
             (same-rows? (relational-query second best 'best)
                         '((1 11) (2 11))) #t)
            (let* ((new-edges '((1 2) (2 4)))
                   (new-blocked '((1 2)))
                   (new-roots '((1) (2) (4)))
                   (new-mapping '(((2) (5)) ((4) (9))))
                   (new-seeds '((4 15)))
                   (replace-all
                    (relational-session-prepare-transaction
                     session (list (list edges 'raw-edge)
                                   (list blocked 'blocked)
                                   (list roots 'root)
                                   (list view 'weight)
                                   (list best 'best))))
                   (fourth
                    (replace-all
                     (list new-edges new-blocked new-roots
                           '((2 5) (4 9)) new-seeds))))
              (check-result-against-model
               fourth counts best new-edges new-blocked new-roots
               new-mapping new-seeds)
              (check-equal?
               (same-rows? (relational-query third counts 'cardinality)
                           '((1 0) (2 0) (3 0))) #t)
              (check-exception
               (relational-session-transaction!
                session (list (list edges 'raw-edge '((1 2)))
                              (list view 'weight '((2 5 7 9))))) true)
              (check-exception
               (relational-session-transaction!
                session (list (list edges 'raw-edge new-edges)
                              (list edges 'raw-edge '()))) true)
              (check-exception
               (relational-session-transaction!
                session
                (list
                 (list edges 'raw-edge
                       (map (lambda (node) (list node (+ node 1)))
                            (iota 19 1))))) true)
              (check-equal?
               (same-rows? (relational-query fourth best 'best)
                           '((1 9) (2 9) (4 15))) #t)
              (let (fifth
                    (relational-session-transaction!
                     session (list (list edges 'raw-edge '()))))
                (check-result-against-model
                 fifth counts best '() new-blocked new-roots
                 new-mapping new-seeds)
                (check-equal?
                 (same-rows? (relational-query fourth best 'best)
                             '((1 9) (2 9) (4 15))) #t)
                ;; Prepared source scope spans fragments and reuses the current
                ;; full transaction owner after an intervening dynamic update.
                (let (sixth (replace-all
                             (list new-edges new-blocked new-roots
                                   '((2 5) (4 9)) new-seeds)))
                  (check-result-against-model
                   sixth counts best new-edges new-blocked new-roots
                   new-mapping new-seeds)
                  (check-result-against-model
                   fifth counts best '() new-blocked new-roots
                   new-mapping new-seeds))))))))))
