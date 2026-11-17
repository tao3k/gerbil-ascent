;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/core/execution-control current-ascent-execution-control)
        (only-in :gerbil-ascent/interface/engine-api ascent-engine-call)
        (only-in :gerbil-ascent/program/func gerbil-ascent-program gerbil-ascent-relation
                 gerbil-ascent-variable gerbil-ascent-rule gerbil-ascent-atom)
        (only-in :gerbil-ascent/program/session gerbil-ascent-session-run
                 gerbil-ascent-session-append-source! gerbil-ascent-session-replace-source!)
        (only-in :gerbil-ascent/program/actor-session gerbil-ascent-open-actor-session
                 gerbil-ascent-session-state gerbil-ascent-session-last-completed
                 gerbil-ascent-session-cancel! gerbil-ascent-session-close!))
(export actor-session-test actor-session-large-test actor-session-4096-test actor-session-shared-test
        actor-session-replacement-test actor-session-gc-test actor-session-cancel-test
        actor-session-wire-4096-test actor-session-wire-16384-test)

(def ticks-per-second
  (let (buffer (make-u64vector 1 0))
    (##get-monotonic-time-frequency! buffer 0)
    (let (frequency (u64vector-ref buffer 0))
      (when (zero? frequency) (error "missing monotonic clock frequency"))
      frequency)))

(def (monotonic-tick)
  (let (buffer (make-u64vector 1 0))
    (##get-monotonic-time! buffer 0)
    (u64vector-ref buffer 0)))

(def (elapsed-nanoseconds start end)
  (quotient (* (- end start) 1000000000) ticks-per-second))

(def (chain count)
  (map (lambda (id) (list id (+ id 1))) (iota count)))

(def (declaration edges input-limit recursive? (heads '(answer)) (probes #f))
  (check-equal? (##current-vm-processor-count) 1)
  (let* ((x (gerbil-ascent-variable 'x))
         (y (gerbil-ascent-variable 'y))
         (z (gerbil-ascent-variable 'z))
         (head (gerbil-ascent-atom 'answer (list x z)))
         (hop (gerbil-ascent-atom 'edge (list y z)))
         (rules
          (map (lambda (name)
                 (gerbil-ascent-rule
                   (list (gerbil-ascent-atom name (list x z)))
                   (list (gerbil-ascent-atom
                          (cond (recursive? 'answer) (probes 'probe) (else 'edge))
                          (list x y)) hop)))
               heads)))
    (gerbil-ascent-program
      (cons (gerbil-ascent-relation 'edge 2 edges)
            (append (if probes (list (gerbil-ascent-relation 'probe 2 probes)) [])
                    (map (lambda (name) (gerbil-ascent-relation name 2 [])) heads)))
      (if recursive?
        (cons (gerbil-ascent-rule (list head) (list (gerbil-ascent-atom 'edge (list x z)))) rules)
        rules)
      input-limit 150000 160000)))

(defstruct gc-samples (wall cpu collections bracket) final: #t)

(def (latency-samples count (trace? #f))
  (vector (make-f64vector count 0.) 0 0.
          (and trace?
               (make-gc-samples (make-f64vector count 0.) (make-f64vector count 0.)
                 (make-f64vector count 0.) (make-f64vector count 0.)))))

(def (record-gc! trace index before after)
  (def (delta field) (- (f64vector-ref after field) (f64vector-ref before field)))
  (f64vector-set! (gc-samples-wall trace) index (* 1000000000. (delta 5)))
  (f64vector-set! (gc-samples-cpu trace) index (* 1000000000. (+ (delta 3) (delta 4))))
  (f64vector-set! (gc-samples-collections trace) index (delta 6))
  (f64vector-set! (gc-samples-bracket trace) index (* 1000000000. (delta 2))))

(def (measure samples operation)
  (let* ((trace (vector-ref samples 3))
         (before (and trace (##process-statistics)))
         (begin-cpu (cpu-time))
         (begin-wall (monotonic-tick))
         (answer (operation))
         (end-wall (monotonic-tick))
         (cpu (- (cpu-time) begin-cpu))
         (elapsed (elapsed-nanoseconds begin-wall end-wall))
         (index (vector-ref samples 1)))
    (when trace (record-gc! trace index before (##process-statistics)))
    (f64vector-set! (vector-ref samples 0) index (exact->inexact elapsed))
    (vector-set! samples 1 (+ index 1))
    (vector-set! samples 2 (+ (vector-ref samples 2) cpu))
    answer))

(def (report-tail rows phase samples)
  (let* ((trace (vector-ref samples 3))
         (latency (vector-ref samples 0))
         (count (vector-ref samples 1))
         (slow (filter (lambda (index) (>= (f64vector-ref latency index) 20000000.))
                       (iota count)))
         (with-gc (filter (lambda (index) (> (f64vector-ref (gc-samples-collections trace) index) 0.))
                          slow))
         (dominated (filter (lambda (index)
                              (let* ((gc (f64vector-ref (gc-samples-wall trace) index))
                                     (elapsed (f64vector-ref latency index))
                                     (bracket (f64vector-ref (gc-samples-bracket trace) index))
                                     (overlap (- gc (max 0. (- bracket elapsed)))))
                                (and (<= gc bracket) (> overlap (/ elapsed 2.)))))
                            with-gc))
         (worst (foldl (lambda (index current)
                        (if (> (f64vector-ref latency index) (f64vector-ref latency current))
                          index current)) 0 (iota count))))
    (display "ACTOR-TAIL ")
    (write (list (cons 'input-edges rows) (cons 'phase phase) (cons 'requests count)
                 (cons 'at-least-20ms (length slow)) (cons 'slow-with-gc (length with-gc))
                 (cons 'slow-mostly-gc (length dominated))
                 (cons 'worst-index worst) (cons 'worst-ns (f64vector-ref latency worst))
                 (cons 'worst-bracket-ns (f64vector-ref (gc-samples-bracket trace) worst))
                 (cons 'worst-gc-wall-ns (f64vector-ref (gc-samples-wall trace) worst))
                 (cons 'worst-gc-cpu-ns (f64vector-ref (gc-samples-cpu trace) worst))
                 (cons 'worst-collections (f64vector-ref (gc-samples-collections trace) worst))))
    (newline)))

(def (report-phase rows phase samples (rules 1) (enforce? #t))
  (let* ((count (vector-ref samples 1))
         (ordered (list-sort < (f64vector->list (vector-ref samples 0))))
         (p95 (list-ref ordered (- (quotient (+ (* count 95) 99) 100) 1)))
         (elapsed (apply + ordered)))
    (check-equal? count (f64vector-length (vector-ref samples 0)))
    (check-equal? (andmap (lambda (sample) (>= sample 0.)) ordered) #t)
    (display "ACTOR-PRODUCTION ")
    (write (list (cons 'input-edges rows) (cons 'consumers rules) (cons 'phase phase)
                 (cons 'requests count) (cons 'gc-traced (and (vector-ref samples 3) #t))
                 (cons 'cpu-us (* 1000000. (vector-ref samples 2)))
                 (cons 'isolated-service-rate-per-second (/ (* count 1000000000.) elapsed))
                 (cons 'p50-ns (list-ref ordered (- (quotient (+ count 1) 2) 1)))
                 (cons 'p95-ns p95)
                 (cons 'p99-ns (list-ref ordered (- (quotient (+ (* count 99) 99) 100) 1)))
                 (cons 'max-ns (list-ref ordered (- count 1)))))
    (newline)
    ;; Small profiles and the single first call remain diagnostic. Sustained
    ;; production phases must satisfy the same strict 100 ms request target.
    (when (and enforce? (>= count 1000)) (check-equal? (< p95 100000000.) #t))
    (when (vector-ref samples 3) (report-tail rows phase samples))
    p95))

;;; Pair by request ordinal. Percentiles of staging and evaluation cannot
;;; be added because their collections and other stalls need not coincide.
(def (report-transaction rows rules phase staging evaluation (enforce? #t))
  (let* ((count (vector-ref staging 1))
         (stage-gc (vector-ref staging 3))
         (eval-gc (vector-ref evaluation 3))
         (samples (latency-samples count (and stage-gc eval-gc)))
         (trace (vector-ref samples 3))
         (wall (vector-ref samples 0))
         (stage-wall (vector-ref staging 0))
         (eval-wall (vector-ref evaluation 0)))
    (check-equal? (vector-ref evaluation 1) count)
    (let next ((index 0))
      (unless (= index count)
        (f64vector-set! wall index (+ (f64vector-ref stage-wall index)
                                     (f64vector-ref eval-wall index)))
        ;; Each GC statistic covers only its own bracket around an operation.
        ;; Summing the disjoint brackets preserves the overlap lower bound.
        (when trace
          (for-each
           (lambda (field)
             (f64vector-set! (field trace) index
               (+ (f64vector-ref (field stage-gc) index)
                  (f64vector-ref (field eval-gc) index))))
           (list gc-samples-wall gc-samples-cpu gc-samples-collections gc-samples-bracket)))
        (next (+ index 1))))
    (vector-set! samples 1 count)
    (vector-set! samples 2 (+ (vector-ref staging 2) (vector-ref evaluation 2)))
    (report-phase rows phase samples rules enforce?)))

(def (report-live rows rules before)
  (let (after (##process-statistics))
    (def (delta field) (- (f64vector-ref after field) (f64vector-ref before field)))
    (##gc)
    (let* ((collected (##process-statistics))
           (collections (delta 6))
           (bytes (delta 7)))
      (display "ACTOR-LIVE ")
      (write (list (cons 'input-edges rows) (cons 'consumers rules)
                   (cons 'natural-collections collections)
                   (cons 'gc-wall-ns (* 1000000000. (delta 5)))
                   (cons 'gc-cpu-ns (* 1000000000. (+ (delta 3) (delta 4))))
                   (cons 'raw-allocation-counter-delta bytes)
                   (cons 'allocation-counter-delta (and (zero? collections) (>= bytes 0) bytes))
                   (cons 'gc-charge-before (f64vector-ref before 16))
                   (cons 'gc-charge-after (f64vector-ref collected 16))
                   (cons 'live-before (f64vector-ref before 17))
                   (cons 'live-after (f64vector-ref collected 17))))
      (newline))))

(def (answer-rows result (name 'answer))
  (unless (.ref result 'finished) (error "actor closure did not finish"))
  ((.ref result 'rows-of) name))

(def (two-hop-oracle count)
  (map (lambda (id) (list id (+ id 2))) (iota (- count 1))))

(def (check-export rows expected)
  (unless (equal? expected (list-sort (lambda (a b) (< (car a) (car b))) rows))
    (error "actor result differs from chain oracle")))

(def (sustained-session count repetitions (heads '(answer)) (trace? #f))
  (check-equal? (##current-vm-processor-count) 1)
  (let* ((edges (chain count))
         (probes (and (pair? (cdr heads))
                      (append (take edges 16) (list (list (- count 1) count)))))
         (selected? (lambda (row) (or (not probes) (< (car row) 16) (= (car row) (- count 1)))))
         (expected (filter selected? (two-hop-oracle count)))
         (extended (filter selected? (two-hop-oracle (+ count 1))))
         (input-limit (+ count 1 (if probes (length probes) 0)))
         (session (gerbil-ascent-open-actor-session
                   (declaration edges input-limit #f heads probes) workers: 1))
         (first-run (latency-samples 1))
         (warm (latency-samples repetitions trace?))
         (append-request (latency-samples repetitions trace?))
         (append-run (latency-samples repetitions trace?))
         (replace-request (latency-samples repetitions trace?))
         (replace-run (latency-samples repetitions trace?))
         (export (latency-samples repetitions trace?))
         (close-cut (list count (+ count 1))))
    (def (run) (gerbil-ascent-session-run session))
    (def (check-chain result expected)
      (for-each (lambda (name) (check-export (answer-rows result name) expected)) heads))
    (try
      (##gc)
      (let* ((before (##process-statistics))
             (first (measure first-run run)))
        (check-chain first expected)
        (let (window-start (monotonic-tick))
          (let loop ((index 0))
            (unless (= index repetitions)
              (check-chain (measure warm run) expected)
              (measure append-request (cut gerbil-ascent-session-append-source! session 'edge close-cut))
              (check-chain (measure append-run run) extended)
              (measure replace-request (cut gerbil-ascent-session-replace-source! session 'edge edges))
              (let* ((replaced (measure replace-run run))
                     (rows (measure export (cut answer-rows replaced))))
                (check-export rows expected)
                (for-each (lambda (name) (check-export (answer-rows replaced name) expected)) (cdr heads)))
              (loop (+ index 1))))
          ;; Include all six public calls and independent client verification.
          ;; Reciprocal phase service time is not sustained window throughput.
          (let (elapsed (elapsed-nanoseconds window-start (monotonic-tick)))
            (display "ACTOR-WINDOW ")
            (write (list (cons 'unit 'verified-production-update-cycle)
                         (cons 'input-edges count) (cons 'consumers (length heads))
                         (cons 'cycles repetitions) (cons 'api-calls-per-cycle 6)
                         (cons 'elapsed-ns elapsed)
                         (cons 'verified-cycles-per-second
                               (/ (* repetitions 1000000000.) elapsed))))
            (newline)))
        (report-live count (length heads) before)
        (check-chain first expected))
      (check-equal? (gerbil-ascent-session-state session) (list (+ 1 (* 5 repetitions)) 'idle))
      (for-each (lambda (phase samples) (report-phase count phase samples (length heads)))
                '(first-run unchanged-run append-request append-run replace-request replace-run export)
                (list first-run warm append-request append-run replace-request replace-run export))
      (report-transaction count (length heads) 'append-transaction append-request append-run)
      (report-transaction count (length heads) 'replace-transaction replace-request replace-run)
      (finally (gerbil-ascent-session-close! session)))))

(def (cancel-session count repetitions)
  (let* ((edges (chain count))
         (session (gerbil-ascent-open-actor-session
                   (declaration '((0 1)) count #t) workers: 1))
         (drain (latency-samples repetitions)))
    (try
      (let (prior (gerbil-ascent-session-run session))
        (for-each (lambda (_)
          (gerbil-ascent-session-replace-source! session 'edge edges)
          (let (caller (spawn (lambda ()
                         (with-catch (lambda (_) 'rejected)
                           (cut gerbil-ascent-session-run session)))))
            (let wait-running ((polls 0))
              (unless (eq? (cadr (gerbil-ascent-session-state session)) 'running)
                (when (= polls 1000) (error "long closure did not start"))
                (thread-yield!)
                (wait-running (+ polls 1))))
            (check-equal? (measure drain
                           (lambda ()
                             (unless (eq? 'draining (gerbil-ascent-session-cancel! session))
                               (error "cancel missed the active publication"))
                             (thread-join! caller))) 'rejected)
            (check-equal? (eq? prior (gerbil-ascent-session-last-completed session)) #t)))
          (iota repetitions))
        (check-equal? (answer-rows (gerbil-ascent-session-run session)) '((0 1)))
        (report-phase count 'cancel-and-drain drain))
      (finally (gerbil-ascent-session-close! session)))))

(def (changed-replacements count repetitions)
  (let* ((prior (chain count))
         (shift (+ count 1))
         (next (map (lambda (row) (list (car row) (+ (cadr row) shift))) prior))
         (probes (take prior 17))
         (heads '(answer second third fourth))
         (session (gerbil-ascent-open-actor-session
                   (declaration prior (+ count (length probes)) #f heads probes) workers: 1))
         (staging (latency-samples repetitions))
         (evaluation (latency-samples repetitions))
         (expected (take (two-hop-oracle count) (length probes)))
         (shifted (map (lambda (row) (list (car row) (+ (cadr row) shift))) expected)))
    (try
      (##gc)
      (let* ((before (##process-statistics))
             (first (gerbil-ascent-session-run session)))
        (for-each
         (lambda (ordinal)
           (let ((changed? (even? ordinal)))
             (measure staging (lambda ()
               (gerbil-ascent-session-replace-source! session 'edge (if changed? next prior))))
             (let (result (measure evaluation (cut gerbil-ascent-session-run session)))
               (for-each
                (lambda (head)
                  (check-export (answer-rows result head) (if changed? shifted expected)))
                heads))))
         (iota repetitions))
        (report-live count (length heads) before)
        (check-export (answer-rows first) expected))
      (report-transaction count (length heads) 'changed-replace-transaction staging evaluation)
      (finally (gerbil-ascent-session-close! session)))))

(def (wire-session count repetitions)
  (check-equal? (##current-vm-processor-count) 1)
  (let* ((source
          (object->string
           `(ascent
             (relation edge (from to))
             (relation answer (from to))
             ((answer x z) <-- (edge x y) (edge y z))
             ;; The result includes the source rows as well as the answer.
             (bounds ,count ,(- count 1) ,(- (* 2 count) 1)))))
         (original (chain count))
         (offset (+ count 1))
         (shifted
          (map (lambda (row) (list (+ offset (car row)) (+ offset (cadr row)))) original))
         (expected (two-hop-oracle count))
         (shifted-expected
          (map (lambda (id) (list id (+ id 2))) (iota (- count 1) offset)))
         (admission (latency-samples 1))
         (first-query (latency-samples 1))
         (replace (latency-samples repetitions #t))
         (query (latency-samples repetitions #t))
         (handle
          (hash-ref
           (measure admission
             (lambda ()
               (ascent-engine-call
                (hash ("operation" "open-sources") ("sources" (list source))))))
           "handle"))
         (query-request
          (hash ("operation" "source-run") ("handle" handle) ("queries" '("answer")))))
    (def (run) (ascent-engine-call query-request))
    (def (verify-and-release result expected generation)
      (unless (and (hash-ref result "complete")
                   (equal? (hash-ref result "scalarProjection") "supported")
                   (= (hash-ref result "sourceGeneration") generation))
        (error "unexpected typed Actor result generation" generation))
      (check-export (hash-ref (hash-ref result "relations") "answer") expected)
      (unless
          (hash-ref
           (ascent-engine-call
            (hash ("operation" "owned-result") ("handle" handle)
                  ("action" "release") ("result" (hash-ref result "resultHandle"))))
           "released")
        (error "typed Actor result was not released")))
    (try
      (let (used-worker? #f)
        (parameterize
            ((current-ascent-execution-control
              (lambda (_work _facts)
                (when (eq? (thread-name (current-thread)) 'ascent-session-evaluation)
                  (set! used-worker? #t)))))
          (verify-and-release (measure first-query run) [] 0))
        (check-equal? used-worker? #t))
      (##gc)
      (let ((before (##process-statistics))
            (start (monotonic-tick)))
        (for-each
         (lambda (ordinal)
           (let ((changed? (even? ordinal))
                 (generation (+ ordinal 1)))
             (let (response
                   (measure replace
                     (lambda ()
                       (ascent-engine-call
                        (hash ("operation" "source-replace") ("handle" handle)
                              ("sources" (list (hash ("relation" "edge")
                                                    ("rows" (if changed? shifted original))))))))))
               (unless (= (hash-ref response "sourceGeneration") generation)
                 (error "unexpected typed Actor replacement generation" generation)))
             (verify-and-release (measure query run)
                                 (if changed? shifted-expected expected) generation)))
         (iota repetitions))
        (let (elapsed (elapsed-nanoseconds start (monotonic-tick)))
          (display "ACTOR-WINDOW ")
          (write (list (cons 'unit 'verified-typed-source-replacement-cycle)
                       (cons 'input-edges count) (cons 'consumers 1)
                       (cons 'cycles repetitions) (cons 'api-calls-per-cycle 3)
                       (cons 'elapsed-ns elapsed)
                       (cons 'verified-cycles-per-second
                             (/ (* repetitions 1000000000.) elapsed))))
          (newline))
        (report-live count 1 before))
      (report-phase count 'typed-open admission)
      (report-phase count 'typed-first-query first-query)
      ;; Keep the whole measured window visible if a typed phase fails its gate.
      (let (tails (list (report-phase count 'typed-eager-replace replace 1 #f)
                       (report-phase count 'typed-complete-export query 1 #f)
                       (report-transaction count 1 'typed-replace-and-export replace query #f)))
        (when (>= repetitions 1000)
          (for-each (lambda (p95) (check-equal? (< p95 100000000.) #t)) tails)))
      (finally (ascent-engine-call (hash ("operation" "close") ("handle" handle)))))))

(def actor-session-test
  (test-suite "Single VM Actor production Session / 128"
    (test-case "1000 cycles of production runs and mutations"
      (sustained-session 128 1000))))
(def actor-session-large-test
  (test-suite "Single VM Actor production Session / 4096 diagnostic"
    (test-case "larger production cuts through the same Session"
      (sustained-session 4096 64))))
(def actor-session-4096-test
  (test-suite "Single VM Actor production Session / 4096 sustained"
    (test-case "1000 large cycles through the production Session"
      (sustained-session 4096 1000))))
(def actor-session-wire-4096-test
  (test-suite "Single VM typed Actor Session / 4096 sustained"
    (test-case "1000 typed replacements with complete and verified exports"
      (wire-session 4096 1000))))
(def actor-session-wire-16384-test
  (test-suite "Single VM typed Actor Session / 16384 sustained"
    (test-case "1000 wide source cuts through the same typed Actor"
      (wire-session 16384 1000))))
(def actor-session-shared-test
  (test-suite "Single VM Actor production Session / 16384 shared"
    (test-case "1000 large cycles with four consumers of the same physical key"
      (sustained-session 16384 1000 '(answer second third fourth)))))
(def actor-session-replacement-test
  (test-suite "Single VM Actor production Session / 16384 replacement"
    (test-case "1000 large replacements change all edge values"
      (changed-replacements 16384 1000))))
(def actor-session-gc-test
  (test-suite "Single VM Actor production Session / 16384 GC"
    (test-case "large Actor requests record overlapping GC pauses"
      (sustained-session 16384 1000 '(answer second third fourth) #t))))
(def actor-session-cancel-test
  (test-suite "Single VM Actor production Session / cancellation"
    (test-case "cancellation drains without changing the previous completed result"
      (cancel-session 448 32))))
