;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .ref)
 :gerbil-ascent/program/operator-lowering :gerbil-ascent/program/objects
 (only-in :gerbil-ascent/t/performance/lexical-dependencies/fixture lexical-input)
 (prefix-in :gerbil-ascent/t/performance/binding-resolution/reference old-)
 (only-in :std/list/list delete-duplicates/hash))
(export binding-input binding-workflow binding-shape)
(def (binding-input width depth queries shape) (lexical-input width depth queries shape))
(def (binding-workflow old? input)
 (call-with-values (lambda ()
   ((if old? old-lower-operator-graph lower-operator-graph) (vector-ref input 0) #f gerbil-ascent-relation gerbil-ascent-rule)) list))
;; Every relation handle and every term occurrence is alpha-normalized, retaining
;; rule-local variable sharing and the exact topology of captured lexical slots.
(def (binding-shape result)
 (with ([relations rules sources output labels] result)
  (let (positions (make-hash-table-eq))
    (for-each (lambda (r n) (hash-put! positions (.ref r 'name) n)) relations (iota (length relations)))
    (list (map (lambda (r) (list (.ref r 'arity) (.ref r 'rows))) relations)
      (delete-duplicates/hash (map (lambda (rule)
        (let ((variables (make-hash-table-eq)) (next 0))
          (def (atom a)
            (list (hash-ref positions (.ref a 'relation))
              (map (lambda (term)
                (let (name (.ref term 'value))
                  (unless (hash-get variables name)
                    (set! next (+ next 1)) (hash-put! variables name next))
                  (list (.ref term 'kind) (hash-ref variables name)))) (.ref a 'terms))))
          (list (map atom (.ref rule 'heads)) (map atom (.ref rule 'body))))) rules) from-end?: #t)
      (map (cut hash-ref positions <>) sources) (hash-ref positions output)
      (map (lambda (entry) (cons (car entry) (hash-ref positions (cdr entry)))) labels)))))
