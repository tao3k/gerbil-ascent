;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-evaluate-program))

(export main)

(def edge-candidates '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)))

(def (mask-edges mask)
  (filter-map
   (lambda (indexed)
     (and (odd? (quotient mask (expt 2 (car indexed))))
          (cdr indexed)))
   (map cons (iota 6) edge-candidates)))

(def (scc-program edges variant)
  (if (= variant 0)
    (ascent
     (relation edge (from to) edges)
     (relation a (from to))
     (relation b (from to))
     (relation c (from to))
     ((b x z) <-- (a x y) (edge y z))
     (((c x z) (a x z)) <-- (b x y) (edge y z))
     ((b x y) <-- (c x y))
     ((a x y) <-- (edge x y))
     (bounds 6 200 200))
    (ascent
     (relation edge (from to) edges)
     (relation a (from to))
     (relation b (from to))
     (relation c (from to))
     ((a x y) <-- (edge x y))
     ((b x y) <-- (c x y))
     (((c x z) (a x z)) <-- (edge y z) (b x y))
     ((b x z) <-- (edge y z) (a x y))
     (bounds 6 200 200))))

(def (print-case mask variant)
  (let* ((result (gerbil-ascent-evaluate-program
                  (scc-program (mask-edges mask) variant)))
         (rows-of (.ref result 'rows-of)))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (display mask) (display #\tab)
          (display variant) (display #\tab)
          (display name)
          (for-each (lambda (column) (display #\tab) (display column)) row)
          (newline))
        (rows-of name)))
     '(a b c))))

(def (main . args)
  (unless (null? args)
    (error "ASCENT SCC order corpus reads graph masks from stdin"))
  (for-each
   (lambda (mask)
     (unless (and (exact-integer? mask) (<= 0 mask) (< mask 64))
       (error "invalid ASCENT SCC graph mask" mask))
     (print-case mask 0)
     (print-case mask 1))
   (read))
  (display "END\n")
  (force-output))
