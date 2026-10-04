;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Two recursive lattice families share one retained positive source session.
(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-replace-source!
                 gerbil-ascent-session-run)
        (only-in :gerbil-ascent/program/syntax ascent))

(export main)

(def (set-union left right)
  (foldl (lambda (value members)
           (if (member value members) members (cons value members)))
         left right))

(def (program edges)
  (ascent
   (relation edge ((from integer?) (to integer?) (weight integer?)) edges)
   (lattice shortest ((from integer?) (to integer?) (distance integer?))
            [] min)
   (lattice reach-tag ((node integer?) (tags list?)) [] set-union)
   ((shortest from to (expr (weight) weight)) <--
    (edge from to weight))
   ((shortest from to (expr (first weight) (+ first weight))) <--
    (shortest from via first) (edge via to weight))
   ((reach-tag from (expr (from) (list from))) <--
    (edge from to weight))
   ((reach-tag to (expr (tags) tags)) <--
    (reach-tag from tags) (edge from to weight))
   (bounds 32 64 96)))

(def (emit-rows index phase result)
  (let (rows-of (.ref result 'rows-of))
    (for-each
     (lambda (row)
       (display index) (display #\tab) (display phase)
       (display "\tshortest")
       (for-each (lambda (column) (display #\tab) (display column)) row)
       (newline))
     (rows-of 'shortest))
    (for-each
     (lambda (row)
       (for-each
        (lambda (tag)
          (display index) (display #\tab) (display phase)
          (display "\treach-tag\t") (display (car row))
          (display #\tab) (display tag) (newline))
        (cadr row)))
     (rows-of 'reach-tag))))

(def (direct-program scores (improvements []))
  (ascent
   (lattice score ((node integer?) (value integer?)) scores min)
   (relation improve ((node integer?) (value integer?)) improvements)
   (lattice copy ((node integer?) (value integer?)) [] min)
   ((score node value) <-- (improve node value))
   ((copy node value) <-- (score node value))
   (bounds 32 64 96)))

(def (emit-direct-rows index phase result)
  (let (rows-of (.ref result 'rows-of))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (display index) (display #\tab) (display phase)
          (display #\tab) (display name)
          (for-each
           (lambda (column) (display #\tab) (display column))
           row)
          (newline))
        (rows-of name)))
     '(score copy))))

(def (print-direct-cases cases mixed?)
  (let loop ((remaining cases) (index 0))
    (unless (null? remaining)
      (let* ((case (car remaining))
             (initial (car case))
             (added (cadr case))
             (session
              (gerbil-ascent-open-session
               (direct-program initial
                               (if mixed? '((0 2) (1 1)) []))))
             (first (gerbil-ascent-session-run session))
             (first-rows-of (.ref first 'rows-of))
             (first-snapshot (map first-rows-of '(score copy))))
        (emit-direct-rows index 0 first)
        (for-each
         (lambda (row)
           (gerbil-ascent-session-append-source! session 'score row))
         added)
        (emit-direct-rows index 1 (gerbil-ascent-session-run session))
        (unless (equal? first-snapshot (map first-rows-of '(score copy)))
          (error "ASCENT direct lattice source changed a prior snapshot"
                 index)))
      (loop (cdr remaining) (+ index 1)))))

(def (print-wide-session size)
  (let* ((keys (iota size))
         (source (map (lambda (key) (list key (+ key (* 2 size)))) keys))
         (improvements (map (lambda (key) (list key (+ key size))) keys))
         (session
          (gerbil-ascent-open-session
           (ascent
            (lattice score ((node integer?) (value integer?)) source min)
            (relation improve ((node integer?) (value integer?)) improvements)
            (lattice copy ((node integer?) (value integer?)) [] min)
            ((score node value) <-- (improve node value))
            ((copy node value) <-- (score node value))
            (bounds (+ (* 2 size) 1) (* 3 size) (* 6 size)))))
         (first (gerbil-ascent-session-run session))
         (first-rows-of (.ref first 'rows-of))
         (first-snapshot (map first-rows-of '(score copy))))
    (emit-direct-rows size 0 first)
    (gerbil-ascent-session-append-source! session 'score '(0 1))
    (emit-direct-rows size 1 (gerbil-ascent-session-run session))
    (gerbil-ascent-session-replace-source!
     session 'score (map (lambda (key) (list key (+ key 2))) keys))
    (emit-direct-rows size 2 (gerbil-ascent-session-run session))
    (unless (equal? first-snapshot (map first-rows-of '(score copy)))
      (error "ASCENT wide lattice session changed a prior snapshot" size))))

(def (main . args)
  (unless (null? args)
    (error "ASCENT lattice session corpus reads one case list"))
  (let (request (read))
    (cond
     ((and (pair? request) (eq? (car request) 'wide-session))
      (print-wide-session (cadr request)))
     ((and (pair? request) (memq (car request) '(direct mixed)))
      (print-direct-cases (cadr request) (eq? (car request) 'mixed)))
     (else
      (let loop ((cases request) (index 0))
        (unless (null? cases)
          (let* ((case (car cases))
                 (initial (car case))
                 (added (cadr case))
                 (session (gerbil-ascent-open-session (program initial)))
                 (first (gerbil-ascent-session-run session))
                 (first-rows-of (.ref first 'rows-of))
                 (first-snapshot
                  (map first-rows-of '(shortest reach-tag))))
            (emit-rows index 0 first)
            (for-each
             (lambda (edge)
               (gerbil-ascent-session-append-source! session 'edge edge))
             added)
            (emit-rows index 1 (gerbil-ascent-session-run session))
            (unless (equal? first-snapshot
                            (map first-rows-of '(shortest reach-tag)))
              (error "ASCENT lattice session changed a prior snapshot"
                     index)))
          (loop (cdr cases) (+ index 1)))))))
  (display "END\n")
  (force-output))
