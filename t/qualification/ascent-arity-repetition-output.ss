;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-open-session
                 gerbil-ascent-session-replace-source!
                 gerbil-ascent-session-run)
        (only-in :gerbil-ascent/program/syntax ascent))

(export main)

(def (case-program edges enabled? variant)
  (if (= variant 0)
    (ascent
     (relation enabled () (if enabled? '(()) []))
     (relation edge (from to) edges)
     (relation loop_node (node))
     (relation loop_twin (node))
     (relation wedge (from via to))
     (relation quad (from via next to))
     (relation quint (from via first second to))
     (relation reach (from to))
     (relation cycle0 ())
     (((loop_node x) (loop_twin x)) <-- (edge x x))
     ((wedge x y z) <-- (enabled) (edge x y) (edge y z))
     ((quad x y z w) <-- (wedge x y z) (edge z w))
     ((quint x y z w v) <-- (quad x y z w) (edge w v))
     ((reach x y) <-- (edge x y))
     ((reach x z) <-- (reach x y) (edge y z))
     ((cycle0) <-- (reach x x))
     (bounds 16 512 768))
    (ascent
     (relation enabled () (if enabled? '(()) []))
     (relation edge (from to) edges)
     (relation loop_node (node))
     (relation loop_twin (node))
     (relation wedge (from via to))
     (relation quad (from via next to))
     (relation quint (from via first second to))
     (relation reach (from to))
     (relation cycle0 ())
     ((cycle0) <-- (reach x x))
     ((reach x z) <-- (edge y z) (reach x y))
     ((reach x y) <-- (edge x y))
     ((quint x y z w v) <-- (edge w v) (quad x y z w))
     ((quad x y z w) <-- (edge z w) (wedge x y z))
     ((wedge x y z) <-- (edge y z) (edge x y) (enabled))
     (((loop_twin x) (loop_node x)) <-- (edge x x))
     (bounds 16 512 768))))

(def (print-case mask enabled? variant session edges)
  (gerbil-ascent-session-replace-source! session 'edge edges)
  (let* ((result (gerbil-ascent-session-run session))
         (rows-of (.ref result 'rows-of)))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (display mask) (display #\tab)
          (display (if enabled? 1 0)) (display #\tab)
          (display variant) (display #\tab)
          (display name)
          (for-each (lambda (column) (display #\tab) (display column)) row)
          (newline))
        (rows-of name)))
     '(loop_node loop_twin wedge quad quint reach cycle0))))

(def (main . args)
  (unless (null? args)
    (error "ASCENT arity corpus reads cases from stdin"))
  ;; Four immutable rule plans cover all snapshots. Source replacement keeps
  ;; each accepted result independent while exercising retained withdrawal.
  (let (sessions
        (vector (gerbil-ascent-open-session (case-program [] #f 0))
                (gerbil-ascent-open-session (case-program [] #f 1))
                (gerbil-ascent-open-session (case-program [] #t 0))
                (gerbil-ascent-open-session (case-program [] #t 1))))
    (for-each gerbil-ascent-session-run (vector->list sessions))
    (for-each
     (lambda (entry)
       (let ((mask (car entry)) (edges (cadr entry)))
         (unless (and (exact-integer? mask) (<= 0 mask) (< mask 512)
                      (list? edges))
           (error "invalid ASCENT arity corpus case" entry))
         (for-each
          (lambda (enabled? offset)
            (print-case mask enabled? 0 (vector-ref sessions offset) edges)
            (print-case mask enabled? 1 (vector-ref sessions (+ offset 1))
                        edges))
          '(#f #t) '(0 2))))
     (read)))
  (display "END\n")
  (force-output))
