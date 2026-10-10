;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object :gerbil-ascent/program/objects
        (only-in :std/error Error? Error-message)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine)
        (rename-in (only-in :gerbil-ascent/t/performance/source-materialization/reference-evaluate
                           gerbil-ascent-make-engine)
                   (gerbil-ascent-make-engine frozen-engine))
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-set-storage-provider
                 gerbil-ascent-trrel-storage-provider))
(export ascent-initial-admission-test)

;;; Observe callbacks and errors through complete fresh engine construction;
;;; each call gets independent rows, providers and event storage.
(def (observe-admission maker mutation? custom? limit)
  (let* ((events []) (row (list 1))
         (check-field (lambda (value)
                        (set! events (cons (list 'check value) events))
                        (when mutation? (set-cdr! row (list 2))) #t))
         (provider (if custom?
                     (.o (:: @ gerbil-ascent-set-storage-provider)
                       (.extend-rows (lambda (_state _all _pending input _budget)
                                      (set! events (cons (list 'extend (car input)) events))
                                      (list input))))
                     gerbil-ascent-set-storage-provider))
         (relation (.o (:: @ (gerbil-ascent-relation 'input 1 []))
                     rows: (list row (list 3))
                     storage-provider: provider
                     field-predicates: (list check-field)))
         (program (.o (:: @ (gerbil-ascent-program [] [] 8 8 8))
                    relations: (list relation) max-input-facts: limit))
         (outcome (with-catch
                   (lambda (error) (Error-message error))
                   (lambda ()
                     ((.ref ((.ref (maker program #t) '.run)) 'rows-of) 'input)))))
    (list outcome (reverse events))))

(def ascent-initial-admission-test
  (test-suite "Initial admission selects a relation algorithm before traversal"
    (test-case "callback admission preserves borrowed source-header traversal"
      (def (observe maker)
        (let* ((source-rows (list (list 1) (list 2) (list 3)))
               (events [])
               (predicate (lambda (value)
                            (set! events (cons value events))
                            (when (= value 1) (set-cdr! source-rows [])) #t))
               (relation (.o (:: @ (gerbil-ascent-relation 'input 1 []))
                           rows: source-rows field-predicates: (list predicate)))
               (program (.o (:: @ (gerbil-ascent-program [] [] 8 8 8))
                          relations: (list relation)))
               (result ((.ref (maker program #t) '.run))))
          (list ((.ref result 'rows-of) 'input) (reverse events))))
      (check (observe frozen-engine) => '(((1)) (1 1)))
      (check (observe gerbil-ascent-make-engine) => '(((1)) (1 1))))
    (test-case "bulk Set admission charges duplicate source occurrences"
      (for-each (lambda (maker)
                  (let (program (gerbil-ascent-program
                                  (list (gerbil-ascent-relation 'input 1 '((1) (1) (1))))
                                  [] 2 8 8))
                    (check (with-catch Error-message (lambda () (maker program #t)))
                           => "ASCENT source fact budget exceeded")))
                (list frozen-engine gerbil-ascent-make-engine)))
    (test-case "bulk Set admission retains a preceding expansion's materialized budget"
      (for-each
       (lambda (maker)
         (let* ((provider (.o (:: @ gerbil-ascent-set-storage-provider)
                            (.extend-rows (lambda (_state _all _pending _row _budget)
                                            '((1) (2) (3))))))
                (relations (list (gerbil-ascent-relation 'expanded 1 '((1))
                                   gerbil-ascent-hash-index-provider provider)
                                 (gerbil-ascent-relation 'input 1 '((4) (5)))))
                (program (gerbil-ascent-program relations [] 8 8 4)))
           (check (with-catch Error-message (lambda () (maker program #t)))
                  => "ASCENT source fact budget exceeded")
           (let* ((accepted (.o (:: @ program) max-output-facts: 5))
                  (result ((.ref (maker accepted #t) '.run))))
             (check ((.ref result 'rows-of) 'expanded) => '((1) (2) (3)))
             (check ((.ref result 'rows-of) 'input) => '((4) (5))))))
       (list frozen-engine gerbil-ascent-make-engine)))
    (test-case "source-admission-loop preserves custom callback and expansion order"
      (let (expected '(((1) (3)) ((check 1) (extend 1) (check 1)
                                 (check 3) (extend 3) (check 3))))
        (for-each (lambda (maker)
                    (check (observe-admission maker #f #t 8) => expected))
                  (list frozen-engine gerbil-ascent-make-engine))))
    (test-case "source-admission-loop rechecks a Set row mutated by its first callback"
      (for-each (lambda (maker)
                  (check (observe-admission maker #t #f 8)
                         => '("invalid ASCENT storage provider row" ((check 1)))))
                (list frozen-engine gerbil-ascent-make-engine)))
    (test-case "source-admission-loop charges the source budget before custom expansion"
      (for-each (lambda (maker)
                  (check (observe-admission maker #f #t 1)
                         => '("ASCENT source fact budget exceeded"
                              ((check 1) (extend 1) (check 1) (check 3)))))
                (list frozen-engine gerbil-ascent-make-engine)))
    (test-case "mixed Set lattice and native graph sources keep duplicates and closure"
      (for-each
       (lambda (maker)
         (let* ((program (gerbil-ascent-program
                          (list (gerbil-ascent-relation 'input 1 '((1) (1) (2)))
                                (gerbil-ascent-lattice 'height 2 '((0 1) (0 3) (0 2)) max)
                                (gerbil-ascent-relation 'edges 2 '((0 1) (1 2))
                                  gerbil-ascent-hash-index-provider gerbil-ascent-trrel-storage-provider))
                          [] 16 16 64))
                (engine (maker program #t))
                (result ((.ref engine '.run))))
           (check ((.ref result 'rows-of) 'input) => '((1) (1) (2)))
           (check ((.ref result 'rows-of) 'height) => '((0 3)))
           (check (list-sort (lambda (a b) (or (< (car a) (car b))
                                              (and (= (car a) (car b)) (< (cadr a) (cadr b)))))
                    ((.ref result 'rows-of) 'edges)) => '((0 1) (0 2) (1 2)))
           ((.ref engine '.replace-source!) 'height '((0 2) (0 5)))
           (check ((.ref ((.ref engine '.run)) 'rows-of) 'height) => '((0 5)))
           (check ((.ref result 'rows-of) 'height) => '((0 3)))))
       (list frozen-engine gerbil-ascent-make-engine)))))
