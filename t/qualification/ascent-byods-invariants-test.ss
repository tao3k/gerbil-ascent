;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite test-case)
        (only-in :std/hash/misc hash-ensure-modify!)
        (only-in :gerbil-ascent/table/trrel-uf gerbil-ascent-trrel-uf-observation)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable gerbil-ascent-atom
                 gerbil-ascent-rule gerbil-ascent-program gerbil-ascent-open-session
                 gerbil-ascent-session-run gerbil-ascent-session-append-source!)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
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

(def (check-frontier-trace kind provider ordered (group #f))
  (let ((state (gerbil-ascent-storage-make-state provider))
        (generous (gerbil-ascent-storage-make-state provider))
        (inputs []) (seen []))
    (for-each
     (lambda (edge)
       (set! inputs (cons edge inputs))
       (let* ((concrete (reference-rows kind inputs))
              (wanted (if group (grouped-rows group concrete) concrete))
              (fresh (filter (lambda (row) (not (member row seen))) wanted))
              (row (if group (cons group edge) edge))
              (needed (length fresh))
              (before (and (eq? kind 'trrel-uf)
                           (gerbil-ascent-trrel-uf-observation state))))
         (when (> needed 0)
           (check-exception
            (gerbil-ascent-storage-extend provider state seen [] row (- needed 1)) true)
           (when before
             (check-equal? (gerbil-ascent-trrel-uf-observation state) before)))
         (let ((emitted (gerbil-ascent-storage-extend provider state seen [] row needed))
               (loose (gerbil-ascent-storage-extend provider generous seen [] row 16)))
           (check-equal? (length emitted) needed)
           (check-equal? (length loose) needed)
           (for-each
            (lambda (fact)
              (check-equal? (not (not (member fact emitted))) #t)
              (check-equal? (not (not (member fact loose))) #t)) fresh)
           (check-equal? (gerbil-ascent-storage-extend provider state seen [] row 0) [])
           (set! seen (append emitted seen))))) ordered)))

;;; Repeated Provider reads share variables; a relay delays the second producer
;;; to a later frontier. Expected heads come from independent graph closure,
;;; then explicit three-edge witness enumeration, not another evaluator.
(def (three-body-program provider first second)
  (let ((x (gerbil-ascent-variable 'x)) (b (gerbil-ascent-variable 'b))
        (c (gerbil-ascent-variable 'c)) (z (gerbil-ascent-variable 'z)))
    (gerbil-ascent-program
     (list (gerbil-ascent-relation 'first 2 first)
           (gerbil-ascent-relation 'second 2 second)
           (gerbil-ascent-relation 'relay 2 [])
           (gerbil-ascent-relation 'closed 2 [] gerbil-ascent-hash-index-provider provider)
           (gerbil-ascent-relation 'answer 2 []))
     (list
      (gerbil-ascent-rule (list (gerbil-ascent-atom 'relay (list x z)))
                         (list (gerbil-ascent-atom 'second (list x z))))
      (gerbil-ascent-rule (list (gerbil-ascent-atom 'closed (list x z)))
                         (list (gerbil-ascent-atom 'first (list x z))))
      (gerbil-ascent-rule (list (gerbil-ascent-atom 'closed (list x z)))
                         (list (gerbil-ascent-atom 'relay (list x z))))
      (gerbil-ascent-rule (list (gerbil-ascent-atom 'answer (list x z)))
                         (list (gerbil-ascent-atom 'closed (list x b))
                               (gerbil-ascent-atom 'closed (list b c))
                               (gerbil-ascent-atom 'closed (list c z)))))
     64 256 512)))

(def (three-body-rows closed)
  (filter
   (lambda (pair)
     (ormap (lambda (b)
              (and (member (list (car pair) b) closed)
                   (ormap (lambda (c)
                            (and (member (list b c) closed)
                                 (member (list c (cadr pair)) closed)))
                          '(0 1 2))))
            '(0 1 2)))
   +possible-edges+))

(def ascent-byods-invariants-test
  (test-suite "ASCENT BYODS exhaustive three-node invariants"
    (test-case "retained head injection survives an empty implied frontier"
      (for-each
       (lambda (kind provider)
         (let* ((first '((0 1) (1 0)))
                (next (append first '((1 2))))
                (session (gerbil-ascent-open-session (three-body-program provider first [])))
                (initial (gerbil-ascent-session-run session))
                (initial-rows ((.ref initial 'rows-of) 'answer)))
           (def (check-answer result edges)
             (let ((wanted (three-body-rows (reference-rows kind edges)))
                   (actual ((.ref result 'rows-of) 'answer)))
               (check-equal? (.ref result 'finished) #t)
               (check-equal? (length actual) (length wanted))
               (for-each (lambda (row)
                           (check-equal? (not (not (member row actual))) #t)) wanted)))
           (check-answer initial first)
           (gerbil-ascent-session-append-source! session 'second '(1 2))
           (check-answer (gerbil-ascent-session-run session) next)
           ;; This new source tuple is already implied by the custom domain.
           ;; Its empty concrete frontier must not replace accumulated heads.
           (gerbil-ascent-session-append-source! session 'second '(0 2))
           (check-answer (gerbil-ascent-session-run session) (append next '((0 2))))
           (check-answer (gerbil-ascent-session-run session) next)
           (check-equal? ((.ref initial 'rows-of) 'answer) initial-rows)
           (displayln "BYODS-RETAINED-INJECTION-OK provider=" kind)
           (force-output)))
       '(eqrel trrel trrel-uf)
       (list gerbil-ascent-eqrel-storage-provider
             gerbil-ascent-trrel-storage-provider
             gerbil-ascent-trrel-uf-storage-provider)))
    (test-case "three repeated Provider atoms consume delayed frontiers exactly"
      (let (checked 0)
       (for-each
       (lambda (edges)
         (for-each
          (lambda (first)
            (let (second (filter (lambda (edge) (not (member edge first))) edges))
              (for-each
               (lambda (kind provider)
                 (let* ((closed (reference-rows kind edges))
                        (wanted (three-body-rows closed))
                        (result (gerbil-ascent-evaluate-program
                                 (three-body-program provider first second)))
                        (actual ((.ref result 'rows-of) 'answer)))
                   (check-equal? (.ref result 'finished) #t)
                   (check-equal? (length actual) (length wanted))
                   (for-each (lambda (row)
                               (check-equal? (not (not (member row actual))) #t)) wanted)))
               '(eqrel trrel trrel-uf)
               (list gerbil-ascent-eqrel-storage-provider
                     gerbil-ascent-trrel-storage-provider
                     gerbil-ascent-trrel-uf-storage-provider))
              ;; Emit only after all three independently checked provider
              ;; results complete for this actual producer partition.
              (set! checked (+ checked 1))
              (displayln "BYODS-THREE-BODY-CHECKED partition=" checked
                         " edges=" edges " first=" first)
              (force-output)))
          (subsets edges)))
       (subsets '((0 1) (1 2) (2 0))))))
    (test-case "union-find false nodes and false groups have distinct identities"
      (let ((state (gerbil-ascent-storage-make-state gerbil-ascent-trrel-uf-storage-provider)))
        (def (extend edge budget)
          (gerbil-ascent-storage-extend gerbil-ascent-trrel-uf-storage-provider state [] [] edge budget))
        (check-equal? (length (extend '(#f #t) 3)) 3)
        (check-equal? (length (extend '(#f #f #t) 3)) 3)
        (check-equal? (extend '(#f #t #f) 1) '((#f #t #f)))
        (check-equal? (extend '(#t #f) 1) '((#t #f)))
        (check-equal? (gerbil-ascent-trrel-uf-observation state) '#(4 2 0))))
    (test-case "union-find compresses a cycle without retaining concrete pairs"
      (let ((state (gerbil-ascent-storage-make-state gerbil-ascent-trrel-uf-storage-provider)) (rows []))
        (for-each (lambda (n)
          (set! rows (append (gerbil-ascent-storage-extend gerbil-ascent-trrel-uf-storage-provider
                              state rows [] (list n (modulo (+ n 1) 64)) 4096) rows))) (iota 64))
        (check-equal? (length rows) 4096)
        (check-equal? (gerbil-ascent-trrel-uf-observation state) '#(64 1 0))
        (for-each (lambda (n)
          (check-equal? (gerbil-ascent-storage-extend gerbil-ascent-trrel-uf-storage-provider
                          state rows [] (list n (modulo (+ n 1) 64)) 0) [])) (iota 64))
        (check-equal? (gerbil-ascent-trrel-uf-observation state) '#(64 1 0))))
    (test-case "union-find budget refusal preserves SCC state and exact retry frontier"
      (let ((state (gerbil-ascent-storage-make-state gerbil-ascent-trrel-uf-storage-provider)) (rows []))
        (def (extend edge budget)
          (gerbil-ascent-storage-extend gerbil-ascent-trrel-uf-storage-provider state rows [] edge budget))
        (check-exception (extend '(0 1) 2) true)
        (check-equal? (gerbil-ascent-trrel-uf-observation state) '#(0 0 0))
        (set! rows (append (extend '(0 1) 3) rows))
        (set! rows (append (extend '(1 2) 3) rows))
        (check-equal? (gerbil-ascent-trrel-uf-observation state) '#(3 3 3))
        (check-exception (extend '(2 0) 2) true)
        (check-equal? (gerbil-ascent-trrel-uf-observation state) '#(3 3 3))
        (set! rows (append (extend '(2 0) 3) rows))
        (check-equal? (length rows) 9)
        (check-equal? (gerbil-ascent-trrel-uf-observation state) '#(3 1 0))
        (check-exception (extend '(3 0) 3) true)
        (check-equal? (gerbil-ascent-trrel-uf-observation state) '#(3 1 0))
        (set! rows (append (extend '(3 0) 4) rows))
        (check-equal? (length rows) 13)
        (check-equal? (gerbil-ascent-trrel-uf-observation state) '#(4 2 1))))
    (test-case "each provider frontier equals the independent new concrete facts"
      (let (checked 0)
        (for-each
         (lambda (edges)
           (for-each
            (lambda (kind provider)
              (check-frontier-trace kind provider edges)
              (check-frontier-trace kind provider (reverse edges))
              (unless (eq? kind 'eqrel)
                (check-frontier-trace kind provider edges "alpha")
                (check-frontier-trace kind provider (reverse edges) "alpha")))
            '(eqrel trrel trrel-uf)
            (list gerbil-ascent-eqrel-storage-provider
                  gerbil-ascent-trrel-storage-provider
                  gerbil-ascent-trrel-uf-storage-provider))
           (set! checked (+ checked 1))
           (when (zero? (modulo checked 64))
             (displayln "PROGRESS independent BYODS frontier graphs " checked "/512")
             (force-output)))
         (subsets +possible-edges+))))
    (test-case "directed frontier bridge merges non-singleton SCCs and preserves explicit loops"
      (for-each
       (lambda (kind provider)
         (check-frontier-trace kind provider
           '((0 1) (1 0) (2 3) (3 2) (1 2) (3 0) (0 0)))
         (check-frontier-trace kind provider
           '((3 2) (2 3) (1 0) (0 1) (2 1) (0 3) (3 3)) "alpha"))
       '(trrel trrel-uf)
       (list gerbil-ascent-trrel-storage-provider gerbil-ascent-trrel-uf-storage-provider)))
    (test-case "eqrel preflight preserves state and deterministic emission order"
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
    (test-case "all directed edge subsets preserve closure and insertion order independence"
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
    (test-case "four-node sparse subsets preserve larger merges"
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
    (test-case "eight-node cycles and bridges preserve closure"
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
    (test-case "four-node edges close across every two-producer partition"
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
    (test-case "eight-node producer partitions retain complete joins"
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
    (test-case "grouped storage isolates two interleaved edge sets"
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
