;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Deliberately naive immediate consequences over immutable alists. No runtime
;;; matcher, graph analysis, indexes, delta or old evaluator is imported.
(export naive-positive naive-rules graph-input canonical-rows)
(def naive-rules '(((p x z) (q x y) (q y z)) ((q x y) (p x y)) ((p x y) (edge x y))))
(def (canonical-rows rows)
  (list-sort (lambda (a b) (or (< (car a) (car b)) (and (= (car a) (car b)) (< (cadr a) (cadr b))))) rows))
(def (graph-input mask)
  (let loop ((i 0) (out []))
    (if (= i 9) (reverse out)
      (loop (+ i 1) (if (zero? (bitwise-and mask (arithmetic-shift 1 i))) out
                     (cons (list (quotient i 3) (modulo i 3)) out))))))
(def (naive-positive edges rules)
  (let ((db (list (cons 'edge edges) (cons 'p []) (cons 'q []))) (witnesses 0))
    (def (bind terms row environment)
      (if (null? terms) environment
        (let (found (assq (car terms) environment))
          (if found
            (and (equal? (cdr found) (car row)) (bind (cdr terms) (cdr row) environment))
            (bind (cdr terms) (cdr row) (cons (cons (car terms) (car row)) environment))))))
    (let again ()
      (let ((next (map (lambda (entry) (cons (car entry) (cdr entry))) db)) (changed? #f))
        (for-each
         (lambda (rule)
           (def (body clauses environment)
             (if (null? clauses)
               (let* ((head (car rule)) (slot (assq (car head) next))
                      (row (map (lambda (v) (cdr (assq v environment))) (cdr head))))
                 (set! witnesses (+ witnesses 1))
                 (unless (member row (cdr slot))
                   (set-cdr! slot (cons row (cdr slot))) (set! changed? #t)))
               (let (clause (car clauses))
                 (for-each (lambda (row)
                             (let (matched (bind (cdr clause) row environment))
                               (when matched (body (cdr clauses) matched))))
                           (cdr (assq (car clause) db))))))
           (body (cdr rule) [])) rules)
        (set! db next)
        (if changed? (again) (values db witnesses))))))
