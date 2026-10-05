;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite check-equal?)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :clan/poo/object .o .ref)
        (only-in :gerbil-ascent/table/funs gerbil-ascent-index-build gerbil-ascent-index-extend!)
        (only-in :gerbil-ascent/table/access gerbil-ascent-physical-index-build
                 gerbil-ascent-physical-index-extend! gerbil-ascent-physical-index-rows)
        (rename-in (only-in :gerbil-ascent/t/qualification/ascent-index-reference-funs
                           gerbil-ascent-index-build gerbil-ascent-index-extend!)
                   (gerbil-ascent-index-build old-build)
                   (gerbil-ascent-index-extend! old-extend!))
        (only-in :gerbil-ascent/program/interface gerbil-ascent-program gerbil-ascent-relation
                 gerbil-ascent-variable gerbil-ascent-atom gerbil-ascent-rule)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/core/rule-semantics gerbil-ascent-bind-row)
        (only-in :gerbil-ascent/t/qualification/ascent-index-reference-evaluate
                 ascent-index-reference-make-engine ascent-index-reference-evaluate-program))
(export ascent-index-lifecycle-test)
(def (indexed-program width provider)
  (let* ((x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y))
         (a (lambda (name terms) (gerbil-ascent-atom name terms))))
    (gerbil-ascent-program
     (list (gerbil-ascent-relation 'left 1 '((0) (1)))
           (gerbil-ascent-relation 'right 2
            (map (lambda (n) (list (modulo n 2) n)) (iota width)) provider)
           (gerbil-ascent-relation 'out 2 []))
     (list (gerbil-ascent-rule (list (a 'out (list x y)))
                              (list (a 'left (list x)) (a 'right (list x y)))))
     256 256 512)))
(def (rows result) ((.ref result 'rows-of) 'out))

;; An exhaustive assignment model, independent of the sequential native binder.
;; Every candidate assignment is total over x/y; constraints are simultaneous.
(def (binding-products choices width)
  (if (zero? width) (list [])
      (apply append
             (map (lambda (value)
                    (map (lambda (tail) (cons value tail))
                         (binding-products choices (- width 1)))) choices))))
(def (binding-assignments)
  (map (lambda (values) (map cons '(x y) values))
       (binding-products '(0 #f) 2)))
(def (binding-set rows)
  (let loop ((rest rows) (seen []))
    (if (null? rest) seen
        (loop (cdr rest) (if (member (car rest) seen) seen (cons (car rest) seen))))))
(def (binding-term-satisfied? term value assignment)
  (case (car term)
    ((wildcard) #t)
    ((literal) (equal? (cdr term) value))
    (else (equal? (cdr (assq (cdr term) assignment)) value))))
(def (binding-model terms row input)
  (filter
   (lambda (assignment)
     (and (andmap (lambda (entry)
                    (equal? (cdr entry) (cdr (assq (car entry) assignment)))) input)
          (andmap (lambda (pair)
                    (binding-term-satisfied? (car pair) (cdr pair) assignment))
                  (map cons terms row))))
   (binding-assignments)))

(def ascent-index-lifecycle-test
  (test-suite "Complete index lifecycle"
    (poo-flow-test-case "ordinary atom binding agrees with exhaustive simultaneous assignments"
      (let* ((choices (list (cons 'variable 'x) (cons 'variable 'y)
                            (cons 'literal 0) (cons 'literal #f) (cons 'wildcard #f)))
             (inputs (map (lambda (values)
                            (filter (lambda (entry) (not (eq? (cdr entry) 'unbound)))
                                    (map cons '(x y) values)))
                          (binding-products '(unbound 0 #f) 2)))
             (decisions 0))
        (for-each
         (lambda (width)
           (for-each
            (lambda (terms)
              (for-each
               (lambda (row)
                 (for-each
                  (lambda (input)
                    (let* ((solutions (binding-model terms row input))
                           (output (gerbil-ascent-bind-row terms row input)))
                      (set! decisions (+ decisions 1))
                      (check-equal? (and output #t) (pair? solutions))
                      (when output
                        (check-equal?
                         (ormap (lambda (assignment)
                                  (andmap (lambda (entry)
                                            (equal? (cdr entry)
                                                    (cdr (assq (car entry) assignment)))) output))
                                solutions) #t)
                        (for-each (lambda (entry)
                                    (check-equal? (assq (car entry) output) entry)) input)))) inputs))
               (binding-products '(0 #f) width)))
            (binding-products choices width))) '(0 1 2 3))
        (check-equal? decisions 9999)))
    (poo-flow-test-case "known-column buckets retain all simultaneous atom solutions"
      (let* ((choices (list (cons 'variable 'x) (cons 'variable 'y)
                            (cons 'literal 0) (cons 'literal #f) (cons 'wildcard #f)))
             (input (list (cons 'x 0)))
             (source (apply append (map (lambda (_) (binding-products '(0 #f) 3)) (iota 5)))))
        (for-each
         (lambda (terms)
           (let* ((known (filter (lambda (column)
                                   (let (term (list-ref terms column))
                                     (or (eq? (car term) 'literal)
                                         (and (eq? (car term) 'variable)
                                              (assq (cdr term) input))))) '(0 1 2)))
                  (key (map (lambda (column)
                              (let (term (list-ref terms column))
                                (if (eq? (car term) 'literal) (cdr term)
                                    (cdr (assq (cdr term) input))))) known))
                  (physical (gerbil-ascent-physical-index-build
                             gerbil-ascent-hash-index-provider source known))
                  (bucket (gerbil-ascent-physical-index-rows
                           gerbil-ascent-hash-index-provider physical key))
                  (expected (binding-set
                             (filter (lambda (row) (pair? (binding-model terms row input))) source)))
                  (actual (binding-set
                           (filter (lambda (row) (gerbil-ascent-bind-row terms row input)) bucket))))
             (check-equal? (list-sort (lambda (a b) (string<? (object->string a) (object->string b))) actual)
                           (list-sort (lambda (a b) (string<? (object->string a) (object->string b))) expected))))
         (binding-products choices 3))))
    (poo-flow-test-case "physical single-column keys preserve equality and incremental bucket order"
      (let* ((source (list (list #f 0) (list '() 1) (list "same" 2)
                           (list (string-copy "same") 3) (list '(a b) 4)))
             (batch (list (list (string-copy "same") 5) (list #f 6)))
             (provider gerbil-ascent-hash-index-provider))
        (for-each
         (lambda (columns)
           (let ((reference (old-build source columns))
                 (physical (gerbil-ascent-physical-index-build provider source columns)))
             (old-extend! reference batch columns)
             (gerbil-ascent-physical-index-extend! provider physical batch columns)
             (for-each
              (lambda (row)
                (let (key (map (lambda (column) (list-ref row column)) columns))
                  (check-equal? (gerbil-ascent-physical-index-rows provider physical key)
                                (hash-get reference key))))
              (append source batch))
             (when (pair? columns)
               (check-equal? (gerbil-ascent-physical-index-rows
                              provider physical (map (lambda (_) 'absent) columns)) []))))
         '((0) (1) (0 1) (1 0) (0 0) ()))))
    (poo-flow-test-case "all ordered subsets and arbitrary columns preserve keys and bucket order"
      (let (source (map (lambda (n) (map (lambda (c) (modulo (+ n c) 3)) (iota 8))) (iota 40)))
        (for-each
         (lambda (columns)
           (let ((old (old-build source columns))
                 (new (gerbil-ascent-index-build source columns)))
             (for-each
              (lambda (row)
                (let (key (map (lambda (c) (list-ref row c)) columns))
                  (check-equal? (hash-get new key) (hash-get old key)))) source)
             (let (batch (reverse (take source 5)))
               (old-extend! old batch columns)
               (gerbil-ascent-index-extend! new batch columns))
             (hash-for-each (lambda (key bucket) (check-equal? (hash-get new key) bucket)) old)))
         (append (map (lambda (bits)
                        (filter (lambda (c) (not (zero? (bitwise-and bits (arithmetic-shift 1 c))))) (iota 8)))
                      (iota 256))
                 '((7 0 4) (2 2 0) (7 7) ())))))
    (poo-flow-test-case "default index crosses threshold and extends without changing retained snapshots"
      (let* ((p (indexed-program 31 gerbil-ascent-hash-index-provider))
             (old (ascent-index-reference-make-engine p #t))
             (new (gerbil-ascent-make-engine p #t))
             (first-old ((.ref old '.run))) (first-new ((.ref new '.run))))
        (check-equal? (rows first-new) (rows first-old))
        (for-each
         (lambda (n)
           (for-each (lambda (engine) ((.ref engine '.append-source!) 'right (list (modulo n 2) n))) (list old new))
           (check-equal? (rows ((.ref new '.run))) (rows ((.ref old '.run)))))
         (iota 10 31))
        (check-equal? (length (rows first-new)) 31)
        (for-each (lambda (engine) ((.ref engine '.replace-source!) 'right '((0 99)))) (list old new))
        (check-equal? (rows ((.ref new '.run))) (rows ((.ref old '.run))))))
    (poo-flow-test-case "custom build extend lookup traces and superset candidates remain identical"
      (let* ((trace [])
             (provider (.o (:: @ gerbil-ascent-hash-index-provider)
                           (.build-index (lambda (rs cs) (set! trace (cons (list 'build rs cs) trace)) rs))
                           (.extend-index! (lambda (idx rs cs)
                                             (set! trace (cons (list 'extend rs cs) trace))
                                             (append (reverse rs) idx)))
                           (.lookup-index (lambda (idx key) (set! trace (cons (list 'lookup key) trace)) idx))))
             (p (indexed-program 40 provider)))
        (def (run make)
          (let (engine (make p #t))
            (let (first ((.ref engine '.run)))
              ((.ref engine '.append-source!) 'right '(1 41))
              (list (rows first) (rows ((.ref engine '.run)))))))
        (let* ((old (run ascent-index-reference-make-engine)) (old-trace trace))
          (set! trace [])
          (check-equal? (run gerbil-ascent-make-engine) old)
          (check-equal? trace old-trace))))
    (poo-flow-test-case "custom improper lookup rows retain the exact error boundary"
      (let* ((provider (.o (:: @ gerbil-ascent-hash-index-provider)
                           (.lookup-index (lambda (_index _key) (cons '(0 1) 'bad)))))
             (p (indexed-program 40 provider)))
        (def (outcome solve)
          (with-catch (lambda (failure) (error-message failure)) (lambda () (solve p) 'success)))
        (check-equal? (outcome gerbil-ascent-evaluate-program)
                      (outcome ascent-index-reference-evaluate-program))
        (check-equal? (outcome gerbil-ascent-evaluate-program)
                      "ASCENT index provider returned non-list rows")))))
