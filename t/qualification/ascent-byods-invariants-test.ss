;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite)
        (only-in :std/hash/misc hash-ensure-modify!)
        (only-in :core/observability/testing-case poo-flow-test-case)
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

(def (provider-rows provider edges)
  (let ((state (gerbil-ascent-storage-make-state provider))
        (rows []))
    (for-each
     (lambda (edge)
       (set! rows
         (append (gerbil-ascent-storage-extend
                  provider state rows [] edge 9)
                 rows))
       (check-equal?
        (gerbil-ascent-storage-extend provider state rows [] edge 0)
        []))
     edges)
    rows))

(def (grouped-rows group edges)
  (map (lambda (edge) (cons group edge)) edges))

(def (check-provider-rows provider ordered wanted)
  (let (actual (provider-rows provider ordered))
    (check-equal? (length actual) (length wanted))
    (for-each
     (lambda (row)
       (check-equal? (not (not (member row actual))) #t))
     wanted)))

(def ascent-byods-invariants-test
  (test-suite "ASCENT BYODS exhaustive three-node invariants"
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
