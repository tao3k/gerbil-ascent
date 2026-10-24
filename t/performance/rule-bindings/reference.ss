;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(export gerbil-ascent-expression-value gerbil-ascent-bind-row gerbil-ascent-head-row)

(def (gerbil-ascent-expression-value payload environment)
  (apply (vector-ref payload 1)
         (map (lambda (name)
                (let (binding (assq name environment))
                  (unless binding
                    (error "unbound ASCENT expression variable" name))
                  (cdr binding)))
              (vector-ref payload 0))))

;;; Bind one candidate row without mutating the caller's environment. A
;;; repeated variable or failed pattern rejects this candidate with #f.
;; gerbil-ascent-bind-row
;;   : (-> Terms Row Environment (Maybe Environment))
;;   | doc m%
;;       Match ordered terms against one row and return extended bindings.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-bind-row '((variable . x)) '(3) '())
;;       ;; => an environment binding x to 3
;;       ```
;;     %
(def (gerbil-ascent-bind-row terms row environment)
  (let loop ((patterns terms) (values row) (bindings environment))
    (if (null? patterns)
      bindings
      (let* ((term (car patterns))
             (value (car values))
             (kind (car term)))
        (case kind
          ((wildcard)
           (loop (cdr patterns) (cdr values) bindings))
          ((fresh-variable)
           ;; Private checked plans prove this name absent, including earlier
           ;; terms in the same atom. No row-time environment search is needed.
           (loop (cdr patterns) (cdr values)
                 (cons (cons (cdr term) value) bindings)))
          ((pattern)
           (let* ((payload (cdr term))
                  (matched ((vector-ref payload 1) value))
                  (outputs (vector-ref payload 0)))
             (and matched
                  (begin
                    (unless (and (list? matched)
                                 (= (length matched) (length outputs)))
                      (error "ASCENT pattern returned invalid bindings"
                             matched outputs))
                    (loop (cdr patterns) (cdr values)
                          (append (map cons outputs matched) bindings))))))
          ((literal expression)
           (and (equal? (if (eq? kind 'literal)
                          (cdr term)
                          (gerbil-ascent-expression-value
                           (cdr term) bindings))
                        value)
                (loop (cdr patterns) (cdr values) bindings)))
          (else
           (let* ((name (cdr term))
                  (previous (assq name bindings)))
             (if previous
               (and (equal? (cdr previous) value)
                    (loop (cdr patterns) (cdr values) bindings))
               (loop (cdr patterns) (cdr values)
                     (cons (cons name value) bindings))))))))))

(def (gerbil-ascent-head-row terms environment)
  (map (lambda (term)
         (case (car term)
           ((literal) (cdr term))
           ((expression)
            (gerbil-ascent-expression-value (cdr term) environment))
           ((pattern)
            (error "ASCENT pattern is invalid in a rule head"))
           ((wildcard)
            (error "ASCENT wildcard is invalid in a rule head"))
           (else
            (let (binding (assq (cdr term) environment))
              (unless binding
                (error "unbound ASCENT head variable" (cdr term)))
              (cdr binding)))))
       terms))
