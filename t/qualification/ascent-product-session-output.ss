;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Two-phase coordinatewise product lattice corpus. Rust 0.8.0's public
;;; Product lacks the Hash needed by its lattice storage; the oracle uses an
;;; equivalent newtype and the fixed-point model adjudicates direct sources.
(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-run))

(export main product-program source-score)

(def (coordinate-pair? value)
  (and (vector? value)
       (= (vector-length value) 2)
       (integer? (vector-ref value 0))
       (integer? (vector-ref value 1))))

(def (coordinate-join left right)
  (vector (max (vector-ref left 0) (vector-ref right 0))
          (max (vector-ref left 1) (vector-ref right 1))))

(def (source-score row)
  (match row
    ([node first second]
     (list node (vector first second)))))

(def (product-program scores improvements)
  (ascent
   (lattice score ((node integer?) (value coordinate-pair?))
            (map source-score scores) coordinate-join)
   (relation improve ((node integer?) (first integer?) (second integer?))
             improvements)
   (lattice copy ((node integer?) (value coordinate-pair?))
            [] coordinate-join)
   ((score node (expr (first second) (vector first second))) <--
    (improve node first second))
   ((copy node value) <-- (score node value))
   (bounds 32 64 96)))

(def (emit-result index phase result)
  (let (rows-of (.ref result 'rows-of))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (display index) (display #\tab) (display phase)
          (display #\tab) (display name)
          (display #\tab) (display (car row))
          (display #\tab) (display (vector-ref (cadr row) 0))
          (display #\tab) (display (vector-ref (cadr row) 1))
          (newline))
        (rows-of name)))
     '(score copy))))

(def (emit-case index case)
  (match case
    ([[initial-scores initial-improvements]
      [added-scores added-improvements]]
     (let* ((session
             (gerbil-ascent-open-session
              (product-program initial-scores initial-improvements)))
            (first (gerbil-ascent-session-run session))
            (rows-of (.ref first 'rows-of))
            (snapshot (map rows-of '(score copy))))
       (emit-result index 0 first)
       (for-each
        (lambda (row)
          (gerbil-ascent-session-append-source!
           session 'score (source-score row)))
        added-scores)
       (for-each
        (lambda (row)
          (gerbil-ascent-session-append-source! session 'improve row))
        added-improvements)
       (emit-result index 1 (gerbil-ascent-session-run session))
       (unless (equal? snapshot (map rows-of '(score copy)))
         (error "ASCENT product session changed a prior snapshot" index))))))

(def (main . args)
  (unless (null? args)
    (error "ASCENT product session corpus reads cases from stdin"))
  (let (cases (read))
    (for-each emit-case (iota (length cases)) cases))
  (display "END\n")
  (force-output))
