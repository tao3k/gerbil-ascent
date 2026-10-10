;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil-ascent/candidate/types make-reasoning-candidate)
        (only-in :gerbil-ascent/candidate/reasoning reasoning-source-snapshot)
        (only-in :gerbil-ascent/candidate/provenance-graph candidate-positive-provenance
                 positive-provenance-witness positive-provenance-alternatives candidate-verify-positive-provenance positive-provenance-status)
        :gerbil-ascent/candidate/provenance-maintenance
        (prefix-in :gerbil-ascent/t/performance/support-height/reference old-))
(export height-prepare height-consume height-verify!)
(def (height-prepare old? scenario)
  (let* ((count (if (eq? scenario 'small) 1 32))
         (snapshot (reasoning-source-snapshot 'height-worklist 0
                     (list (list 's 1 '((0) (0)))
                           (list 'next 2 (map (lambda (i) (list i (+ i 1))) (iota count))))))
         (rows (map list (iota (+ count 1))))
         (spec (make-reasoning-candidate '((p . 1)) []
                 (list (vector '(p ?x) '((s ?x)) 10)
                       (vector '(p ?y) '((p ?x) (next ?x ?y)) 11))
                 (vector '(p ?x) 12) '(4096 4096 8192)))
         (graph (candidate-positive-provenance snapshot spec 'program 'complete rows 100000 4096))
         ;; Edge order is not proof authority. Reverse the already verified
         ;; support to exercise dependencies pointing against scan order.
         (state ((if old? old-candidate-make-provenance-maintenance candidate-make-provenance-maintenance)
                 (positive-provenance-witness graph) (reverse (positive-provenance-alternatives graph)))))
    (unless (and (eq? (positive-provenance-status graph) 'complete)
                 (candidate-verify-positive-provenance snapshot spec 'program 'complete rows graph 100000 4096))
      (error "height fixture requires a complete verified support graph"))
    (when (eq? scenario 'withdrawn)
      ((if old? old-candidate-provenance-withdraw! candidate-provenance-withdraw!) state '((s 1))))
    (list old? state (map (lambda (i) (list (list i) (+ i 1))) (iota (+ count 1))))))
(def (height-consume prepared scenario)
  (with ([old? state expected] prepared)
    (let-values (((first _) ((if old? old-candidate-provenance-heights candidate-provenance-heights) state)))
      (let-values (((compact _) ((if old? old-candidate-provenance-compact candidate-provenance-compact) state)))
        (let-values (((next _) ((if old? old-candidate-provenance-heights candidate-provenance-heights) compact)))
          (list first next ((if old? old-provenance-maintenance-rows provenance-maintenance-rows) compact)))))))
(def (height-verify! prepared)
  (with ([_ _ expected] prepared)
    (unless (equal? (height-consume prepared 'check) (list expected expected (map car expected)))
      (error "independent support height truth differs"))))
