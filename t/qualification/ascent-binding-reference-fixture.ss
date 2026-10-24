;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later


;;; Frozen binding oracle from 74f0046bb6137b4fce22db5ae398b9812734c137.
(import (only-in :gerbil-ascent/program/objects gerbil-ascent-atom gerbil-ascent-clause-plan))
(export ascent-reference-bind-row ascent-binding-atom-plan)

(def (ascent-reference-expression-value payload environment)
  (apply (vector-ref payload 1)
         (map (lambda (name)
                (let (binding (assq name environment))
                  (unless binding
                    (error "unbound ASCENT expression variable" name))
                  (cdr binding)))
              (vector-ref payload 0))))

;;; Bind one candidate row without mutating the caller's environment. A
;;; repeated variable or failed pattern rejects this candidate with #f.
;; ascent-reference-bind-row
;;   : (-> Terms Row Environment (Maybe Environment))
;;   | doc m%
;;       Match ordered terms against one row and return extended bindings.
;;
;;       # Examples
;;
;;       ```scheme
;;       (ascent-reference-bind-row '((variable . x)) '(3) '())
;;       ;; => an environment binding x to 3
;;       ```
;;     %
(def (ascent-reference-bind-row terms row environment)
  (let loop ((patterns terms) (values row) (bindings environment))
    (if (null? patterns)
      bindings
      (let* ((term (car patterns))
             (value (car values))
             (kind (car term)))
        (case kind
          ((wildcard)
           (loop (cdr patterns) (cdr values) bindings))
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
                          (ascent-reference-expression-value
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

(def +binding-atom+ (gerbil-ascent-atom 'source []))

;;; Invoke the real checked clause planner with an already lowered atom.
(def (ascent-binding-atom-plan terms bound)
  (vector-ref
   (vector-ref
    (gerbil-ascent-clause-plan +binding-atom+
                              (lambda (_) (vector 0 terms)) bound)
    0)
   1))
