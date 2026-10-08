;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite test-case)
        (only-in :clan/poo/object .o .ref)
        (only-in :gerbil-ascent/program/objects
                 gerbil-ascent-relation gerbil-ascent-program
                 gerbil-ascent-atom gerbil-ascent-rule gerbil-ascent-variable)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-set-storage-provider)
        (only-in :gerbil-ascent/t/qualification/ascent-binding-reference-evaluate
                 ascent-reference-evaluate-program))
(export ascent-source-admission-test)

(def (program rows width (storage gerbil-ascent-set-storage-provider)
              (predicates []) (input-limit 16) (output-limit 16))
  (gerbil-ascent-program
   (list (gerbil-ascent-relation 'source width rows
                                gerbil-ascent-hash-index-provider storage predicates))
   [] input-limit 16 output-limit))

(def (rows-of result)
  ((.ref result 'rows-of) 'source))

(def (outcome solve input)
  (with-catch (lambda (failure) (list 'error (error-message failure)))
    (lambda () (rows-of (solve input)))))

(def (check-failure input message)
  (check-equal? (outcome gerbil-ascent-evaluate-program input) (list 'error message))
  (check-equal? (outcome ascent-reference-evaluate-program input) (list 'error message)))

(def (projection output (derived-limit 16) (output-limit 16))
  (let (variable (gerbil-ascent-variable 'x))
    (gerbil-ascent-program
     (list (gerbil-ascent-relation 'source 1 '((1) (2))) output)
     (list (gerbil-ascent-rule
            (list (gerbil-ascent-atom 'output (list variable)))
            (list (gerbil-ascent-atom 'source (list variable)))))
     16 derived-limit output-limit)))

(def ascent-source-admission-test
  (test-suite "ASCENT default Set source admission"
    (test-case "wide Set sources retain ordered duplicates and budgets"
      (let* ((first-row (iota 128))
             (last-row (reverse first-row))
             (source-rows (list first-row first-row last-row))
             (input (program source-rows 128 gerbil-ascent-set-storage-provider [] 3 3)))
        (check-equal? (rows-of (gerbil-ascent-evaluate-program input)) source-rows)
        (check-equal? (rows-of (ascent-reference-evaluate-program input)) source-rows)
        (check-failure (program source-rows 128 gerbil-ascent-set-storage-provider [] 2 3)
                       "ASCENT source fact budget exceeded")))
    (test-case "identity storage preserves duplicate source order and counts"
      (let* ((rows '((1 2) (1 2) (2 3)))
             (input (program rows 2 gerbil-ascent-set-storage-provider [] 3 3)))
        (check-equal? (rows-of (gerbil-ascent-evaluate-program input)) rows)
        (check-equal? (rows-of (ascent-reference-evaluate-program input)) rows)))
    (test-case "source rows mutated after declaration are checked again"
      (let* ((row (list 1 2)) (input (program (list row) 2)))
        (set-cdr! row [])
        (check-failure input "invalid ASCENT relation row")))
    (test-case "duplicate facts still consume the source budget"
      (check-failure
       (program '((1) (1) (2)) 1 gerbil-ascent-set-storage-provider [] 2 16)
       "ASCENT source fact budget exceeded"))
    (test-case "field callbacks retain both source and stored-row checks"
      (let* ((calls 0)
             (predicate (lambda (_) (set! calls (+ calls 1)) #t))
             (input (program '((1 2) (3 4)) 2
                             gerbil-ascent-set-storage-provider
                             (list predicate predicate))))
        (set! calls 0)
        (check-equal? (rows-of (ascent-reference-evaluate-program input)) '((1 2) (3 4)))
        (check-equal? calls 8)
        (set! calls 0)
        (check-equal? (rows-of (gerbil-ascent-evaluate-program input)) '((1 2) (3 4)))
        (check-equal? calls 8)))
    (test-case "a stateful field predicate still fails its second check"
      (let* ((active? #f) (calls 0)
             (predicate
              (lambda (_)
                (if active?
                  (begin (set! calls (+ calls 1)) (= calls 1))
                  #t)))
             (input (program '((1)) 1 gerbil-ascent-set-storage-provider
                             (list predicate))))
        (set! active? #t)
        (set! calls 0)
        (check-equal? (outcome ascent-reference-evaluate-program input)
                      '(error "ASCENT relation field type mismatch"))
        (check-equal? calls 2)
        (set! calls 0)
        (check-equal? (outcome gerbil-ascent-evaluate-program input)
                      '(error "ASCENT relation field type mismatch"))
        (check-equal? calls 2)))
    (test-case "an inherited custom Provider still receives every source row"
      (let* ((calls 0)
             (storage
              (.o (:: @ gerbil-ascent-set-storage-provider)
                  (.extend-rows
                   (lambda (_state _all _pending row _budget)
                     (set! calls (+ calls 1))
                     (list row)))))
             (input (program '((1) (2)) 1 storage)))
        (check-equal? (rows-of (ascent-reference-evaluate-program input)) '((1) (2)))
        (check-equal? calls 2)
        (set! calls 0)
        (check-equal? (rows-of (gerbil-ascent-evaluate-program input)) '((1) (2)))
        (check-equal? calls 2)))
    (test-case "custom Provider row widths are still checked"
      (let (storage
            (.o (:: @ gerbil-ascent-set-storage-provider)
                (.extend-rows
                 (lambda (_state _all _pending _row _budget) '((1))))))
        (check-failure (program '((1 2)) 2 storage)
                       "invalid ASCENT storage provider row")))
    (test-case "custom Provider expansion retains the materialized budget"
      (let (storage
            (.o (:: @ gerbil-ascent-set-storage-provider)
                (.extend-rows
                 (lambda (_state _all _pending _row _budget) '((1) (2))))))
        (check-failure (program '((1)) 1 storage [] 1 1)
                       "ASCENT source fact budget exceeded")))
    (test-case "nullary Set sources and derived facts retain their multiplicities"
      (let (input
            (gerbil-ascent-program
             (list (gerbil-ascent-relation 'source 0 '(() ()))
                   (gerbil-ascent-relation 'output 0 []))
             (list (gerbil-ascent-rule
                    (list (gerbil-ascent-atom 'output []))
                    (list (gerbil-ascent-atom 'source []))))
             2 1 3))
        (for-each
         (lambda (solve)
           (let (result (solve input))
             (check-equal? (rows-of result) '(() ()))
             (check-equal? ((.ref result 'rows-of) 'output) '(()))))
         (list ascent-reference-evaluate-program gerbil-ascent-evaluate-program))))
    (test-case "direct staging retains derived and total fact budgets"
      (check-failure (projection (gerbil-ascent-relation 'output 1 []) 1 16)
                     "ASCENT derived fact budget exceeded")
      (check-failure (projection (gerbil-ascent-relation 'output 1 []) 16 3)
                     "ASCENT output fact budget exceeded"))
    (test-case "derived field callbacks retain their second validation"
      (let* ((calls 0)
             (predicate (lambda (_) (set! calls (+ calls 1)) #t))
             (input
              (projection
               (gerbil-ascent-relation 'output 1 []
                                      gerbil-ascent-hash-index-provider
                                      gerbil-ascent-set-storage-provider
                                      (list predicate)))))
        (for-each
         (lambda (solve)
           (set! calls 0)
           (check-equal? ((.ref (solve input) 'rows-of) 'output) '((1) (2)))
           (check-equal? calls 4))
         (list ascent-reference-evaluate-program gerbil-ascent-evaluate-program))))
    (test-case "derived custom storage still receives each candidate"
      (let* ((calls 0)
             (storage
              (.o (:: @ gerbil-ascent-set-storage-provider)
                  (.extend-rows
                   (lambda (_state _all _pending row _budget)
                     (set! calls (+ calls 1))
                     (list row)))))
             (input (projection (gerbil-ascent-relation
                                'output 1 [] gerbil-ascent-hash-index-provider storage))))
        (for-each
         (lambda (solve)
           (set! calls 0)
           (check-equal? ((.ref (solve input) 'rows-of) 'output) '((1) (2)))
           (check-equal? calls 2))
         (list ascent-reference-evaluate-program gerbil-ascent-evaluate-program))))))
