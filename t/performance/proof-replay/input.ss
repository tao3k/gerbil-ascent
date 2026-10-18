;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil-ascent/candidate/reasoning reasoning-source-snapshot)
        (only-in :gerbil-ascent/candidate/types make-reasoning-candidate))
(export proof-input)
(def (proof-input width rule-count)
  (let* ((rows (map list (iota width)))
         (input (reasoning-source-snapshot 'source 0 (list (list 'edge 1 rows))))
         (program (make-reasoning-candidate '((out . 1)) []
                    (map (lambda (i) (vector '(out ?x) '((edge ?x)) (+ i 1))) (iota rule-count))
                    (vector (if (zero? rule-count) '(edge ?x) '(out ?x)) 0) '(64 4096 4096))))
    (values input program rows)))
