;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(export finite-choice-solutions)

(def (natural? value)
  (and (exact-integer? value) (>= value 0)))

;; Databases are sorted alists by ground attribute identity. Extend only at
;; absent keys, so siblings can share their unmodified tails.
(def (insert-assignment database attribute value)
  (if (or (null? database) (< attribute (caar database)))
    (cons (cons attribute value) database)
    (cons (car database) (insert-assignment (cdr database) attribute value))))

;; Rules have the form (closed attribute values body) or
;; (open attribute value body). Bodies are lists of (attribute . value).
;; Empty closed offers can express a forbidden body.
(def (ground-rule? rule)
  (match rule
    ([kind attribute offer body]
     (and (natural? attribute)
          (case kind
            ((closed) (and (list? offer) (andmap natural? offer)))
            ((open) (natural? offer))
            (else #f))
          (list? body)
          (andmap (lambda (fact)
                    (and (pair? fact) (natural? (car fact)) (natural? (cdr fact))))
                  body)))
    (else #f)))

(def (enabled? database body)
  (andmap (lambda (fact)
            (let (known (assv (car fact) database))
              (and known (= (cdr known) (cdr fact)))))
          body))

;; False means an enabled closed requirement makes this branch inconsistent.
;; An empty list means it has no strict successor.
(def (rule-extensions database rule checkpoint!)
  (match rule
    ([kind attribute offer body]
     (cond
       ((not (enabled? database body)) [])
       ((assv attribute database)
        => (lambda (known)
             (and (or (eq? kind 'open) (memv (cdr known) offer)) [])))
       ((and (eq? kind 'closed) (null? offer)) #f)
       (else
        (map (lambda (value)
               (checkpoint!)
               (insert-assignment database attribute value))
             (if (eq? kind 'open) (list offer) offer)))))))

;; The caller owns its budget and cancellation policy through a checkpoint
;; which may raise. Only a fully exhausted search returns any solutions.
(def (finite-choice-solutions rules checkpoint!)
  (unless (and (list? rules) (andmap ground-rule? rules) (procedure? checkpoint!))
    (error "invalid ground finite-choice program"))
  (let ((seen (make-hash-table)) (solutions []))
    (let search ((pending (list [])))
      (if (null? pending) (reverse! solutions)
        (let ((database (car pending)) (rest (cdr pending)))
          (checkpoint!)
          (if (hash-get seen database) (search rest)
            (begin
              (hash-put! seen database #t)
              (let scan ((remaining rules) (next rest) (saturated? #t))
                (if (null? remaining)
                  (begin
                    (when saturated? (set! solutions (cons database solutions)))
                    (search next))
                  (let (extensions
                        (begin
                          (checkpoint!)
                          (rule-extensions database (car remaining) checkpoint!)))
                    (cond
                      ((not extensions) (search rest))
                      ((null? extensions) (scan (cdr remaining) next saturated?))
                      (else (scan (cdr remaining) (append extensions next) #f)))))))))))))
