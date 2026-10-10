;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/runtime/gambit :gerbil-ascent/program/objects
        :gerbil-ascent/table/provider :gerbil-ascent/table/storage)
(export ordered cycle-program)
(def (ordered rows)
  (list-sort (lambda (a b) (or (< (car a) (car b))
                             (and (= (car a) (car b)) (< (cadr a) (cadr b))))) rows))
(def (cycle-program n (cycle? #t) (output-limit (* n n 3)))
  (let* ((y (gerbil-ascent-variable 'y))
         (edges (map (lambda (i) (list i (modulo (+ i 1) n))) (iota (if cycle? n (- n 1))))))
    (gerbil-ascent-program
      (list (gerbil-ascent-relation 'reach 2 edges gerbil-ascent-hash-index-provider
                                  gerbil-ascent-trrel-uf-storage-provider)
            (gerbil-ascent-relation 'out 1 []))
      (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'out (list y)))
                               (list (gerbil-ascent-atom 'reach (list (gerbil-ascent-literal 0) y)))))
      (* n 4) (* n n 2) output-limit)))
