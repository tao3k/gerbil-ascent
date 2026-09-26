;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-mutual-program-fixture
                 ascent-mutual-evaluate))

(export main)

(def (main . _)
  (let* ((result (ascent-mutual-evaluate (read)))
         (rows-of (.ref result 'rows-of)))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (display name)
          (display #\tab)
          (display (car row))
          (display #\tab)
          (displayln (cadr row)))
        (rows-of name)))
     '(path0 path1))))
