;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Test-only shortest-support output. MRR supplies source-label ranks in the
;;; same order as its canonical FactIds and compares the result with Ascent.

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/candidate/closure
                 gerbil-ascent-closure-candidates))

(export main)

(def (parse-node node width)
  (unless (and (exact-integer? node) (<= 0 node) (< node width))
    (error "invalid ASCENT fixture node" node))
  node)

(def (source-facts values width)
  (let loop ((remaining values) (facts []))
    (if (null? remaining)
      (reverse facts)
      (let ((from (parse-node (car remaining) width))
            (to (parse-node (cadr remaining) width))
            (label (caddr remaining)))
        (unless (and (exact-integer? label) (<= 0 label))
          (error "invalid ASCENT fixture source label" label))
        (loop (cdddr remaining)
              (cons (cons (+ (* from width) to) label) facts))))))

(def (main . args)
  (unless (null? args)
    (error "ASCENT support fixture reads one source list from stdin"))
  (let (request (read))
    (unless (and (list? request)
                 (>= (length request) 4)
                 (zero? (modulo (- (length request) 1) 3)))
      (error "ASCENT support fixture expects (RADIX FROM TO LABEL ...)"))
    (let (width (car request))
      (unless (and (exact-integer? width) (> width 1))
        (error "invalid ASCENT fixture radix"))
      (let (receipt
            (gerbil-ascent-closure-candidates
             (source-facts (cdr request) width) width 4096 4096 4096))
        (unless (eq? (.ref receipt 'status) 'complete)
          (error "ASCENT fixture closure is incomplete"))
        (for-each
         (lambda (candidate)
           (let (pair (.ref candidate 'pair))
             (display (quotient pair width))
             (display "\t")
             (display (modulo pair width))
             (display "\t")
             (display (.ref candidate 'distance))
             (display "\t")
             (display (.ref candidate 'rule))
             (for-each
              (lambda (label)
                (display "\t")
                (display label))
              (.ref candidate 'support))
             (newline)))
         (.ref receipt 'candidates))))))
