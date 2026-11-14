;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/table/trrel-uf :gerbil-ascent/core/relation-view
 (prefix-in :gerbil-ascent/t/performance/uf-admission/reference old-))
(export ascent-uf-admission-test)
(def ascent-uf-admission-test
 (test-suite "UF closure admission and local reverse index retirement"
  (test-case "indexed partial merges retain unrelated arcs, snapshots and exact frontiers"
   (let ((a (old-gerbil-ascent-trrel-uf-state)) (b (gerbil-ascent-trrel-uf-state)))
    (for-each (lambda (edge)
      (let* ((held (gerbil-ascent-trrel-uf-freeze b)) (rows (gerbil-ascent-view-rows held))
             (frontier (old-gerbil-ascent-trrel-uf-extension a [] [] edge 100000))
             (before (gerbil-ascent-trrel-uf-observation b)))
        (check-exception (gerbil-ascent-trrel-uf-extension b [] [] edge (- (length frontier) 1)) (lambda (_) #t))
        (check-equal? (gerbil-ascent-trrel-uf-observation b) before)
        (check-equal? (gerbil-ascent-trrel-uf-extension b [] [] edge (length frontier)) frontier)
        (check-equal? (gerbil-ascent-trrel-uf-validate b) #t)
        (check-equal? (gerbil-ascent-view-rows held) rows)
        (check-equal? (gerbil-ascent-trrel-uf-extension b [] [] edge 0) [])
        (check-equal? (gerbil-ascent-trrel-uf-observation b) (old-gerbil-ascent-trrel-uf-observation a))))
      (append (map (lambda (n) (list n (+ n 1))) (iota 72))
              '((100 101) (101 102) (102 103) (104 100) (103 105)
                (102 101) (103 100) (105 104) (72 0))))))
  (test-case "existing reflexive and transitive facts reject negative budgets"
   (let (state (gerbil-ascent-trrel-uf-state))
    (for-each (lambda (edge) (gerbil-ascent-trrel-uf-insert! state edge 20)) '((#f a) (a b)))
    (for-each (lambda (edge)
      (check-equal? (gerbil-ascent-trrel-uf-extension state [] [] edge 0) [])
      (check-exception (gerbil-ascent-trrel-uf-insert! state edge -1) (lambda (_) #t))
      (check-equal? (gerbil-ascent-trrel-uf-validate state) #t)) '((#f #f) (#f b) (a b)))))))
