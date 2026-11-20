;;; -*- Gerbil -*-
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Native production Session measurements, not a message-to-row conversion.
(import :std/test
        (only-in :std/list/list append-map)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/func
                 gerbil-ascent-program gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-rule gerbil-ascent-atom)
        (only-in :gerbil-ascent/program/session
                 gerbil-ascent-session-run gerbil-ascent-session-replace-source!)
        (only-in :gerbil-ascent/program/actor-session
                 gerbil-ascent-open-actor-session gerbil-ascent-session-state
                 gerbil-ascent-session-close!))
(export actor-million-oracle-test actor-million-state-test
        actor-million-query-test actor-million-recursive-test)

(def frequency
  (let (buffer (make-u64vector 1 0))
    (##get-monotonic-time-frequency! buffer 0)
    (let (value (u64vector-ref buffer 0))
      (unless (> value 0) (error "missing monotonic clock frequency"))
      value)))

(def (tick)
  (let (buffer (make-u64vector 1 0))
    (##get-monotonic-time! buffer 0)
    (u64vector-ref buffer 0)))

(def (nanoseconds start)
  (quotient (* (- (tick) start) 1000000000) frequency))

(def (receipt phase fields)
  (display "ACTOR-MILLION ")
  (write (cons (cons 'phase phase) fields))
  (newline)
  (force-output))

;; Disjoint chains give a closed-form oracle independent of the rule engine.
(def (edges groups width offset)
  (append-map
    (lambda (group)
      (map (lambda (column)
             (let (left (+ offset (* group width) column)) (list left (+ left 1))))
           (iota (- width 1))))
    (iota groups)))

(def (output-count groups width)
  (quotient (* groups width (- width 1)) 2))

(def (declaration rows groups width recursive?)
  (let* ((x (gerbil-ascent-variable 'x))
         (y (gerbil-ascent-variable 'y))
         (z (gerbil-ascent-variable 'z))
         (edge (gerbil-ascent-atom 'edge (list x y)))
         (reach (gerbil-ascent-atom 'reach (list x y)))
         (base (gerbil-ascent-rule (list reach) (list edge)))
         (step (gerbil-ascent-rule
                 (list (gerbil-ascent-atom 'reach (list x z)))
                 (list reach (gerbil-ascent-atom 'edge (list y z)))))
         (input (* groups (- width 1)))
         (output (if recursive? (output-count groups width) input)))
    ;; Workload-specific declared ceilings; existing production defaults and
    ;; original performance gates are untouched. Exactly one VM processor.
    (gerbil-ascent-program
      (list (gerbil-ascent-relation 'edge 2 rows)
            (gerbil-ascent-relation 'reach 2 []))
      (if recursive? (list base step) (list base)) input output (+ input output))))

(def (open-session rows groups width recursive?)
  (let* ((start (tick))
         (program (declaration rows groups width recursive?)))
    (receipt 'declaration-ready (list (cons 'wall-ns (nanoseconds start))))
    (let* ((open (tick))
           (session (gerbil-ascent-open-actor-session program workers: 1)))
      (receipt 'session-open (list (cons 'wall-ns (nanoseconds open))))
      session)))

(def (verify rows groups width offset recursive?)
  (let ((seen (make-u8vector (* groups width width) 0))
        (expected (if recursive? (output-count groups width) (* groups (- width 1))))
        (count 0))
    (for-each
      (lambda (row)
        (unless (and (pair? row) (pair? (cdr row)) (null? (cddr row)))
          (error "invalid exported row" row))
        (let ((left (- (car row) offset)) (right (- (cadr row) offset)))
          (unless (and (exact-integer? left) (exact-integer? right)
                       (<= 0 left) (< left right) (< right (* groups width))
                       (= (quotient left width) (quotient right width))
                       (or recursive? (= right (+ left 1))))
            (error "row outside independent chain oracle" row))
          (let (index (+ (* left width) (remainder right width)))
            (unless (= (u8vector-ref seen index) 0) (error "duplicate exported row" row))
            (u8vector-set! seen index 1)))
        (set! count (+ count 1)))
      rows)
    (unless (= count expected) (error "incomplete exported relation" count expected))
    count))

(def (query session groups width offset recursive?)
  (let* ((start (tick))
         (result (gerbil-ascent-session-run session)))
    (unless (.ref result 'finished) (error "query did not finish"))
    (let* ((rows ((.ref result 'rows-of) 'reach))
           (query-ns (nanoseconds start)))
      (verify rows groups width offset recursive?)
      (values query-ns (nanoseconds start)))))

(def (report-samples phase input output samples wall cpu before)
  (let* ((after (##process-statistics))
         (ordered (list-sort < (f64vector->list samples)))
         (count (length ordered))
         (p95 (list-ref ordered (- (quotient (+ (* count 95) 99) 100) 1)))
         (collections (- (f64vector-ref after 6) (f64vector-ref before 6)))
         (allocated (- (f64vector-ref after 7) (f64vector-ref before 7))))
    (receipt phase
      (list (cons 'input-facts input) (cons 'exported-rows output)
            (cons 'verified-requests count) (cons 'wall-ns wall) (cons 'cpu-seconds cpu)
            (cons 'requests-per-second (/ (* count 1000000000.) wall))
            (cons 'rows-per-second (/ (* count output 1000000000.) wall))
            (cons 'natural-collections collections)
            (cons 'gc-wall-seconds (- (f64vector-ref after 5) (f64vector-ref before 5)))
            (cons 'raw-allocation-counter-delta allocated)
            (cons 'allocation-bytes (and (zero? collections) (>= allocated 0) allocated))
            (cons 'p50-ns (list-ref ordered (quotient (- count 1) 2)))
            (cons 'p95-ns p95) (cons 'max-ns (list-ref ordered (- count 1)))))
    (check (< p95 100000000) => #t)))

(def (million-query groups width recursive?)
  (check (##current-vm-processor-count) => 1)
  (receipt 'prepare-start (list (cons 'groups groups) (cons 'width width)
                               (cons 'recursive recursive?)))
  (let* ((input (* groups (- width 1)))
         (output (if recursive? (output-count groups width) input))
         (span (* groups width))
         (begin (tick))
         (first (edges groups width 0))
         (second (edges groups width span))
         (session (open-session first groups width recursive?))
         (samples (make-f64vector 1000 0.)))
    (try
      (receipt 'prepared (list (cons 'input-facts input) (cons 'expected-rows output)
                               (cons 'recursive recursive?) (cons 'wall-ns (nanoseconds begin))))
      (let-values (((cold total) (query session groups width 0 recursive?)))
        (receipt 'cold-complete-query
          (list (cons 'query-and-export-ns cold) (cons 'with-oracle-ns total)
                (cons 'exported-rows output))))
      (let ((start (tick)) (cpu (cpu-time)) (before (##process-statistics)))
        (let loop ((index 0))
          (unless (= index 1000)
            (let* ((offset (if (even? index) span 0))
                   (rows (if (even? index) second first))
                   (request (tick)))
              ;; Every measured request changes the complete source cut.
              (gerbil-ascent-session-replace-source! session 'edge rows)
              (let-values (((query-ns total-ns) (query session groups width offset recursive?)))
                (void))
              (f64vector-set! samples index (exact->inexact (nanoseconds request))))
            (when (zero? (modulo (+ index 1) 10))
              (receipt 'progress (list (cons 'verified-requests (+ index 1))
                                       (cons 'wall-ns (nanoseconds start)))))
            (loop (+ index 1))))
        (report-samples 'changed-complete-query input output samples
          (nanoseconds start) (- (cpu-time) cpu) before))
      (finally (gerbil-ascent-session-close! session)))))

(def actor-million-state-test
  (test-suite "million-row resident Session state"
    (test-case "one million verified state requests with one million source rows"
      (check (##current-vm-processor-count) => 1)
      (receipt 'state-prepare-start (list (cons 'input-facts 1000000)))
      (let* ((begin (tick))
             (rows (edges 1000000 2 0))
             (session (open-session rows 1000000 2 #f))
             (samples (make-f64vector 1000000 0.)))
        (try
          (receipt 'state-prepared (list (cons 'input-facts 1000000)
                                        (cons 'wall-ns (nanoseconds begin))))
          (let ((start (tick)) (cpu (cpu-time)) (before (##process-statistics)))
            (let loop ((index 0))
              (unless (= index 1000000)
                (let* ((request (tick)) (state (gerbil-ascent-session-state session)))
                  (unless (equal? state '(0 idle)) (error "unexpected Session state" state))
                  (f64vector-set! samples index (exact->inexact (nanoseconds request))))
                (loop (+ index 1))))
            (report-samples 'resident-state 1000000 0 samples
              (nanoseconds start) (- (cpu-time) cpu) before))
          (finally (gerbil-ascent-session-close! session)))))))

(def actor-million-oracle-test
  (test-suite "million-workload oracle refusal controls"
    (test-case "complete disconnected-chain rows and displaced cuts"
      (let (rows '((0 1) (0 2) (1 2) (3 4) (3 5) (4 5)))
        (check (verify rows 2 3 0 #t) => 6)
        (check-exception (verify (cdr rows) 2 3 0 #t) true)
        (check-exception (verify (cons (car rows) (cdr rows)) 2 3 10 #t) true)
        (check-exception (verify (cons (car rows) (cons (car rows) (cddr rows))) 2 3 0 #t) true)
        (check-exception (verify '((0 1) (1 2) (2 3) (3 4) (4 5) (3 5)) 2 3 0 #t) true)))
    (test-case "base-only queries cannot reuse a recursive oracle"
      (check (verify '((0 1) (1 2) (3 4) (4 5)) 2 3 0 #f) => 4)
      (check-exception (verify '((0 1) (0 2) (3 4) (4 5)) 2 3 0 #f) true))
    (test-case "million dimensions count data independently of request samples"
      (check (* 1000000 (- 2 1)) => 1000000)
      (check (output-count 128 128) => 1040384))))

(def actor-million-query-test
  (test-suite "million-input complete query"
    (test-case "one million inputs and one million fully checked output rows"
      (million-query 1000000 2 #f))))

(def actor-million-recursive-test
  (test-suite "million-output recursive query"
    (test-case "128 chains of width 128 produce 1040384 checked rows"
      (million-query 128 128 #t))))
