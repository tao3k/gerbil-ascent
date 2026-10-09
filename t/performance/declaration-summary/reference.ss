;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Static rule dependency SCCs. This is declaration metadata, independent of
;;; source rows and of the evaluator's (possibly coarser) strata.
(import (only-in :clan/poo/object .o .ref)
        (only-in :gerbil-ascent/core/dependency-graph gerbil-ascent-graph-components)
        (only-in :std/list/list append-map delete-duplicates/hash))

(export gerbil-ascent-program-summary)

;; gerbil-ascent-program-summary
;;   : (forall (row) (-> (Program row) (ProgramSummary row)))
;;   : (-> Program ProgramSummary)
;;   | doc m%
;;       Return one POO SCC descriptor per rule dependency component.
;;       Components expose source rule indexes, dynamic relation names,
;;       and a Boolean indicating a recursive component.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-program-summary program)
;;       ;; => an immutable POO summary with an sccs slot
;;       ```
;;     %
;; Rule vertices match the pinned macro's dependency graph. This summary is
;; immutable declaration metadata, so retained source updates do not rebuild
;; it and never alias mutable relation storage.
(def (gerbil-ascent-program-summary program)
  (let* ((rules (.ref program 'rules))
         (count (length rules))
         (rule-vector (list->vector rules))
         (producers (make-hash-table-eq))
         (successors (make-vector count [])))
    (for-each
     (lambda (rule index)
       (for-each
        (lambda (head)
          (let (name (.ref head 'relation))
            (hash-update! producers name
                          (lambda (prior) (cons index prior)) [])))
        (.ref rule 'heads)))
     rules (iota count))
    (for-each
     (lambda (rule consumer)
       (for-each
        (lambda (clause)
          (when (memq (.ref clause 'ascent-clause-kind)
                      '(atom negation aggregate))
            (for-each
             (lambda (producer)
               (vector-set! successors producer
                            (cons consumer
                                  (vector-ref successors producer))))
             (or (hash-get producers (.ref clause 'relation)) []))))
        (.ref rule 'body)))
     rules (iota count))
    (set! successors
      (vector-map (lambda (neighbors)
                    (delete-duplicates/hash neighbors))
                  successors))
    ;; std/struct/dag rejects cyclic graphs, so it cannot find these SCCs.
    ;; Tarjan visits each rule and dependency once. The reversed list of
    ;; completed components is in producer-before-consumer order.
    (let (components (gerbil-ascent-graph-components successors))
      (.o
       (sccs
        (map
         (lambda (members)
           (let* ((ordered (list-sort < members))
                  (names
                   (list-sort
                    (lambda (left right)
                      (string<? (symbol->string left)
                                (symbol->string right)))
                    (delete-duplicates/hash
                     (append-map
                      (lambda (index)
                        (map (lambda (head) (.ref head 'relation))
                             (.ref (vector-ref rule-vector index) 'heads)))
                      ordered))))
                  (looping?
                   (or (> (length ordered) 1)
                       (memv (car ordered)
                             (vector-ref successors (car ordered))))))
             (.o (rules ordered)
                 (dynamic-relations names)
                 (is-looping (if looping? #t #f)))))
         components))))))
