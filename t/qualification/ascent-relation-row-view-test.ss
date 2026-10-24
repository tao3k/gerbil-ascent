;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        :gerbil-ascent/program/objects
        (only-in :gerbil-ascent/program/types gerbil-ascent-relation-with-rows
                 GerbilAscentRelationContract GerbilAscentLatticeContract)
        (only-in :gerbil-ascent/interface/engine-api ascent-engine-program-wire)
        (only-in :clan/poo/object .o .ref object-revision object-slots object-slots-set!)
        (only-in :clan/poo/mop validate))
(export ascent-relation-row-view-test)

;;; Inspect the actual owner stamp in compiled code without adding a production
;;; test hook. It records field-specification ownership, never validation success.
(def shape? (##eval 'gerbil-ascent/program/types#declared-value-shape?))
(def ordinary-check (##eval 'gerbil-ascent/program/objects#current-declaration-check))
(def (old-view relation replacement) (.o (:: @ relation) rows: replacement))
(def (rejected? action) (with-catch (lambda (_) #t) (lambda () (action) #f)))
(def (same-data? a b)
  (cond ((hash-table? a)
         (and (hash-table? b) (= (hash-length a) (hash-length b))
              (andmap (lambda (entry)
                        (and (hash-key? b (car entry))
                             (same-data? (cdr entry) (hash-ref b (car entry)))))
                      (hash->list a))))
        ((pair? a) (and (pair? b) (same-data? (car a) (car b)) (same-data? (cdr a) (cdr b))))
        (else (equal? a b))))
(def (wire relation)
  (ascent-engine-program-wire
   (gerbil-ascent-program (list relation) [] 32 64 96 '(input))
   '(input) (list (cons 'input (list (hash ("kind" "native"))))) '(input)))
(def (getter-trace build throw?)
  (let ((trace []) (base (gerbil-ascent-relation 'input 1 [])))
    (let* ((parent (.o (:: @ base)
                      name: (begin
                              (set! trace (cons (list 'name (eq? (ordinary-check) validate)) trace))
                              (when throw? (error "row-view caller getter failure"))
                              'input)))
           (view (build parent '((1)))))
      (check trace => [])
      (check (shape? 'relation view) => #f)
      (let (failure? (rejected? (lambda () (validate GerbilAscentRelationContract view))))
        (list failure? (reverse trace))))))

(def ascent-relation-row-view-test
  (test-suite "Source row views retain fresh admission and prototype invalidation"
    (test-case "canonical views preserve duplicate, complex and mutable cell projection"
      (let* ((parent (gerbil-ascent-relation 'input 1 []))
             (cell (vector 7))
             (replacement (list (list cell) (list cell) '(1) '(#f) '(name) '("name") '(1/3)))
             (old (old-view parent replacement))
             (view (gerbil-ascent-relation-with-rows parent replacement)))
        (check (shape? 'relation parent) => #t)
        (check (shape? 'relation old) => #f)
        (check (shape? 'relation view) => #t)
        (check (eq? (.ref view 'rows) replacement) => #t)
        (check (eq? (caar (.ref view 'rows)) cell) => #t)
        (check (length (.ref view 'rows)) => 7)
        (check (same-data? (wire old) (wire view)) => #t)
        (vector-set! cell 0 9)
        (check (same-data? (wire old) (wire view)) => #t)))
    (test-case "every admission rechecks a mutated payload despite the same stamp"
      (let* ((parent (gerbil-ascent-relation 'input 1 []))
             (replacement (list '(1) '(2)))
             (view (gerbil-ascent-relation-with-rows parent replacement)))
        (validate GerbilAscentRelationContract view)
        (set-cdr! replacement 7)
        (check (shape? 'relation view) => #t)
        (check (rejected? (lambda () (validate GerbilAscentRelationContract view))) => #t)
        (check (rejected? (lambda () (validate GerbilAscentRelationContract (old-view parent replacement)))) => #t)))
    (test-case "real POO ancestor edits revoke all chained view stamps"
      (let* ((parent (gerbil-ascent-relation 'input 1 []))
             (view (gerbil-ascent-relation-with-rows parent '((1))))
             (child (gerbil-ascent-relation-with-rows view '((2)))))
        (check (shape? 'relation child) => #t)
        (object-slots-set! parent (object-slots parent))
        (for-each (lambda (value)
                    (check (> (object-revision value) 0) => #t)
                    (check (shape? 'relation value) => #f)) (list parent view child))
        (validate GerbilAscentRelationContract child)
        (check (shape? 'relation (gerbil-ascent-relation-with-rows parent '((3)))) => #f)))
    (test-case "direct view edits cannot retain producer ownership"
      (let* ((parent (gerbil-ascent-relation 'input 1 []))
             (view (gerbil-ascent-relation-with-rows parent '((1)))))
        (object-slots-set! view (object-slots view))
        (check (shape? 'relation view) => #f)
        (validate GerbilAscentRelationContract view)))
    (test-case "ordinary caller getters keep exception order and ordinary checks"
      (for-each (lambda (throw?)
                  (check (getter-trace gerbil-ascent-relation-with-rows throw?)
                         => (getter-trace old-view throw?))) '(#f #t)))
    (test-case "lattice declarations retain their original complete admission"
      (let* ((parent (gerbil-ascent-lattice 'input 2 '((1 3)) min))
             (replacement '((1 2) (1 2)))
             (view (gerbil-ascent-relation-with-rows parent replacement)))
        (check (shape? 'relation view) => #f)
        (validate GerbilAscentLatticeContract view)
        (check (eq? (.ref view 'join) (.ref parent 'join)) => #t)
        (check (.ref view 'rows) => replacement)))
    (test-case "row views do not change public constructor rejection"
      (check (rejected? (lambda () (gerbil-ascent-relation 'invalid 1 7))) => #t)
      (let* ((parent (gerbil-ascent-relation 'input 1 []))
             (view (gerbil-ascent-relation-with-rows parent 7)))
        (check (rejected? (lambda () (validate GerbilAscentRelationContract view))) => #t)))))
