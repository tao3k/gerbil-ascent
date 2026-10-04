;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-lattice-negation-fixture
                 ascent-lattice-negation-program)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-replace-source!
                 gerbil-ascent-session-run))

(export main)

(def (emit index phase result)
  (let (rows-of (.ref result 'rows-of))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (display index) (display #\tab)
          (display phase) (display #\tab)
          (display name)
          (for-each
           (lambda (column) (display #\tab) (display column))
           row)
          (newline))
        (rows-of name)))
     '(score cheap not-cheap))))

(def (emit-case index edges added)
  (let* ((session (gerbil-ascent-open-session
                   (ascent-lattice-negation-program edges)))
         (first (gerbil-ascent-session-run session))
         (rows-of (.ref first 'rows-of))
         (names '(score cheap not-cheap))
         (snapshot (map rows-of names)))
    (emit index 0 first)
    (for-each
     (lambda (row)
       (gerbil-ascent-session-append-source! session 'edge row))
     added)
    (emit index 1 (gerbil-ascent-session-run session))
    (gerbil-ascent-session-replace-source! session 'edge edges)
    (emit index 2 (gerbil-ascent-session-run session))
    (unless (equal? snapshot (map rows-of names))
      (error "ASCENT lattice-negation changed an earlier snapshot" index))))

(def (main . args)
  (unless (null? args)
    (error "ASCENT lattice-negation corpus reads cases from stdin"))
  (let (cases (read))
    (for-each
     (lambda (index case)
       (emit-case index (car case) (cadr case)))
     (iota (length cases)) cases))
  (display "END\n")
  (force-output))
