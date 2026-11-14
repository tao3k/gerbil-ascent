;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil-ascent/candidate/program candidate-variable?))
(export prepare-reduction-row)

;;; A successful ordered prefix fixes outer bindings. Reduction-local variables
;;; disappear at the group boundary: test only outer constraints and repetitions,
;;; then read the aggregate operand without building unused binding pairs.
;; : (forall (row) (-> (Atom row) Operator SymbolSet (Values RowPredicate RowValue)))
;; : (-> InspectedAtom Operator PrefixBindings (Values RowPredicate RowValue))
(def (prepare-reduction-row atom operator known)
  (let ((positions (make-hash-table-eq size: (length (cdr atom)))) (index 0))
    (let* ((checks
            (map (lambda (term)
                   (let (position index)
                     (set! index (+ index 1))
                     (cond
                      ((eq? term '?_) #f)
                      ((not (candidate-variable? term))
                       (lambda (row _bindings) (equal? term (list-ref row position))))
                      ((hash-get known term)
                       (lambda (row bindings)
                         (cond ((assq term bindings)
                                => (lambda (old) (equal? (cdr old) (list-ref row position))))
                               (else #f))))
                      ((hash-get positions term)
                       => (lambda (first)
                            (lambda (row _bindings)
                              (equal? (list-ref row first) (list-ref row position)))))
                      (else (hash-put! positions term position) #f))))
                 (cdr atom)))
           (active (filter values checks))
           (match-row (lambda (row bindings) (andmap (cut <> row bindings) active)))
           (value
            (if (eq? (car operator) 'count)
              (lambda (_row _bindings) #f)
              (let (name (cadr operator))
                (if (hash-get known name)
                  (lambda (_row bindings) (cdr (assq name bindings)))
                  (let (position (hash-get positions name))
                    (lambda (row _bindings) (list-ref row position))))))))
      (values match-row value))))
