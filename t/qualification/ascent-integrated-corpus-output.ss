;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Batch differential adapter for one composed Ascent program. Each input
;;; case is (edge-rows blocked-nodes); every case gets a fresh POO program.
(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-count gerbil-ascent-evaluate-program
                 gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-run))

(export main)

(def (score-value? value)
  (and (vector? value)
       (= (vector-length value) 2)
       (integer? (vector-ref value 0))
       (integer? (vector-ref value 1))))

(def (score-join left right)
  (vector (max (vector-ref left 0) (vector-ref right 0))
          (max (vector-ref left 1) (vector-ref right 1))))

(def (case-program edges blocked)
  (ascent
    (relation edge ((from integer?) (to integer?)) edges)
    (relation block ((node integer?)) (map list blocked))
    (relation root ((node integer?)) '((0) (1) (2)))
    (relation path ((from integer?) (to integer?)))
    (relation witness ((node integer?)))
    (relation safe ((from integer?) (to integer?)))
    (relation reach-count ((node integer?) (total integer?)))
    (relation selected ((node integer?)))
    (lattice score ((node integer?) (value score-value?)) [] score-join)
    (((path x y) (witness y)) <-- (edge x y))
    ((path x z) <-- (path x y) (edge y z))
    ((safe x y) <-- (path x y) (not (block y)))
    ((reach-count x total) <-- (root x)
     (aggregate total gerbil-ascent-count () (path x target)))
    ((selected x) <--
     (or (and (witness x)) (and (root x)))
     (if (x) (even? x)))
    ((score to (expr (from to) (vector from to))) <-- (edge from to))
    ((score to (expr (value) value)) <--
     (score from value) (edge from to))
    (bounds 32 64 96)))

(def (evaluate-case edges blocked)
  (gerbil-ascent-evaluate-program (case-program edges blocked)))

(def (emit-case index result (phase #f))
  (let (rows-of (.ref result 'rows-of))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (display index)
          (display #\tab)
          (when phase
            (display phase)
            (display #\tab))
          (display name)
          (if (eq? name 'score)
            (begin
              (display #\tab)
              (display (car row))
              (display #\tab)
              (display (vector-ref (cadr row) 0))
              (display #\tab)
              (display (vector-ref (cadr row) 1)))
            (for-each
             (lambda (column)
               (display #\tab)
               (display column))
             row))
          (newline))
        (rows-of name)))
     '(path witness safe reach-count selected score))))

(def (emit-session-case index case)
  (let* ((initial (car case))
         (added (cadr case))
         (session (gerbil-ascent-open-session
                   (case-program (car initial) (cadr initial))))
         (first (gerbil-ascent-session-run session))
         (first-rows-of (.ref first 'rows-of))
         (names '(path witness safe reach-count selected score))
         (snapshot (map first-rows-of names)))
    (emit-case index first 0)
    (for-each
     (lambda (edge)
       (gerbil-ascent-session-append-source! session 'edge edge))
     (car added))
    (for-each
     (lambda (node)
       (gerbil-ascent-session-append-source! session 'block (list node)))
     (cadr added))
    (let (second (gerbil-ascent-session-run session))
      (emit-case index second 1)
      (unless (equal? snapshot (map first-rows-of names))
        (error "ASCENT composed session changed an earlier snapshot"
               index)))))

(def (main . args)
  (unless (null? args)
    (error "ASCENT integrated corpus reads a case list from stdin"))
  (let* ((request (read))
         (session? (and (pair? request) (eq? (car request) 'session)))
         (cases (if session? (cadr request) request)))
    (let loop ((cases cases) (index 0))
      (unless (null? cases)
        (let (case (car cases))
          (unless (and (list? case) (= (length case) 2))
            (error "invalid ASCENT integrated corpus case" case))
          (if session?
            (emit-session-case index case)
            (emit-case index (evaluate-case (car case) (cadr case)))))
        (loop (cdr cases) (+ index 1)))))
  (display "END\n")
  (force-output))
