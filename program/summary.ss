;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Static rule dependency SCCs. This is declaration metadata, independent of
;;; source rows and of the evaluator's (possibly coarser) strata.
(import (only-in :clan/poo/object .o .ref))

(export gerbil-ascent-program-summary)

;; cons-unique
;;   : (forall (a) (-> a (List a) (List a)))
;;   : (-> RelationName RelationNames RelationNames)
;;   | doc m%
;;       Add a relation name once to the declaration-only SCC accumulator.
;;
;;       # Examples
;;
;;       ```scheme
;;       (cons-unique 'edge '(edge))
;;       ;; => (edge)
;;       ```
;;     %
;; The declaration path is cold; preserve first-use order without sorting
;; names in the evaluator's hot row loop.
(def (cons-unique name names)
  (if (memq name names) names (cons name names)))

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
            (hash-put! producers name
                       (cons index (or (hash-get producers name) [])))))
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
               (unless (memv consumer (vector-ref successors producer))
                 (vector-set! successors producer
                              (cons consumer
                                    (vector-ref successors producer)))))
             (or (hash-get producers (.ref clause 'relation)) []))))
        (.ref rule 'body)))
     rules (iota count))
    ;; Tarjan visits each rule and dependency once. The reversed list of
    ;; completed components is in producer-before-consumer order.
    (let ((next-index 0)
          (indices (make-vector count #f))
          (lowlinks (make-vector count 0))
          (on-stack (make-vector count #f))
          (stack [])
          (components []))
      (def (visit node)
        (let (index next-index)
          (set! next-index (+ next-index 1))
          (vector-set! indices node index)
          (vector-set! lowlinks node index)
          (vector-set! on-stack node #t)
          (set! stack (cons node stack)))
        (for-each
         (lambda (neighbor)
           (cond
            ((not (vector-ref indices neighbor))
             (visit neighbor)
             (vector-set! lowlinks node
                          (min (vector-ref lowlinks node)
                               (vector-ref lowlinks neighbor))))
            ((vector-ref on-stack neighbor)
             (vector-set! lowlinks node
                          (min (vector-ref lowlinks node)
                               (vector-ref indices neighbor))))))
         (vector-ref successors node))
        (when (= (vector-ref lowlinks node) (vector-ref indices node))
          (let pop ((members []))
            (let (member (car stack))
              (set! stack (cdr stack))
              (vector-set! on-stack member #f)
              (let (collected (cons member members))
                (if (= member node)
                  (set! components (cons collected components))
                  (pop collected)))))))
      (for-each
       (lambda (index)
         (unless (vector-ref indices index) (visit index)))
       (iota count))
      (.o
       (sccs
        (map
         (lambda (members)
           (let* ((ordered members)
                  (names
                   (reverse
                    (let collect-rules ((remaining ordered) (found []))
                      (if (null? remaining)
                        found
                        (collect-rules
                         (cdr remaining)
                         (let collect-heads
                             ((heads (.ref (vector-ref rule-vector
                                                        (car remaining)) 'heads))
                              (acc found))
                           (if (null? heads) acc
                               (collect-heads
                                (cdr heads)
                                (cons-unique (.ref (car heads) 'relation)
                                             acc)))))))))
                  (looping?
                   (or (> (length ordered) 1)
                       (memv (car ordered)
                             (vector-ref successors (car ordered))))))
             (.o (rules ordered)
                 (dynamic-relations names)
                 (is-looping (if looping? #t #f)))))
         components))))))
