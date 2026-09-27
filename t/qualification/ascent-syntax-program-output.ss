;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-syntax-fixture
                 ascent-syntax-parity-evaluate
                 ascent-pattern-clauses-evaluate))

(export main)

(def (main . args)
  (unless (null? args)
    (error "ASCENT syntax fixture reads one edge snapshot from stdin"))
  (let* ((edges (read))
         (rows-of (.ref (ascent-syntax-parity-evaluate edges) 'rows-of))
         (pattern-rows-of
          (.ref (ascent-pattern-clauses-evaluate edges) 'rows-of)))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (display name)
          (for-each (lambda (column) (display #\tab) (display column)) row)
          (newline))
        (rows-of name)))
     '(seed marker selected successor unwrapped unwrapped-pattern))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (display name)
          (for-each (lambda (column) (display #\tab) (display column)) row)
          (newline))
        (pattern-rows-of name)))
     '(let-pair for-pair))
    (displayln "END")
    (force-output)))
