;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil-ascent/candidate/types make-reasoning-candidate)
        (only-in :gerbil-ascent/candidate/reasoning reasoning-source-snapshot))
(export absence-input)
;;; Identity rules admit exactly the input relation, independently of the
;;; certificate producer. Repeated body rows exercise late relation lookup.
(def (absence-input width rows rules (identity? #t))
  (let* ((names (map (lambda (i) (string->symbol (string-append "r" (number->string i)))) (iota width)))
         (tuples (map list (iota rows)))
         (relations (map (lambda (name) (list name 1 tuples)) names))
         (last (car (reverse names)))
         (program (make-reasoning-candidate [] []
           (map (lambda (i) (vector (list last '?x)
             (list (list (if identity? last (car names)) '?x) (list last '?y)) i)) (iota rules))
           (vector (list last -1) 0) '(64 4096 4096))))
    (values (reasoning-source-snapshot 'indexed 0 relations) program relations)))
