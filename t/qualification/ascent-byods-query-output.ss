;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-byods-query-fixture
                 ascent-byods-query-evaluate))

(export main)

(def (main . _)
  (let* ((request (read))
         (rows-of (.ref (ascent-byods-query-evaluate
                         (car request) (cadr request))
                        'rows-of)))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (display name)
          (for-each
           (lambda (column) (display #\tab) (display column))
           row)
          (newline))
        (rows-of name)))
     '(eq-match tr-match uf-match))
    (display "END\n")))
