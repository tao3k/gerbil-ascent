;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o)
        (only-in :gerbil-ascent/program/scheme-query make-relational-solution)
        (only-in :std/test check-equal? check-exception test-suite test-case)
        (only-in :gerbil-ascent/program/interface
                 relational-op-function relational-op-fix
                 relational-op-union relational-op-project
                 relational-op-join relational-op-source
                 relational-op-fragment relational-compose relational-open-session
                 relational-session-run relational-session-replace-sources!
                 relational-prepare-query relational-prepare-queries relational-query
                 relational-op-apply
                 relational-op-select-eq relational-op-flatmap
                 relational-op-open-retained relational-op-retained-rows
                 relational-op-retained-input-label
                 relational-op-retained-append!
                 relational-op-retained-replace!
                 relational-op-retained-replace-sources!))

(export scheme-operator-retained-test)

(def (reachability edge)
  (let (step
        (relational-op-function
         2 (lambda (path)
             (relational-op-project
              (relational-op-join path edge 1 0) '(0 3)))))
    (relational-op-fix
     2 (lambda (path)
         (relational-op-union edge
                              (relational-op-apply step path))))))

(def closure
  (relational-op-function 2 (lambda (edge) (reachability edge))))

(def (nested-reachability edge)
  (relational-op-fix
   2 (lambda (outer)
       (relational-op-fix
        2 (lambda (inner)
            (relational-op-union
             edge
             (relational-op-union
              outer
              (relational-op-project
               (relational-op-join inner edge 1 0) '(0 3)))))))))

;;; Deliberately independent finite graph model; the rule planner and
;;; operator interpreter are not called for expected values.
(def (finite-closure edges)
  (let (matrix (make-vector 9 #f))
    (for-each
     (lambda (edge)
       (vector-set! matrix (+ (* 3 (car edge)) (cadr edge)) #t))
     edges)
    (for-each
     (lambda (pivot)
       (for-each
        (lambda (from)
          (for-each
           (lambda (to)
             (when (and (vector-ref matrix (+ (* 3 from) pivot))
                        (vector-ref matrix (+ (* 3 pivot) to)))
               (vector-set! matrix (+ (* 3 from) to) #t)))
           '(0 1 2)))
        '(0 1 2)))
     '(0 1 2))
    (let (rows [])
      (for-each
       (lambda (from)
         (for-each
          (lambda (to)
            (when (vector-ref matrix (+ (* 3 from) to))
              (set! rows (cons (list from to) rows))))
          '(0 1 2)))
       '(0 1 2))
      rows)))

(def (same-rows? actual expected)
  (and (= (length actual) (length expected))
       (andmap (lambda (row) (if (member row expected) #t #f)) actual)))

(def (difference left right)
  (filter (lambda (row) (not (member row right))) left))

(def (mask-edges mask possible)
  (let loop ((rest possible) (bit 1) (rows []))
    (if (null? rest)
      (reverse rows)
      (loop (cdr rest) (* bit 2)
            (if (zero? (bitwise-and mask bit)) rows
              (cons (car rest) rows))))))

(def scheme-operator-retained-test
  (test-suite "retained first-class relational operators"
    (test-case "prepared views follow completed transactions and own duplicate rows"
      (let* ((edge (relational-op-source 'edge 2 '((0 1) (1 2))))
             (fragment (relational-op-fragment (reachability edge) 'reach))
             (labels (list 'reach 'edge 'reach))
             (view (relational-prepare-queries fragment labels))
             (read-edge (relational-prepare-query fragment 'edge))
             (session (relational-open-session
                        (relational-compose (list fragment) 32 128 256)))
             (first (relational-session-run session))
             (before (view first)))
        (check-equal? (same-rows? (car before) (finite-closure '((0 1) (1 2)))) #t)
        (check-equal? (cadr before) (read-edge first))
        (check-equal? (car before) (caddr before))
        (set-car! labels 'unknown)
        (set-car! (car (car before)) 99)
        (check-equal? (same-rows? (caddr before) (finite-closure '((0 1) (1 2)))) #t)
        (check-equal? (same-rows? (car (view first)) (finite-closure '((0 1) (1 2)))) #t)
        (let* ((next (relational-session-replace-sources!
                      session fragment (list (cons 'edge '((2 0))))))
               (after (view next)))
          (check-equal? (same-rows? (car after) (finite-closure '((2 0)))) #t)
          (check-equal? (cadr after) '((2 0)))
          (check-equal? (read-edge first) '((0 1) (1 2)))
          (check-exception
           (relational-session-replace-sources!
            session fragment (list (cons 'edge '((0 2))) (cons 'unknown '()))) true)
          (check-equal? (view (relational-session-run session)) after)
          (check-equal? (read-edge first) (relational-query first fragment 'edge)))
        (check-exception (relational-prepare-queries fragment '(edge unknown)) true)
        (let* ((other (relational-op-fragment
                       (relational-op-source 'edge 2 '((2 1))) 'reach))
               (other-solution
                (relational-session-run
                 (relational-open-session
                  (relational-compose (list other) 32 128 256)))))
          ;; Identical public labels do not substitute a different fragment's handle.
          (check-exception (read-edge other-solution) true))))
    (test-case "query preparation is lazy and completion precedes observation"
      (let* ((fragment (relational-op-fragment
                        (relational-op-source 'edge 1 '((1))) 'out))
             (view (relational-prepare-queries fragment '(out out)))
             (empty-view (relational-prepare-queries fragment '()))
             (calls 0)
             (partial (make-relational-solution
                       (.o (finished #f)
                           (rows-of (lambda (_name) (set! calls (+ calls 1)) '((7))))))))
        (check-equal? calls 0)
        (check-exception (view partial) true)
        (check-exception (empty-view partial) true)
        (check-equal? calls 0)
        (check-exception (view #f) true)
        (let* ((complete (make-relational-solution
                         (.o (finished #t)
                             (rows-of (lambda (_name)
                                        (set! calls (+ calls 1)) '((7))))))))
          (check-equal? (empty-view complete) '())
          (check-equal? calls 0)
          (check-equal? (view complete) '(((7)) ((7))))
          (check-equal? calls 2))))
    (test-case "all finite graphs survive append, duplicate and withdrawal"
      (let* ((possible '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)))
             (retained
              (relational-op-open-retained closure '() 32 128 256))
             (prior '()))
        (for-each
         (lambda (mask)
           (let* ((before (mask-edges mask possible))
                  (base (finite-closure before))
                  (grown (finite-closure (cons '(0 1) before)))
                  (old (relational-op-retained-rows retained)))
             (check-equal? (same-rows? old prior) #t)
             (let-values (((previous current added removed)
                           (relational-op-retained-replace! retained before)))
               (check-equal? (same-rows? previous prior) #t)
               (check-equal? (same-rows? current base) #t)
               (check-equal? (same-rows? added (difference base prior)) #t)
               (check-equal? (same-rows? removed (difference prior base)) #t))
             (check-equal?
              (same-rows? (relational-op-retained-rows retained) base) #t)
             (let-values (((previous current added)
                           (relational-op-retained-append!
                            retained '(0 1))))
               (check-equal? (same-rows? previous base) #t)
               (check-equal? (same-rows? current grown) #t)
               (check-equal?
                (same-rows? added (difference grown base)) #t))
             (let-values (((previous current added)
                           (relational-op-retained-append!
                            retained '(0 1))))
               (check-equal? (same-rows? previous grown) #t)
               (check-equal? (same-rows? current grown) #t)
               (check-equal? added '()))
             (let-values (((previous current added removed)
                           (relational-op-retained-replace!
                            retained before)))
               (check-equal? (same-rows? previous grown) #t)
               (check-equal? (same-rows? current base) #t)
               (check-equal? (same-rows? added (difference base grown)) #t)
               (check-equal?
                (same-rows? removed (difference grown base)) #t))
             (check-equal? (same-rows? old prior) #t)
             (set! prior base)
             (when (zero? (modulo (+ mask 1) 2))
               (displayln "PROGRESS retained graphs " (+ mask 1) "/64")
               (force-output))))
         (iota 64))))
    (test-case "fixed captured source and finite mapping share retained solve"
      (let* ((transformer
              (relational-op-function
               2 (lambda (input)
                   (relational-op-select-eq
                    (relational-op-flatmap
                     (relational-op-project
                      (relational-op-union
                       input (relational-op-source 'fixed 2 '((2 9))))
                      '(0))
                     1 '(((1) (a)) ((2) (b)) ((3) (a))))
                    0 'a))))
             (retained
              (relational-op-open-retained transformer '((1 4))
                                           16 32 64))
             (old (relational-op-retained-rows retained)))
        (check-equal? old '((a)))
        (let-values (((_before after added)
                      (relational-op-retained-append! retained '(3 7))))
          (check-equal? after '((a)))
          (check-equal? added '()))
        (let-values (((_before after added removed)
                      (relational-op-retained-replace! retained '())))
          (check-equal? after '())
          (check-equal? added '())
          (check-equal? removed '((a))))
        (check-equal? old '((a)))))
    (test-case "batch replacement commits both sources and nested closure"
      (let* ((possible '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)))
             (transformer
              (relational-op-function
               2 (lambda (input)
                   (nested-reachability
                    (relational-op-union
                     input (relational-op-source 'other 2 '()))))))
             (retained
              (relational-op-open-retained transformer '() 32 128 256))
             (input (relational-op-retained-input-label retained))
             (prior '()))
        (for-each
         (lambda (mask)
           (let* ((left (mask-edges mask possible))
                  (right (mask-edges (bitwise-xor mask 21) possible))
                  (before (relational-op-retained-rows retained))
                  (expected (finite-closure (append left right))))
             (check-equal? (same-rows? before prior) #t)
             (let-values (((old after added removed)
                           (relational-op-retained-replace-sources!
                            retained
                            (list (cons input left) (cons 'other right)))))
               (check-equal? old before)
               (check-equal? (same-rows? after expected) #t)
               (check-equal? (same-rows? added (difference expected before))
                             #t)
               (check-equal? (same-rows? removed
                                        (difference before expected)) #t))
             (check-equal? (same-rows? (relational-op-retained-rows retained)
                                      expected) #t)
             (set! prior expected)
             (when (zero? (modulo (+ mask 1) 2))
               (displayln "PROGRESS nested source cuts " (+ mask 1)
                          "/64")
               (force-output))))
         (iota 64))))
    (test-case "failed batch preserves all sources and the prior result"
      (let* ((transformer
              (relational-op-function
               2 (lambda (input)
                   (reachability
                    (relational-op-union
                     input (relational-op-source 'other 2 '((1 2))))))))
             (retained
              (relational-op-open-retained transformer '((0 1))
                                           3 64 256))
             (input (relational-op-retained-input-label retained))
             (first (relational-op-retained-rows retained)))
        (check-equal? (same-rows? first '((0 1) (1 2) (0 2))) #t)
        (check-exception
         (relational-op-retained-replace-sources!
          retained (list (cons input '((0 1) (1 2)))
                         (cons 'other '((2 0) (2 1))))) true)
        (check-equal? (same-rows? (relational-op-retained-rows retained)
                                  first) #t)
        (check-exception
         (relational-op-retained-replace-sources!
          retained (list (cons input '((0 1)))
                         (cons 'other '((0 1 2))))) true)
        (check-exception
         (relational-op-retained-replace-sources!
          retained (list (cons input '((0 1)))
                         (cons input '()))) true)
        (let-values (((old after added removed)
                      (relational-op-retained-replace-sources!
                       retained (list (cons input '())))))
          (check-equal? (same-rows? old first) #t)
          (check-equal? after '((1 2)))
          (check-equal? added '())
          (check-equal? (same-rows? removed '((0 1) (0 2))) #t))))
    (test-case "invalid or over-budget update preserves last result"
      (let* ((retained
              (relational-op-open-retained closure '((0 1))
                                           8 32 64))
             (first (relational-op-retained-rows retained)))
        (check-exception
         (relational-op-retained-append! retained '(invalid)) true)
        (check-equal? (same-rows? (relational-op-retained-rows retained)
                                  first) #t)
        (check-exception
         (relational-op-retained-replace! retained '((0 1 2))) true)
        (check-equal? (same-rows? (relational-op-retained-rows retained)
                                  first) #t)
        (let-values (((_before after added)
                      (relational-op-retained-append! retained '(1 2))))
          (check-equal? (same-rows? after '((0 1) (1 2) (0 2))) #t)
          (check-equal? (same-rows? added '((1 2) (0 2))) #t))
        (check-equal? first '((0 1)))
        (set-car! (car first) 99)
        (check-equal?
         (same-rows? (relational-op-retained-rows retained)
                     '((0 1) (1 2) (0 2))) #t)))
    (test-case "failed output budget does not publish an insertion"
      (let (retained
            (relational-op-open-retained closure '((0 1)) 8 8 2))
        (check-exception
         (relational-op-retained-append! retained '(1 2)) true)
        (check-equal? (relational-op-retained-rows retained) '((0 1)))
        (let-values (((before after added removed)
                      (relational-op-retained-replace!
                       retained '((0 1)))))
          (check-equal? before '((0 1)))
          (check-equal? after '((0 1)))
          (check-equal? added '())
          (check-equal? removed '()))))))
