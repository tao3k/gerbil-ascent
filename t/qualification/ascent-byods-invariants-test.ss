;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite)
        (only-in :std/hash/misc hash-ensure-modify!)
        (only-in :clan/poo/object .ref)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :gerbil-ascent/t/qualification/ascent-byods-query-fixture
                 ascent-byods-query-evaluate)
        (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-eqrel-storage-provider
                 gerbil-ascent-trrel-storage-provider
                 gerbil-ascent-trrel-uf-storage-provider
                 gerbil-ascent-storage-make-state
                 gerbil-ascent-storage-extend))

(export ascent-byods-invariants-test)

(def +possible-edges+
  '((0 0) (0 1) (0 2)
    (1 0) (1 1) (1 2)
    (2 0) (2 1) (2 2)))

(def +four-node-edges+
  '((0 0) (0 1) (0 2) (1 2)
    (2 1) (2 3) (3 0) (3 3)))

(def +eight-node-edges+
  '((0 1) (1 2) (2 3) (3 4)
    (4 5) (5 6) (6 7) (7 0)
    (0 4) (2 6) (4 0) (6 2)))

(def (eight-node-subset mask)
  (let loop ((remaining +eight-node-edges+) (bit 1) (selected []))
    (if (null? remaining)
      (reverse selected)
      (loop (cdr remaining) (* bit 2)
            (if (odd? (quotient mask bit))
              (cons (car remaining) selected)
              selected)))))

(def (subsets items)
  (if (null? items)
    (list [])
    (let (tail (subsets (cdr items)))
      (append tail
              (map (lambda (subset) (cons (car items) subset)) tail)))))

(def (adjacency edges symmetric?)
  (let (index (make-hash-table))
    (def (add! from to)
      (hash-ensure-modify! index from
                           (lambda () [])
                           (lambda (neighbors) (cons to neighbors))))
    (for-each
     (lambda (edge)
       (add! (car edge) (cadr edge))
       (when symmetric? (add! (cadr edge) (car edge))))
     edges)
    index))

(def (reachable index root)
  (let ((seen (make-hash-table))
        (todo (list root)))
    (let loop ()
      (unless (null? todo)
        (let (node (car todo))
          (set! todo (cdr todo))
          (unless (hash-get seen node)
            (hash-put! seen node #t)
            (set! todo (append (or (hash-get index node) []) todo))))
        (loop)))
    seen))

(def (reference-rows kind edges)
  (let* ((node-set (make-hash-table))
         (nodes [])
         (index (adjacency edges (eq? kind 'eqrel)))
         (wanted []))
    (for-each
     (lambda (edge)
       (for-each
        (lambda (node)
          (unless (hash-get node-set node)
            (hash-put! node-set node #t)
            (set! nodes (cons node nodes))))
        edge))
     edges)
    (for-each
     (lambda (from)
       (let (seen (reachable index from))
         (for-each
          (lambda (to)
            (when (and (hash-get seen to)
                       (or (not (eq? kind 'trrel))
                           (not (= from to))
                           (member (list from from) edges)))
              (set! wanted (cons (list from to) wanted))))
          nodes)))
     nodes)
    wanted))

(def (provider-rows provider edges (budget 9))
  (let ((state (gerbil-ascent-storage-make-state provider))
        (rows []))
    (for-each
     (lambda (edge)
       (set! rows
         (append (gerbil-ascent-storage-extend
                  provider state rows [] edge budget)
                 rows))
       (check-equal?
        (gerbil-ascent-storage-extend provider state rows [] edge 0)
        []))
     edges)
    rows))

(def (grouped-rows group edges)
  (map (lambda (edge) (cons group edge)) edges))

(def (check-provider-rows provider ordered wanted (budget 9))
  (let (actual (provider-rows provider ordered budget))
    (check-equal? (length actual) (length wanted))
    (for-each
     (lambda (row)
       (check-equal? (not (not (member row actual))) #t))
     wanted)))

(def ascent-byods-invariants-test
  (test-suite "ASCENT BYODS exhaustive three-node invariants"
    (poo-flow-test-case "eqrel preflight preserves state and deterministic emission order"
      (let (state (gerbil-ascent-storage-make-state
                   gerbil-ascent-eqrel-storage-provider))
        (def (extend row budget)
          (gerbil-ascent-storage-extend
           gerbil-ascent-eqrel-storage-provider state [] [] row budget))
        (check-exception (extend '(1 2) 3) true)
        (check-equal? (hash-length state) 0)
        (check-equal? (extend '(1 2) 4)
                      '((1 1) (2 2) (1 2) (2 1)))
        (check-exception (extend '(2 3) 4) true)
        (check-equal? (hash-length state) 2)
        (check-equal? (extend '(2 1) 0) [])
        (check-equal? (extend '(1 1) 0) [])
        (check-exception (extend '(1 2) -1) true)
        (check-equal? (extend '(2 3) 5)
                      '((3 3) (2 3) (3 2) (1 3) (3 1)))
        (check-exception (extend '("other" 1 1) 0) true)
        (check-equal? (hash-length state) 3)
        (check-equal? (extend '("other" 1 1) 1) '(("other" 1 1)))
        (check-equal? (extend '("other" 1 1) 0) [])
        (check-equal? (extend (list (list 4) (list 4)) 1)
                      '(((4) (4))))
        (check-equal? (extend (list (list 4) (list 4)) 0) [])))
    (poo-flow-test-case "all directed edge subsets preserve closure and insertion order independence"
      (for-each
       (lambda (edges)
         (for-each
          (lambda (kind provider)
            (let (wanted (reference-rows kind edges))
              (for-each
               (lambda (ordered)
                 (check-provider-rows provider ordered wanted))
               (list edges (reverse edges)))))
          '(eqrel trrel trrel-uf)
          (list gerbil-ascent-eqrel-storage-provider
                gerbil-ascent-trrel-storage-provider
                gerbil-ascent-trrel-uf-storage-provider)))
       (subsets +possible-edges+)))
    (poo-flow-test-case "four-node sparse subsets preserve larger merges"
      (for-each
       (lambda (edges)
         (for-each
          (lambda (kind provider)
            (let (wanted (reference-rows kind edges))
              (for-each
               (lambda (ordered)
                 (check-provider-rows provider ordered wanted 16))
               (list edges (reverse edges)))))
          '(eqrel trrel trrel-uf)
          (list gerbil-ascent-eqrel-storage-provider
                gerbil-ascent-trrel-storage-provider
                gerbil-ascent-trrel-uf-storage-provider)))
       (subsets +four-node-edges+)))
    (poo-flow-test-case "eight-node cycles and bridges preserve closure"
      (for-each
       (lambda (mask)
         (let (edges (eight-node-subset mask))
           (for-each
            (lambda (kind provider)
              (let (wanted (reference-rows kind edges))
                (for-each
                 (lambda (ordered)
                   (check-provider-rows provider ordered wanted 64))
                 (list edges (reverse edges)))))
            '(eqrel trrel trrel-uf)
            (list gerbil-ascent-eqrel-storage-provider
                  gerbil-ascent-trrel-storage-provider
                  gerbil-ascent-trrel-uf-storage-provider))))
       (append (map (lambda (sample) (modulo (* sample 263) 4096))
                    (iota 256))
               '(1 1365 3855 4095))))
    (poo-flow-test-case "four-node edges close across every two-producer partition"
      (let* ((edges +four-node-edges+)
             (wanted (map (lambda (node) (list "alpha" node)) '(0 1 2 3)))
             (expected
              (map (lambda (kind)
                     (grouped-rows "alpha" (reference-rows kind edges)))
                   '(eqrel trrel trrel-uf))))
        (for-each
         (lambda (first)
           (let* ((second
                   (filter (lambda (edge) (not (member edge first))) edges))
                  (result
                   (ascent-byods-query-evaluate
                    (grouped-rows "alpha" first) wanted
                    (grouped-rows "alpha" second)))
                  (rows-of (.ref result 'rows-of)))
             (for-each
              (lambda (name rows)
                (let (actual (rows-of name))
                  (check-equal? (length actual) (length rows))
                  (for-each
                   (lambda (row)
                     (check-equal? (not (not (member row actual))) #t))
                   rows)))
              '(eq-match tr-match uf-match) expected)))
         (subsets edges))))
    (poo-flow-test-case "eight-node producer partitions retain complete joins"
      (let* ((edges +eight-node-edges+)
             (wanted '(("alpha" 0)))
             (expected
              (map (lambda (kind)
                     (grouped-rows
                      "alpha"
                      (filter (lambda (row) (= (cadr row) 0))
                              (reference-rows kind edges))))
                   '(eqrel trrel trrel-uf))))
        (for-each
         (lambda (mask)
           (let* ((first (eight-node-subset mask))
                  (second
                   (filter (lambda (edge) (not (member edge first)))
                           edges))
                  (result
                   (ascent-byods-query-evaluate
                    (grouped-rows "alpha" first) wanted
                    (grouped-rows "alpha" second)))
                  (rows-of (.ref result 'rows-of)))
             (for-each
              (lambda (name rows)
                (let (actual (rows-of name))
                  (unless (= (length actual) (length rows))
                    (error "ASCENT eight-node partition mismatch"
                           mask name (length actual) (length rows)))
                  (for-each
                   (lambda (row)
                     (check-equal? (not (not (member row actual))) #t))
                   rows)))
              '(eq-match tr-match uf-match) expected)))
         (append (map (lambda (sample) (modulo (* sample 263) 4096))
                      (iota 256))
                 '(1 1365 3855 4095)))))
    (poo-flow-test-case "grouped storage isolates two interleaved edge sets"
      (let (beta '((0 1) (1 2) (2 0)))
        (for-each
         (lambda (alpha)
           (for-each
            (lambda (kind provider)
              (let* ((alpha-edges (grouped-rows 'alpha alpha))
                     (beta-edges (grouped-rows 'beta beta))
                     (wanted (append
                              (grouped-rows 'alpha
                                            (reference-rows kind alpha))
                              (grouped-rows 'beta
                                            (reference-rows kind beta)))))
                (check-provider-rows provider
                                     (append alpha-edges beta-edges)
                                     wanted)
                (check-provider-rows provider
                                     (append beta-edges (reverse alpha-edges))
                                     wanted)))
            '(eqrel trrel trrel-uf)
            (list gerbil-ascent-eqrel-storage-provider
                  gerbil-ascent-trrel-storage-provider
                  gerbil-ascent-trrel-uf-storage-provider)))
         (subsets +possible-edges+))))))
