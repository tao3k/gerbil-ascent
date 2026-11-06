;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Deliberately naive immediate consequences over immutable alists. No runtime
;;; matcher, graph analysis, indexes, delta or old evaluator is imported.
(export naive-positive naive-rules graph-input canonical-rows finite-domain-closure)

;;; Independent function-free positive oracle: enumerate *all* assignments of
;;; rule variables over the declared domain, then test ground membership.
;;; This uses no production matcher, lowering, index, delta, or planner.
;;; sources declares every relation (including empty derived relations).
(def (finite-domain-closure domain sources rules)
  (for-each (lambda (entry)
              (for-each (lambda (row)
                          (unless (andmap (lambda (x) (member x domain)) row)
                            (error "oracle source outside finite domain" row)))
                        (cdr entry))) sources)
  (def (variables rule)
    (foldl (lambda (atom found)
             (foldl (lambda (v found) (if (memq v found) found (cons v found)))
                    found (cdr atom))) [] rule))
  (def (ground atom env)
    (cons (car atom) (map (lambda (v) (cdr (assq v env))) (cdr atom))))
  (let loop ((db sources))
    (let ((next (map (lambda (entry) (cons (car entry) (cdr entry))) db)) (changed? #f))
      (for-each
       (lambda (rule)
         (def (assign remaining env)
           (if (pair? remaining)
             (for-each (lambda (value) (assign (cdr remaining)
                                              (cons (cons (car remaining) value) env))) domain)
             (when (andmap (lambda (atom)
                             (let (g (ground atom env))
                               (member (cdr g) (cdr (assq (car g) db))))) (cdr rule))
               (let* ((g (ground (car rule) env)) (slot (assq (car g) next)))
                 (unless (member (cdr g) (cdr slot))
                   (set-cdr! slot (cons (cdr g) (cdr slot)))
                   (set! changed? #t))))))
         (assign (variables rule) [])) rules)
      (if changed? (loop next) db))))
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
