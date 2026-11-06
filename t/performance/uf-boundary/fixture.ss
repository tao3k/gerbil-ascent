;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/table/trrel-uf :gerbil-ascent/core/relation-view
        (prefix-in :gerbil-ascent/t/performance/uf-boundary/reference-trrel-uf old-))
(export ui-prepare ui-consume ui-expected boundary-input)
(def (chain start count) (map (lambda (i) (list i (+ i 1))) (iota count start)))
(def (boundary-input scenario)
  (case scenario
    ((bridge) (append (chain 0 256) (chain 257 256) '((256 257))))
    ((overlap) (append (chain 0 384) '((320 128) (384 64))))
    ((partial) (append (chain 0 512) '((448 64))))
    ((complete) (append (chain 0 512) '((512 0))))
    ((weighted) (append (chain 0 256) '((96 32) (224 128) (256 0))))
    ((sparse) (map (lambda (i) (list 0 i)) (iota 600 1)))
    ((small) '((0 1) (2 3) (1 2) (3 0)))
    ((chain) (chain 0 512))))
(def (ui-prepare old? scenario) #f)
(def (ui-consume ignored scenario old?)
  (let ((state ((if old? old-gerbil-ascent-trrel-uf-state gerbil-ascent-trrel-uf-state))) (count 0))
    (for-each (lambda (row)
      (set! count (+ count ((if old? old-gerbil-ascent-trrel-uf-count-insert! gerbil-ascent-trrel-uf-count-insert!)
                           state row 2000000)))) (boundary-input scenario))
    (list count (vector->list ((if old? old-gerbil-ascent-trrel-uf-observation gerbil-ascent-trrel-uf-observation) state)))))
;; Independent arithmetic for complete fixtures, not baseline-generated truth.
(def (ui-expected ignored scenario)
  (case scenario
    ((bridge) '(132355 (514 514 131841)))
    ((chain) '(131841 (513 513 131328)))
    ((complete) '(263169 (513 1 0)))
    ((partial) '(205761 (513 129 8256)))
    ((overlap) '(125665 (385 65 2080)))
    ((weighted) '(66049 (257 1 0)))
    ((sparse) '(1201 (601 601 600)))
    ((small) '(16 (4 1 0)))))
