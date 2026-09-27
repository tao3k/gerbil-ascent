;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-rule-program-fixture
                 ascent-rule-fixture-evaluate))

(export main)

(def (main . _)
  (let (rows-of
        (.ref (ascent-rule-fixture-evaluate (read)) 'rows-of))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (display name)
          (for-each (lambda (column) (display #\tab) (display column)) row)
          (newline))
        (rows-of name)))
     '(labelled cycle hot selected choice generated dependent successor
       blocked allowed denied safe-reach reach))
    (display "END\n")))
