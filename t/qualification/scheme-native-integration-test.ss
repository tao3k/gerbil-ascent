;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :gerbil-ascent/program/interface
                 relational-fragment relational-finite-view
                 relational-lattice-fragment relational-compose
                 relational-export relational-open-session
                 relational-session-run relational-session-replace-source!
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
                         '((1 11) (2 11))) #t)))))))
