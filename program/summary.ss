;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Static rule dependency SCCs. This is declaration metadata, independent of
;;; source rows and of the evaluator's (possibly coarser) strata.
(import (only-in :clan/poo/object .o .ref)
        (only-in :gerbil-ascent/core/dependency-graph gerbil-ascent-graph-components)
        (only-in :std/list/list append-map delete-duplicates/hash))

(export gerbil-ascent-program-summary)

;;; Declaration names are admitted symbols. Each invocation owns membership;
;;; the common zero/one-name layout needs no table or retained projection list.
;;; The projection runs once per item, including duplicates and nonreads.
;; : (forall (a) (-> [a] RelationProjectionBindings BodyExpressions Void))
;; : (-> DeclarationItems RelationProjectionBindings BodyExpressions Void)
(defrule (for-summary-relations items (item name projection) body ...)
  (let ((first #f) (seen #f))
    (for-each
     (lambda (item)
       (let (name projection)
         (when name
           (cond
            ((eq? first name) (void))
            ((not first) (set! first name) body ...)
            (else
             (unless seen (set! seen (make-hash-table-eq)))
             (unless (hash-key? seen name)
               (hash-put! seen name #t)
               body ...)))))) items)))

;;; All reads of a consumer are published together. Its edge is either absent
;;; or the current list head, so duplicate admission needs no per-vertex table.
;; : (-> Successors Natural Natural Void)
(def (publish-summary-edge! successors producer consumer)
  (let (neighbors (vector-ref successors producer))
    (unless (and (pair? neighbors) (= (car neighbors) consumer))
      (vector-set! successors producer (cons consumer neighbors)))))

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
       (for-summary-relations (.ref rule 'heads) (head name (.ref head 'relation))
         (hash-update! producers name (cut cons index <>) [])))
     rules (iota count))
    (for-each
     (lambda (rule consumer)
       (for-summary-relations (.ref rule 'body)
         (clause name (and (memq (.ref clause 'ascent-clause-kind) '(atom negation aggregate))
                          (.ref clause 'relation)))
         (for-each (cut publish-summary-edge! successors <> consumer)
                   (or (hash-get producers name) []))))
     rules (iota count))
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
