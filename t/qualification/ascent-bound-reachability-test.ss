;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/iter for in-range)
        (only-in :gerbil-ascent/core/execution-control current-ascent-execution-control)
        (only-in :gerbil-ascent/program/api gerbil-ascent-open-bound-reachability
                 gerbil-ascent-bound-reachability-edit gerbil-ascent-bound-reachability-query
                 gerbil-ascent-bound-reachability-path gerbil-ascent-bound-reachability-verify))
(export ascent-bound-reachability-test)

(def (graph-rows mask)
  (let (rows [])
    (for (i (in-range 9))
      (when (bit-set? i mask)
        (set! rows (cons (list (quotient i 3) (remainder i 3)) rows))))
    rows))

;; Boolean matrix closure has no hash index, worklist, or bound seed rewrite.
(def (oracle rows)
  (let (matrix (make-vector 9 #f))
    (def (key from to) (+ (* from 3) to))
    (for-each (lambda (row) (vector-set! matrix (apply key row) #t)) rows)
    (for (k (in-range 3))
      (for (a (in-range 3))
        (for (b (in-range 3))
          (when (and (vector-ref matrix (key a k)) (vector-ref matrix (key k b)))
            (vector-set! matrix (key a b) #t)))))
    (lambda (a b) (vector-ref matrix (key a b)))))

(def (valid-path? path rows from to)
  (and (pair? (cdr path)) (= (car path) from)
       (let walk ((rest path))
         (if (null? (cdr rest)) (= (car rest) to)
           (and (member (list (car rest) (cadr rest)) rows) (walk (cdr rest)))))))

(def (compare graph rows)
  (let (expected (oracle rows))
    (for (from (in-range 3))
      (for (to (in-range 3))
        (let-values (((proof edges) (gerbil-ascent-bound-reachability-query graph from to)))
          (unless (and (eq? (and proof #t) (expected from to))
                       (or (not proof)
                           (and (> edges 0)
                                (gerbil-ascent-bound-reachability-verify graph proof)
                                (valid-path? (gerbil-ascent-bound-reachability-path proof) rows from to))))
            (error "bound reachability disagrees with the matrix oracle" from to rows)))))))

(def (witness graph from to)
  (let-values (((proof _) (gerbil-ascent-bound-reachability-query graph from to))) proof))

(def ascent-bound-reachability-test
  (test-suite "Bound directed reachability at exact graph versions"
    (test-case "Every three-vertex graph and each one-edge toggle match matrix closure"
      (for (mask (in-range 512))
        (let* ((rows (graph-rows mask)) (before (gerbil-ascent-open-bound-reachability rows)))
          (compare before rows)
          (for (i (in-range 9))
            (let ((from (quotient i 3)) (to (remainder i 3)) (insert? (not (bit-set? i mask))))
              (let-values (((after buckets _) (gerbil-ascent-bound-reachability-edit before from to insert?)))
                (unless (= buckets 2) (error "single edit changed the wrong number of buckets"))
                (compare after (graph-rows (bitwise-xor mask (arithmetic-shift 1 i))))))))))

    (test-case "Versions, independent branches, no-op edits, and mutable exports stay isolated"
      (let* ((rows (list (list 0 1) (list 1 2) (list 2 0) (list 0 1)))
             (before (gerbil-ascent-open-bound-reachability rows edge-limit: 3))
             (old (witness before 0 2)))
        (set-car! (car rows) 99)
        (set-car! (gerbil-ascent-bound-reachability-path old) 99)
        (let-values (((removed rebuilt reads) (gerbil-ascent-bound-reachability-edit before 1 2 #f))
                     ((noop untouched _) (gerbil-ascent-bound-reachability-edit before 0 1 #t)))
          (check rebuilt => 2)
          (check reads => 2)
          (check untouched => 0)
          (check (witness removed 0 2) => #f)
          (check (gerbil-ascent-bound-reachability-verify before old) => #t)
          (check (gerbil-ascent-bound-reachability-verify removed old) => #f)
          (check (gerbil-ascent-bound-reachability-verify noop old) => #f)
          (check (gerbil-ascent-bound-reachability-path old) => '(0 1 2))
          (check (gerbil-ascent-bound-reachability-path (witness before 0 0)) => '(0 1 2 0))
          (let-values (((restored _buckets _reads) (gerbil-ascent-bound-reachability-edit removed 1 2 #t)))
            (let (new (witness restored 0 2))
              (check (gerbil-ascent-bound-reachability-verify restored new) => #t)
              (check (gerbil-ascent-bound-reachability-verify before new) => #f))))))

    (test-case "A canceled or exhausted operation leaves both graph and witness usable"
      (let* ((before (gerbil-ascent-open-bound-reachability '((0 1) (0 2) (1 3)) edge-limit: 3))
             (old (witness before 0 3))
             (charge 0))
        (check-exception (gerbil-ascent-bound-reachability-edit before 0 1 #f work-limit: 2) error?)
        (check-exception (gerbil-ascent-bound-reachability-edit before 2 3 #t) error?)
        (check-exception (gerbil-ascent-bound-reachability-query before 0 3 work-limit: 1) error?)
        (check-exception (gerbil-ascent-bound-reachability-verify before old work-limit: 0) error?)
        (check-exception (gerbil-ascent-bound-reachability-path old work-limit: 1) error?)
        (parameterize ((current-ascent-execution-control
                        (lambda (cost facts)
                          (set! charge (+ charge cost))
                          (when (= charge 1) (error "canceled for test")))))
          (check-exception (gerbil-ascent-bound-reachability-edit before 0 1 #f) error?))
        (check charge => 1)
        (let (prepared? #f)
          (parameterize ((current-ascent-execution-control
                          (lambda (cost _facts)
                            (if (positive? cost) (set! prepared? #t)
                              (when prepared? (error "canceled at publication"))))))
            (check-exception (gerbil-ascent-bound-reachability-edit before 0 1 #f) error?))
          (check prepared? => #t))
        (check (gerbil-ascent-bound-reachability-verify before old) => #t)
        (check (gerbil-ascent-bound-reachability-path (witness before 0 3)) => '(0 1 3))))

    (test-case "Input limits, exact integers, and new endpoint IDs are enforced"
      (check-exception (gerbil-ascent-open-bound-reachability '((0 1) (1 2)) edge-limit: 1) error?)
      (check-exception (gerbil-ascent-open-bound-reachability '((0 1) (0 1)) work-limit: 1) error?)
      (check-exception (gerbil-ascent-open-bound-reachability '((1.0 0))) error?)
      (check-exception (gerbil-ascent-open-bound-reachability '((1 0 3))) error?)
      (let (cyclic (list '(1 2)))
        (set-cdr! cyclic cyclic)
        (check-exception (gerbil-ascent-open-bound-reachability cyclic) error?))
      (let (before (gerbil-ascent-open-bound-reachability [] edge-limit: 1))
        (check (witness before -5 -5) => #f)
        (let-values (((after _buckets _reads) (gerbil-ascent-bound-reachability-edit before -5 -5 #t)))
          (check (gerbil-ascent-bound-reachability-path (witness after -5 -5)) => '(-5 -5)))))

    (test-case "A meeting supplies both path halves and separated roots never meet"
      (let* ((rows '((0 1) (0 2) (1 3) (3 4) (4 5) (5 6) (7 8) (8 7) (9 2)))
             (graph (gerbil-ascent-open-bound-reachability rows))
             (proof (witness graph 0 6)))
        (check (gerbil-ascent-bound-reachability-path proof) => '(0 1 3 4 5 6))
        (check (gerbil-ascent-bound-reachability-verify graph proof) => #t)
        (check (witness graph 0 8) => #f)
        (check (gerbil-ascent-bound-reachability-path (witness graph 7 7)) => '(7 8 7))
        ;; This cut meets on the ninth work step. The remaining suffix still
        ;; has to pass the budget and cancellation check before publication.
        (check-exception (gerbil-ascent-bound-reachability-query graph 0 6 work-limit: 9) error?)
        (let (charged 0)
          (parameterize ((current-ascent-execution-control
                          (lambda (work _facts)
                            (set! charged (+ charged work))
                            (when (= charged 10) (error "canceled during witness stitch")))))
            (check-exception (gerbil-ascent-bound-reachability-query graph 0 6) error?))
          (check charged => 10))
        (check (gerbil-ascent-bound-reachability-verify graph proof) => #t)
        (let-values (((direct reads) (gerbil-ascent-bound-reachability-query graph 0 2 work-limit: 1)))
          (check reads => 1)
          (check (gerbil-ascent-bound-reachability-path direct) => '(0 2)))))))
