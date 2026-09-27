;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Two recursive lattice families share one retained positive source session.
(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-run))

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

(def (direct-program scores)
  (ascent
   (lattice score ((node integer?) (value integer?)) scores min)
   (relation copy ((node integer?) (value integer?)))
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

(def (print-direct-cases cases)
  (let loop ((remaining cases) (index 0))
    (unless (null? remaining)
      (let* ((case (car remaining))
             (initial (car case))
             (added (cadr case))
             (session (gerbil-ascent-open-session
                       (direct-program initial)))
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

(def (main . args)
  (unless (null? args)
    (error "ASCENT lattice session corpus reads one case list"))
  (let (request (read))
    (if (and (pair? request) (eq? (car request) 'direct))
      (print-direct-cases (cadr request))
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
          (loop (cdr cases) (+ index 1))))))
  (display "END\n")
  (force-output))
