;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/runtime/gambit)
(export steensgaard-truth)

;; Independent partition saturation. It does not use Scheme clauses, UF,
;; the production equality Provider, or the explicit Datalog closure rules.
(def (steensgaard-truth alloc assign load store)
  (let ((classes []) (changed? #f))
    (def (class-of value)
      (let loop ((remaining classes))
        (and (pair? remaining)
             (if (member value (car remaining)) (car remaining) (loop (cdr remaining))))))
    (def (join! a b)
      (let ((left (class-of a)) (right (class-of b)))
        (unless (and left (eq? left right))
          (set! classes (cons (append (or left (list a))
                                      (if (equal? a b) [] (or right (list b))))
                              (filter (lambda (members) (and (not (eq? members left))
                                                              (not (eq? members right)))) classes)))
          (set! changed? #t))))
    (for-each (lambda (pair) (join! (car pair) (cadr pair))) (append alloc assign))
    (let loop ()
      (set! changed? #f)
      (for-each (lambda (write)
        (for-each (lambda (read)
          (let (members (class-of (car write)))
            (when (and members (member (cadr read) members)
                       (equal? (cadr write) (caddr read)))
              (join! (caddr write) (car read))))) load)) store)
      (when changed? (loop)))
    (apply append (map (lambda (members)
      (apply append (map (lambda (left) (map (lambda (right) (list left right)) members)) members))) classes))))
