;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/table/trrel-uf :gerbil-ascent/core/relation-view
        (prefix-in :gerbil-ascent/t/performance/uf-frontier/reference-trrel-uf old-))
(export ui-prepare ui-consume ui-expected frontier-input)
(def (chain start count) (map (lambda (i) (list i (+ i 1))) (iota count start)))
(def (frontier-input scenario)
  (case scenario
    ((scalar weighted heavy)
      (append (chain 0 256) (chain 257 256)
        (case scenario ((weighted) '((449 321))) ((heavy) '((192 64) (449 321))) (else []))
        '((256 257))))
    ((partial) (append (chain 0 512) '((448 64))))
    ((sparse) (map (lambda (i) (list 0 i)) (iota 600 1)))
    ((small) '((0 1) (2 3) (1 2) (3 0)))
    ((chain) (chain 0 512))))
(def (ui-prepare old? scenario) #f)
(def (ui-consume ignored scenario old?)
  (let ((state ((if old? old-gerbil-ascent-trrel-uf-state gerbil-ascent-trrel-uf-state))) (count 0))
    (for-each (lambda (row)
      (let (scalar? (and (memq scenario '(scalar heavy)) (equal? row '(256 257))))
        (set! count (+ count
          (if scalar?
            (let (view ((if old? old-gerbil-ascent-trrel-uf-insert! gerbil-ascent-trrel-uf-insert!) state row 2000000))
              (relation-view-count view))
            ((if old? old-gerbil-ascent-trrel-uf-count-insert! gerbil-ascent-trrel-uf-count-insert!) state row 2000000))))))
      (frontier-input scenario))
    (list count (vector->list ((if old? old-gerbil-ascent-trrel-uf-observation gerbil-ascent-trrel-uf-observation) state)))))
;; Independent chain/SCC arithmetic for whole trajectories.
(def (ui-expected ignored scenario)
  (case scenario
    ((scalar) '(132355 (514 514 131841)))
    ((weighted) '(140611 (514 386 74305)))
    ((heavy) '(148867 (514 258 33153)))
    ((partial) '(205761 (513 129 8256)))
    ((sparse) '(1201 (601 601 600)))
    ((small) '(16 (4 1 0)))
    ((chain) '(131841 (513 513 131328)))))
