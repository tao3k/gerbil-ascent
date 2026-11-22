;;; -*- Gerbil -*-
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Native production Session measurements, not a message-to-row conversion.
(import :std/test
        (only-in :std/list/list append-map)
        (only-in :std/sync/completion make-completion completion-post! completion-wait!)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/func
                 gerbil-ascent-program gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-rule gerbil-ascent-atom)
        (only-in :gerbil-ascent/program/session
                 gerbil-ascent-session-run gerbil-ascent-session-replace-source!
                 gerbil-ascent-session-append-source!)
        (only-in :gerbil-ascent/program/actor-session
                 gerbil-ascent-open-actor-session gerbil-ascent-session-state
                 gerbil-ascent-session-last-completed
                 gerbil-ascent-session-close! gerbil-ascent-session-open-integer-pages
                 gerbil-ascent-session-pull-integer-page!))
(export actor-million-oracle-test actor-million-state-test
        actor-million-state-contention-test
        actor-million-query-test actor-million-recursive-test
        million-query ten-million-query ten-million-paged-query
        actor-ten-thousand-closure-test
        actor-million-list-delivery-test actor-million-visit-test
        actor-million-fields-test actor-million-fields-controls-test
        actor-packed-reuse-controls-test
        actor-query-delivery-test)

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
  (def (chain group)
    (map (lambda (column)
           (let (left (+ offset (* group width) column)) (list left (+ left 1))))
         (iota (- width 1))))
  (let (ordinals (iota groups))
    ;; Keep the projection setup. Both SDKs agree on singleton groups.
    (if (= width 2)
      (append-map chain ordinals)
      ;; The release fixture emitted each chain's edges in descending order.
      (foldl (lambda (group rows) (foldl cons rows (chain group))) [] (reverse ordinals)))))

(def (output-count groups width)
  (quotient (* groups width (- width 1)) 2))

(def (declaration rows groups width recursive?
                  input-facts: (input (* groups (- width 1))))
  (let* ((x (gerbil-ascent-variable 'x))
         (y (gerbil-ascent-variable 'y))
         (z (gerbil-ascent-variable 'z))
         (edge (gerbil-ascent-atom 'edge (list x y)))
         (reach (gerbil-ascent-atom 'reach (list x y)))
         (base (gerbil-ascent-rule (list reach) (list edge)))
         (step (gerbil-ascent-rule
                 (list (gerbil-ascent-atom 'reach (list x z)))
                 (list reach (gerbil-ascent-atom 'edge (list y z)))))
         (output (if recursive? (output-count groups width) input)))
    ;; Workload-specific declared ceilings; existing production defaults and
    ;; original performance gates are untouched. Exactly one VM processor.
    (gerbil-ascent-program
      (list (gerbil-ascent-relation 'edge 2 rows)
            (gerbil-ascent-relation 'reach 2 []))
      (if recursive? (list base step) (list base)) input output (+ input output))))

(def (open-session rows groups width recursive?
                   input-facts: (input (* groups (- width 1))))
  (let* ((start (tick))
         (program (declaration rows groups width recursive? input-facts: input)))
    (receipt 'declaration-ready (list (cons 'wall-ns (nanoseconds start))))
    (let* ((open (tick))
           (session (gerbil-ascent-open-actor-session program workers: 1)))
      (receipt 'session-open (list (cons 'wall-ns (nanoseconds open))))
      session)))

(def (verify-exact rows groups width offset recursive?)
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

(def (verify-fixnum rows width offset end expected seen chain-ends)
  (let ((width-two? (and (not chain-ends) (fx= width 2)))
        (last-column (fx- width 1)))
    (defrule (mark origin target datum)
      (begin
        (unless (and (fixnum? origin) (fixnum? target)
                     (fx<= offset origin) (fx< origin target) (fx< target end))
          (error "row outside independent chain oracle" datum))
        (let* ((left (fx- origin offset))
               (right (fx- target offset))
               (index
                (cond
                 (chain-ends
                  (unless (fx< right (vector-ref chain-ends left))
                    (error "row outside independent chain oracle" datum))
                  (fx+ (fx* left width) (fx- right left)))
                 (width-two?
                  (unless (and (fx= (fx+ left 1) right) (fx= (fxand left 1) 0))
                    (error "row outside independent chain oracle" datum))
                  (fxquotient left 2))
                 (else
                  (unless (and (fx= (fx+ left 1) right)
                               (fx< (fxremainder left width) last-column))
                    (error "row outside independent chain oracle" datum))
                  left))))
          (unless (fx= (u8vector-ref seen index) 0)
            (error "duplicate exported row" datum))
          (u8vector-set! seen index 1))))
    (if (s64vector? rows)
      (let (size (s64vector-length rows))
        (unless (= size (* 2 expected))
          (error "incorrect binary relation extent" size expected))
        (let walk ((i 0))
          (if (fx= i size) expected
            (let ((origin (##s64vector-ref rows i)) (target (##s64vector-ref rows (fx+ i 1))))
              (mark origin target (list origin target))
              (walk (fx+ i 2))))))
      (let walk ((rest rows) (count 0))
        (cond
         ((pair? rest)
          (let (row (car rest))
            (unless (and (pair? row) (pair? (cdr row)) (null? (cddr row)))
              (error "invalid exported row" row))
            (let ((origin (car row)) (target (cadr row)))
              (mark origin target row)
              (walk (cdr rest) (fx+ count 1)))))
         ((null? rest)
          (unless (fx= count expected) (error "incomplete exported relation" count expected))
          count)
         (else (error "invalid exported relation" rest)))))))

(def (chain-end-ordinals span width)
  (let (ends (make-vector span))
    (let fill ((start 0))
      (when (fx< start span)
        (let (end (fx+ start width))
          (let fill-chain ((left start))
            (unless (fx= left end)
              (vector-set! ends left end)
              (fill-chain (fx+ left 1))))
          (fill end))))
    ends))

(def (make-chain-verifier groups width recursive?)
  (let* ((span (* groups width))
         (expected (if recursive? (output-count groups width) (* groups (- width 1))))
         (slots (cond (recursive? (* span width)) ((= width 2) groups) (else span))))
    (if (and (fixnum? groups) (fx>= groups 0)
             (fixnum? width) (fx> width 0) (fixnum? span)
             (fixnum? expected) (fixnum? slots))
      (let ((seen (make-u8vector slots 0))
            (chain-ends (and recursive? (chain-end-ordinals span width))))
        (lambda (rows offset)
          (let (end (+ offset span))
            (if (and (fixnum? offset) (fixnum? end))
              (begin
                (u8vector-fill! seen 0)
                (verify-fixnum rows width offset end expected seen chain-ends))
              (verify-exact rows groups width offset recursive?)))))
      (lambda (rows offset) (verify-exact rows groups width offset recursive?)))))

(defrule (for-each-expected-chain-row groups width offset (left right) body ...)
  (let (last-base (fx+ offset (fx* (fx- groups 1) width)))
    (let visit-gap ((gap (fx- width 1)))
      (unless (fx= gap 0)
        (let* ((chains-forward? (odd? gap))
               (step (if chains-forward? -1 1))
               (base-step (if chains-forward? width (fx- 0 width)))
               (extent (fx- width gap)))
          (let visit-chain ((base (if chains-forward? offset last-base)) (remaining groups))
            (unless (fx= remaining 0)
              (let (start (if chains-forward? (fx+ base (fx- extent 1)) base))
                (let visit-row ((left start) (right (fx+ start gap)) (remaining extent))
                  (unless (fx= remaining 0)
                    body ...
                    (visit-row (fxwrap+ left step) (fxwrap+ right step) (fx- remaining 1)))))
              (visit-chain (fxwrap+ base base-step) (fx- remaining 1)))))
        (visit-gap (fx- gap 1))))))

(def (ordered-chain-count rows groups width offset expected)
  (let/cc unordered
    (if (s64vector? rows)
      (let ((size (s64vector-length rows)) (cell 0))
        (unless (= size (* 2 expected)) (unordered #f))
        (for-each-expected-chain-row groups width offset (left right)
          (unless (and (fx< cell size)
                       (eq? left (##s64vector-ref rows cell))
                       (eq? right (##s64vector-ref rows (fx+ cell 1))))
            (unordered #f))
          (set! cell (fx+ cell 2)))
        (unless (fx= cell size) (unordered #f)))
      (let (rest rows)
        (for-each-expected-chain-row groups width offset (left right)
          (unless (pair? rest) (unordered #f))
          (let (row (car rest))
            (unless (and (pair? row) (eq? left (car row))
                         (pair? (cdr row)) (eq? right (cadr row)) (null? (cddr row)))
              (unordered #f)))
          (set! rest (cdr rest)))
        (unless (null? rest) (unordered #f))))
    expected))

(def (make-ordered-chain-verifier groups width on-fallback!)
  (let ((span (* groups width))
        (expected (output-count groups width))
        (bitmap (delay (make-chain-verifier groups width #t))))
    (lambda (rows offset)
      (or (and (fixnum? offset) (fixnum? (+ offset span))
               (ordered-chain-count rows groups width offset expected))
          (begin
            (on-fallback!)
            ((force bitmap) rows offset))))))

(def (verify rows groups width offset recursive?)
  ((make-chain-verifier groups width recursive?) rows offset))

(def (record-run-cost! totals before after)
  ;; Slot order follows the Gambit process-statistics API.
  (let ((cpu (+ (- (f64vector-ref after 0) (f64vector-ref before 0))
                (- (f64vector-ref after 1) (f64vector-ref before 1))))
        (gc-cpu (+ (- (f64vector-ref after 3) (f64vector-ref before 3))
                   (- (f64vector-ref after 4) (f64vector-ref before 4))))
        (collections (- (f64vector-ref after 6) (f64vector-ref before 6))))
    (f64vector-set! totals 0 (+ (f64vector-ref totals 0) cpu))
    (f64vector-set! totals 1 (+ (f64vector-ref totals 1) gc-cpu))
    (f64vector-set! totals 2 (+ (f64vector-ref totals 2) collections))))

(def (query session verify-rows offset run-cost (source-size #f) (deliver #f))
  (let* ((before (##process-statistics))
         (start (tick))
         (result (gerbil-ascent-session-run session))
         (run-ns (nanoseconds start)))
    (record-run-cost! run-cost before (##process-statistics))
    (unless (.ref result 'finished) (error "query did not finish"))
    (let* ((rows (if deliver (deliver session) ((.ref result 'rows-of) 'reach)))
           (query-ns (nanoseconds start)))
      (when source-size
        (unless (= source-size (cdr (assq 'edge ((.ref result 'relation-sizes)))))
          (error "query did not publish the expected source size" source-size)))
      (verify-rows rows offset)
      (values run-ns (- query-ns run-ns) (- (nanoseconds start) query-ns)))))

(def (report-query-work phase completed replace-ns run-ns export-ns oracle-ns wall-ns cost)
  (receipt phase
    (list (cons 'verified-requests completed) (cons 'replace-ns replace-ns)
          (cons 'run-and-publish-ns run-ns) (cons 'export-ns export-ns)
          (cons 'oracle-ns oracle-ns) (cons 'wall-ns wall-ns)
          (cons 'run-cpu-seconds (f64vector-ref cost 0))
          (cons 'run-gc-cpu-seconds (f64vector-ref cost 1))
          (cons 'run-natural-collections (f64vector-ref cost 2)))))

(def (report-samples phase input output samples wall cpu before
                     (delivered #f) (limit 100000000) (shard-info []))
  (let* ((after (##process-statistics))
         (ordered (list-sort < (f64vector->list samples)))
         (count (length ordered))
         (p95 (list-ref ordered (- (quotient (+ (* count 95) 99) 100) 1)))
         (collections (- (f64vector-ref after 6) (f64vector-ref before 6)))
         (allocated (- (f64vector-ref after 7) (f64vector-ref before 7))))
    (receipt phase
      (append shard-info
        (if (null? shard-info) []
          (list (cons 'request-latencies-ns (f64vector->list samples))
                (cons 'gc-cpu-seconds (+ (- (f64vector-ref after 3) (f64vector-ref before 3))
                                         (- (f64vector-ref after 4) (f64vector-ref before 4))))))
        (list (cons 'input-facts input) (cons 'exported-rows output)
              (cons 'verified-requests count) (cons 'wall-ns wall) (cons 'cpu-seconds cpu)
              (cons 'requests-per-second (/ (* count 1000000000.) wall))
              (cons 'rows-per-second (/ (* (or delivered (* count output)) 1000000000.) wall))
              (cons 'natural-collections collections)
              (cons 'gc-wall-seconds (- (f64vector-ref after 5) (f64vector-ref before 5)))
              (cons 'raw-allocation-counter-delta allocated)
              (cons 'allocation-bytes (and (zero? collections) (>= allocated 0) allocated))
              (cons 'p50-ns (list-ref ordered (quotient (- count 1) 2)))
              (cons 'p95-ns p95) (cons 'max-ns (list-ref ordered (- count 1))))))
    (when limit (check (< p95 limit) => #t))))

(def (chain-shortcut group width offset)
  (let (first (+ offset (* group width)))
    (list first (+ first 2))))

(def (make-query-cut groups width offset shortcuts?)
  (let (base (edges groups width offset))
    (if shortcuts?
      ;; A redundant edge breaks the one-successor premise. The independent
      ;; closure oracle still expects exactly the same set and cardinality.
      (append base
        (map (lambda (group) (chain-shortcut group width offset)) (iota groups)))
      base)))

(def (measure-chain-query groups width recursive? shortcuts? append-shortcuts? copy-into
                          requests latency-limit (shard #f))
  (check (##current-vm-processor-count) => 1)
  (when (or shortcuts? append-shortcuts?)
    (check (and recursive? (>= width 3)) => #t))
  (when append-shortcuts? (check (and (not shortcuts?) (>= groups 1000)) => #t))
  (receipt 'prepare-start (list (cons 'groups groups) (cons 'width width)
                               (cons 'recursive recursive?)))
  (let* ((input (* groups (if shortcuts? width (- width 1))))
         (capacity (if append-shortcuts? (+ input requests) input))
         (output (if recursive? (output-count groups width) input))
         (span (* groups width))
         (begin (tick))
         (first (make-query-cut groups width 0 shortcuts?))
         (second (and (not append-shortcuts?) (make-query-cut groups width span shortcuts?)))
         (first-request (if shard (* shard requests) 0))
         (alternate-first? (even? first-request))
         (initial (if alternate-first? first second))
         (initial-offset (if alternate-first? 0 span))
         (session (open-session initial groups width recursive? input-facts: capacity))
         (oracle-fallbacks 0)
         (verify-rows (if shard
                        (make-ordered-chain-verifier groups width
                          (lambda () (set! oracle-fallbacks (+ oracle-fallbacks 1))))
                        (make-chain-verifier groups width recursive?)))
         (deliver
          (and copy-into
               (let (buffer (make-s64vector (* 2 output)))
                 (lambda (session)
                   (let (count (copy-into session 'reach buffer))
                     (unless (eqv? count output) (error "incomplete caller-buffer delivery" count))
                     buffer)))))
         (samples (make-f64vector requests 0.))
         (shard-info (if shard
                       (list (cons 'delivery (if deliver 'buffer 'list))
                             (cons 'groups groups) (cons 'width width)
                             (cons 'shard shard) (cons 'first-request first-request))
                       [])))
    (try
      (receipt 'prepared (list (cons 'input-facts input) (cons 'expected-rows output)
                               (cons 'input-fact-capacity capacity)
                               (cons 'recursive recursive?) (cons 'wall-ns (nanoseconds begin))))
      (let (cost (make-f64vector 3 0.))
        (let-values (((run-ns export-ns oracle-ns) (query session verify-rows initial-offset cost #f deliver)))
          (let (cold (+ run-ns export-ns))
            (receipt 'cold-complete-query
              (list (cons 'query-and-export-ns cold) (cons 'with-oracle-ns (+ cold oracle-ns))
                    (cons 'exported-rows output))))
          (report-query-work 'cold-query-phases 1 0 run-ns export-ns oracle-ns
            (+ run-ns export-ns oracle-ns) cost)))
      (set! oracle-fallbacks 0)
      (let ((start (tick)) (cpu (cpu-time)) (before (##process-statistics))
            (replace-total 0) (run-total 0) (export-total 0) (oracle-total 0)
            (cost (make-f64vector 3 0.)))
        (let loop ((index 0))
          (unless (= index requests)
            (let* ((use-second? (and second (eq? (even? index) alternate-first?)))
                   (offset (if use-second? span 0))
                   (request (tick)))
              (if append-shortcuts?
                (gerbil-ascent-session-append-source! session 'edge (chain-shortcut index width 0))
                (gerbil-ascent-session-replace-source! session 'edge (if use-second? second first)))
              (let ((replace-ns (nanoseconds request)))
                (let-values (((run-ns export-ns oracle-ns)
                              (query session verify-rows offset cost
                                (and append-shortcuts? (+ input index 1)) deliver)))
                  (set! replace-total (+ replace-total replace-ns))
                  (set! run-total (+ run-total run-ns))
                  (set! export-total (+ export-total export-ns))
                  (set! oracle-total (+ oracle-total oracle-ns))))
              (f64vector-set! samples index (exact->inexact (nanoseconds request))))
            (when (zero? (modulo (+ index 1) 10))
              (report-query-work 'progress (+ index 1) replace-total run-total export-total
                oracle-total (nanoseconds start) cost))
            (loop (+ index 1))))
        (let ((elapsed (nanoseconds start)) (used (- (cpu-time) cpu)))
          (report-samples (cond (shard 'ten-million-delivery)
                                (deliver 'changed-buffer-query)
                                (append-shortcuts? 'appended-complete-query)
                                (else 'changed-complete-query))
            input output samples elapsed used before #f latency-limit
            (if shard (cons (cons 'oracle-fallbacks oracle-fallbacks) shard-info) []))
          (when shard
            (report-query-work 'ten-million-phases requests replace-total run-total
              export-total oracle-total elapsed cost))))
      (finally (gerbil-ascent-session-close! session)))))

(def (million-query groups width recursive? shortcuts?: (shortcuts? #f)
                    append-shortcuts?: (append-shortcuts? #f) copy-into: (copy-into #f))
  (measure-chain-query groups width recursive? shortcuts? append-shortcuts? copy-into
    1000 (if copy-into 50000000 100000000)))

(def (ten-million-groups width)
  (case width
    ((128) 1240)
    ((512) 77)
    (else (error "unsupported delivery chain width" width))))

(def (ten-million-shard)
  (let (shard (string->number (getenv "ASCENT_DELIVERY_SHARD" "0")))
    (unless (and (fixnum? shard) (fx<= 0 shard) (fx< shard 40))
      (error "ASCENT_DELIVERY_SHARD must be an integer from 0 to 39" shard))
    shard))

(def (ten-million-query width (copy-into #f))
  (let ((groups (ten-million-groups width)) (shard (ten-million-shard)))
    (receipt 'ten-million-plan
      (list (cons 'delivery (if copy-into 'buffer 'list))
            (cons 'groups groups) (cons 'width width)
            (cons 'shard shard) (cons 'planned-requests 25)))
    (measure-chain-query groups width #t #f #f copy-into 25 #f shard)))

(def (ten-million-paged-query width)
  (check (##current-vm-processor-count) => 1)
  (let* ((groups (ten-million-groups width)) (shard (ten-million-shard))
         (expected (output-count groups width)) (span (* groups width))
         (first (make-query-cut groups width 0 #f))
         (second (make-query-cut groups width span #f))
         (start-with-first? (even? shard))
         (session (open-session (if start-with-first? first second) groups width #t))
         (page-width 8192) (buffer (make-s64vector (* 2 page-width)))
         (requests 25) (first-page (make-f64vector requests)) (completion (make-f64vector requests)))
    (def (deliver offset start)
      (unless (.ref (gerbil-ascent-session-run session) 'finished) (error "query did not finish"))
      (let* ((cursor (gerbil-ascent-session-open-integer-pages session 'reach page-width expected))
             (remaining expected) (cell 0)
             (size (* 2 (gerbil-ascent-session-pull-integer-page! session cursor buffer)))
             (first-ns (nanoseconds start)))
        (unless (= size (* 2 page-width)) (error "incorrect first page size" size))
        (for-each-expected-chain-row groups width offset (left right)
          (when (fx= cell size)
            (let (received (gerbil-ascent-session-pull-integer-page! session cursor buffer))
              (unless (= received (min remaining page-width))
                (error "incorrect page size" received remaining))
              (set! size (fx* 2 received))
              (set! cell 0)))
          (unless (and (eq? left (##s64vector-ref buffer cell))
                       (eq? right (##s64vector-ref buffer (fx+ cell 1))))
            (error "page order or row mismatch" left right remaining))
          (set! cell (fx+ cell 2))
          (set! remaining (fx- remaining 1)))
        (unless (and (= remaining 0) (= size cell)
                     (= 0 (gerbil-ascent-session-pull-integer-page! session cursor buffer)))
          (error "incomplete paged delivery" remaining))
        first-ns))
    (try
      (let* ((start (tick)) (first-ns (deliver (if start-with-first? 0 span) start)))
        (receipt 'cold-ten-million-pages
          (list (cons 'first-page-ns first-ns) (cons 'complete-ns (nanoseconds start)))))
      (let ((start (tick)) (cpu (cpu-time)) (before (##process-statistics)))
        (for-each
          (lambda (i)
            (let* ((initial? (eq? (even? i) start-with-first?)) (request (tick)))
              (gerbil-ascent-session-replace-source! session 'edge (if initial? second first))
              (let (first-ns (deliver (if initial? span 0) request))
                (f64vector-set! first-page i (exact->inexact first-ns))
                (f64vector-set! completion i (exact->inexact (nanoseconds request))))))
          (iota requests))
        (let ((wall (nanoseconds start)) (used (- (cpu-time) cpu)))
          (report-samples 'ten-million-paged-delivery (* groups (- width 1)) expected
            completion wall used before #f #f
            (list (cons 'width width) (cons 'groups groups) (cons 'shard shard)
                  (cons 'first-request (* shard requests)) (cons 'page-rows page-width)))
          (receipt 'first-page-samples (f64vector->list first-page))))
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

(def actor-million-state-contention-test
  (test-suite "concurrent callers of one resident Actor Session"
    (test-case "one million verified mailbox replies shared across concurrent callers"
      (check (##current-vm-processor-count) => 1)
      (let* ((count 1000000)
             (callers (max 2 (##cpu-count)))
             (prepare (tick))
             (rows (edges count 2 0))
             (session (open-session rows count 2 #f))
             (samples (make-f64vector count 0.))
             (start-signal (make-completion 'actor-state-measurement)))
        (try
          (let (clients
                (map (lambda (slot)
                       (let ((from (quotient (* slot count) callers))
                             (until (quotient (* (+ slot 1) count) callers)))
                         (spawn (lambda ()
                           (completion-wait! start-signal)
                           (do ((i from (+ i 1))) ((= i until) (- until from))
                             (let* ((request (tick)) (state (gerbil-ascent-session-state session)))
                               (unless (equal? state '(0 idle))
                                 (error "unexpected concurrent Session state" state))
                               (f64vector-set! samples i
                                 (exact->inexact (nanoseconds request)))))))))
                     (iota callers)))
            (receipt 'state-contention-prepared (list (cons 'callers callers)
                                                     (cons 'wall-ns (nanoseconds prepare))))
            (let ((start (tick)) (cpu (cpu-time)) (before (##process-statistics)))
              (completion-post! start-signal #t)
              (let* ((verified (apply + (map thread-join! clients)))
                     (wall (nanoseconds start)) (used (- (cpu-time) cpu)))
                (check verified => count)
                (report-samples 'resident-state-contention count 0 samples wall used before))))
          (finally (gerbil-ascent-session-close! session)))))))

(def actor-million-oracle-test
  (test-suite "million-workload oracle refusal controls"
    (test-case "chain inputs preserve the release order across SDKs"
      (check (edges 2 4 10) => '((12 13) (11 12) (10 11) (16 17) (15 16) (14 15)))
      (check (edges 2 2 10) => '((10 11) (12 13))))
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
    (test-case "bitmap lanes accept reordering and reject malformed or foreign rows"
      (check (verify '((2 3) (0 1)) 2 2 0 #f) => 2)
      (check (verify '((4 5) (0 1) (3 4) (1 2)) 2 3 0 #f) => 4)
      (check (verify '((-3 -1) (-2 -1) (-3 -2)) 1 3 -3 #t) => 3)
      (for-each (lambda (rows) (check-exception (verify rows 2 2 0 #f) true))
        '(((0 1) (0 1)) ((0 1) (1 2)) ((0 1) (2 3 4))
          ((0 1) (2 3.0)) ((0 1) (2 . 3)) ((0 1) (3 4))
          ((0 1) . invalid)))
      (let (offset (expt 2 80))
        (check (verify (list (list offset (+ offset 1))) 1 2 offset #f) => 1)))
    (test-case "the bitmap is clean after acceptance and rejection across cuts"
      (let (verify-rows (make-chain-verifier 1 3 #t))
        (check (verify-rows '((0 2) (0 1) (1 2)) 0) => 3)
        (check-exception (verify-rows '((3 4) (3 4) (4 5)) 3) true)
        (check (verify-rows '((4 5) (3 4) (3 5)) 3) => 3)
        (check-exception (verify-rows '((4 5) (3 4) (3 5)) 0) true)
        (check (verify-rows '((0 1) (1 2) (0 2)) 0) => 3)))
    (test-case "ordered oracle verifies both representations and retains unordered acceptance"
      (let* ((fallbacks 0)
             (check-rows (make-ordered-chain-verifier 2 3
                           (lambda () (set! fallbacks (+ fallbacks 1)))))
             (rows '((3 5) (0 2) (1 2) (0 1) (4 5) (3 4))))
        (check (check-rows rows 0) => 6)
        (check (check-rows '#s64(3 5 0 2 1 2 0 1 4 5 3 4) 0) => 6)
        (check fallbacks => 0)
        (check (check-rows (reverse rows) 0) => 6)
        (check fallbacks => 1)
        (check-exception (check-rows (cdr rows) 0) true)
        (check-exception (check-rows (cons (cadr rows) (cdr rows)) 0) true)
        (check-exception (check-rows rows 6) true)
        (check-exception (check-rows '#s64(3 5 0 2 1 2 0 1 4 5 4 5) 0) true)
        (check-exception (check-rows '#s64(3 5 0 2 1 2 0 1 4 5) 0) true)
        (check (check-rows rows 0) => 6)))
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

(def actor-ten-thousand-closure-test
  (test-suite "ten-thousand-row recursive Actor query"
    (test-case "1000 functional chains with 10000 derived rows"
      (million-query 1000 5 #t))
    (test-case "1000 branched chains with the same 10000 derived rows"
      (million-query 1000 5 #t shortcuts?: #t))
    (test-case "one redundant edge per update preserves all 10000 derived rows"
      (million-query 1000 5 #t append-shortcuts?: #t))))

;; For this projection the i-th row is (offset + 2i, offset + 2i + 1).
;; Check that sequence online through either delivery method.
(def (verify-ordered-delivery result offset count mode start)
  (let ((next offset) (end (+ offset (* 2 count))) (first #f))
    (def (accept-fields left right)
      (unless first (set! first (nanoseconds start)))
      (unless (and (< next end) (eqv? left next) (eqv? right (+ next 1)))
        (error "unexpected or extra delivered row" next left right))
      (set! next (+ next 2)))
    (def (accept-row row)
      (unless (and (pair? row) (pair? (cdr row)) (null? (cddr row)))
        (error "unexpected delivery row shape" row))
      (accept-fields (car row) (cadr row)))
    (case mode
      ((changed-visit) ((.ref result 'visit-rows) 'reach [] [] accept-row))
      ((changed-fields) ((.ref result 'visit-rows) 'reach [] [] accept-fields fields?: #t))
      (else (for-each accept-row ((.ref result 'rows-of) 'reach))))
    (unless (and (= next end) first)
      (error "incomplete ordered delivery" next end))
    first))

(def (million-order-delivery phase)
  (check (##current-vm-processor-count) => 1)
  (let* ((count 1000000) (span (* 2 count))
         (prepare (tick))
         (original (edges count 2 0)) (alternate (edges count 2 span))
         (session (open-session original count 2 #f))
         (all (make-f64vector 1000 0.))
         (first (make-f64vector 1000 0.)))
    (try
      (receipt 'delivery-prepared (list (cons 'mode phase)
                                    (cons 'wall-ns (nanoseconds prepare))))
      (let ((start (tick)) (cpu (cpu-time)) (before (##process-statistics))
            (updates 0) (runs 0) (deliveries 0))
        (do ((i 0 (+ i 1))) ((= i 1000))
          (let* ((request (tick)) (use-alternate? (even? i))
                 (offset (if use-alternate? span 0)))
            (gerbil-ascent-session-replace-source! session 'edge
              (if use-alternate? alternate original))
            (let* ((update (nanoseconds request))
                   (result (gerbil-ascent-session-run session))
                   (ready (nanoseconds request)))
              (unless (.ref result 'finished) (error "query did not finish"))
              (let* ((arrived (verify-ordered-delivery result offset count phase request))
                     (delivered (nanoseconds request)))
                (f64vector-set! first i (exact->inexact arrived))
                (f64vector-set! all i (exact->inexact delivered))
                (set! updates (+ updates update))
                (set! runs (+ runs (- ready update)))
                (set! deliveries (+ deliveries (- delivered ready))))))
          (when (zero? (modulo (+ i 1) 100))
            (receipt 'delivery-progress
              (list (cons 'mode phase) (cons 'verified-requests (+ i 1))
                    (cons 'wall-ns (nanoseconds start))))))
        (let ((wall (nanoseconds start)) (used (- (cpu-time) cpu)))
          ;; Emit both receipts before the full-window gate can fail.
          (let (ordered (list-sort < (f64vector->list first)))
            (receipt 'delivery-first-row
              (list (cons 'mode phase) (cons 'p50-ns (list-ref ordered 499))
                    (cons 'p95-ns (list-ref ordered 949)) (cons 'max-ns (list-ref ordered 999)))))
          (receipt 'delivery-work
            (list (cons 'mode phase) (cons 'update-ns updates)
                  (cons 'run-and-publish-ns runs) (cons 'delivery-and-oracle-ns deliveries)))
          (report-samples phase count count all wall used before)))
      (finally (gerbil-ascent-session-close! session)))))

(def actor-million-list-delivery-test
  (test-suite "actor complete lists on changing million-row sources"
    (test-case "verify a billion rows delivered as detached lists"
      (million-order-delivery 'changed-list))))

(def actor-million-visit-test
  (test-suite "actor ordered visitor on changing million-row sources"
    (test-case "verify a billion rows delivered through the public visitor"
      (million-order-delivery 'changed-visit))))

(def actor-million-fields-test
  (test-suite "actor field delivery on changing million-row sources"
    (test-case "verify a billion rows delivered as positional fields"
      (million-order-delivery 'changed-fields))))

(def actor-million-fields-controls-test
  (test-suite "Actor result field visitor ownership and selection"
    (test-case "the cursor keeps its old cut when a callback replaces the source"
      (let* ((original (edges 32 2 0)) (alternate (edges 32 2 64))
             (session (open-session original 32 2 #f))
             (seen []))
        (try
          (let (old (gerbil-ascent-session-run session))
            ((.ref old 'visit-rows) 'reach [] []
             (lambda (left right)
               (when (null? seen)
                 (gerbil-ascent-session-replace-source! session 'edge alternate)
                 (gerbil-ascent-session-run session))
               (set! seen (cons (list left right) seen)))
             fields?: #t)
            (check (reverse seen) => original)
            (check ((.ref (gerbil-ascent-session-last-completed session) 'rows-of) 'reach)
              => alternate))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "field delivery honours key checks and a callback exit"
      (let (session (open-session (edges 32 2 0) 32 2 #f))
        (try
          (let* ((result (gerbil-ascent-session-run session))
                 (visit (.ref result 'visit-rows)) (seen []))
            (visit 'reach '(0 0) '(4 6)
              (lambda (l r) (error "conflicting key returned row" l r)) fields?: #t)
            (check-exception (visit 'reach '(2) '(4) void fields?: #t) true)
            (check (call/cc (lambda (done)
                     (visit 'reach '(0 1) '(4 5)
                       (lambda (l r) (done (list l r))) fields?: #t)
                     #f))
              => '(4 5))
            (call/cc (lambda (done)
              (visit 'reach [] []
                (lambda (l r) (set! seen (cons (list l r) seen)) (done #t)) fields?: #t)))
            (check seen => '((0 1))))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "the ordinary representation supplies all fields without a packed view"
      (let* ((program (gerbil-ascent-program
                        (list (gerbil-ascent-relation 'item 3 '((a b c)))) [] 1 1 2))
             (session (gerbil-ascent-open-actor-session program workers: 1))
             (seen []))
        (try
          (let (result (gerbil-ascent-session-run session))
            ((.ref result 'visit-rows) 'item '(2) '(c)
             (lambda (a b c) (set! seen (list a b c))) fields?: #t)
            (check seen => '(a b c)))
          (finally (gerbil-ascent-session-close! session)))))))

(def actor-packed-reuse-controls-test
  (test-suite "Actor exact packed replacement"
    (test-case "equal new input shares values while a changed terminal field stays visible"
      (let* ((a (edges 32 2 0))
             (b (edges 32 2 64))
             (a-copy (edges 32 2 0))
             (session (open-session a 32 2 #f)))
        (try
          (let (old (gerbil-ascent-session-run session))
            (gerbil-ascent-session-replace-source! session 'edge b)
            (check ((.ref (gerbil-ascent-session-run session) 'rows-of) 'reach) => b)
            (gerbil-ascent-session-replace-source! session 'edge a-copy)
            (let ((repeated (gerbil-ascent-session-run session))
                  (last (list-ref a-copy 31)))
              (check ((.ref repeated 'rows-of) 'reach) => a)
              (set-car! (cdr last) -9)
              (gerbil-ascent-session-replace-source! session 'edge b)
              (gerbil-ascent-session-run session)
              (gerbil-ascent-session-replace-source! session 'edge a-copy)
              (let* ((updated (gerbil-ascent-session-run session))
                     (delivered ((.ref updated 'rows-of) 'reach)))
                (check delivered => a-copy)
                (set-car! (cdr (list-ref delivered 31)) -17)
                (check ((.ref updated 'rows-of) 'reach) => a-copy)
                (check ((.ref repeated 'rows-of) 'reach) => a)
                (check ((.ref old 'rows-of) 'reach) => a))))
          (finally (gerbil-ascent-session-close! session)))))))

;; Keep complete-result validation outside the request timer. Window throughput
;; includes it, and the receipt accounts for its wall time separately.
(def (measure-query-delivery mode (groups 10000))
  (check (##current-vm-processor-count) => 1)
  (let* ((append? (eq? mode 'append))
         (initial (if append? (- groups 1000) groups))
         (original (edges initial 2 0))
         (alternate (and (eq? mode 'replace) (edges groups 2 (* 2 groups))))
         (session (open-session original groups 2 #f))
         (samples (make-f64vector 1000 0.))
         (replace-total 0) (run-total 0) (export-total 0) (oracle-total 0))
    (try
      (let (published (gerbil-ascent-session-run session))
        (unless (.ref published 'finished) (error "query did not finish"))
        (verify ((.ref published 'rows-of) 'reach) initial 2 0 #f))
      (let ((start (tick)) (cpu (cpu-time)) (before (##process-statistics)))
        (do ((i 0 (+ i 1))) ((= i 1000))
          (let* ((request (tick))
                 (offset (if (and alternate (even? i)) (* 2 groups) 0))
                 (expected (if append? (+ initial i 1) groups))
                 (origin (* 2 (modulo (* i 7919) expected))))
            (case mode
              ((append)
               (let (left (* 2 (- expected 1)))
                 (gerbil-ascent-session-append-source! session 'edge (list left (+ left 1)))))
              ((replace)
               (gerbil-ascent-session-replace-source! session 'edge
                 (if (zero? offset) original alternate))))
            (let* ((update-ns (nanoseconds request))
                   (result (if (or append? alternate) (gerbil-ascent-session-run session)
                             (gerbil-ascent-session-last-completed session)))
                   (ready-ns (nanoseconds request)))
              (unless (.ref result 'finished) (error "query did not finish"))
              (let* ((rows
                      (if (eq? mode 'indexed)
                        (let ((row #f) (count 0))
                          ((.ref result 'visit-rows) 'reach '(0) (list origin)
                           (lambda (match) (set! count (+ count 1)) (set! row match)))
                          (unless (= count 1) (error "unexpected indexed cardinality" count))
                          row)
                        ((.ref result 'rows-of) 'reach)))
                     (delivered-ns (nanoseconds request)))
                (f64vector-set! samples i (exact->inexact delivered-ns))
                (if (eq? mode 'indexed)
                  (unless (equal? rows (list origin (+ origin 1)))
                    (error "incorrect indexed row" rows))
                  (verify rows expected 2 offset #f))
                (set! replace-total (+ replace-total update-ns))
                (set! run-total (+ run-total (- ready-ns update-ns)))
                (set! export-total (+ export-total (- delivered-ns ready-ns)))
                (set! oracle-total (+ oracle-total (- (nanoseconds request) delivered-ns)))))))
        (receipt 'delivery-shape
          (list (cons 'mode mode) (cons 'initial-facts initial)
                (cons 'last-facts groups) (cons 'request-samples 1000)))
        (report-samples mode groups
          (case mode ((indexed) 1) ((append) #f) (else groups))
          samples (nanoseconds start) (- (cpu-time) cpu) before
          (and append? (+ (* initial 1000) (quotient (* 1000 1001) 2))))
        (receipt 'delivery-phases
          (list (cons 'mode mode) (cons 'update-ns replace-total)
                (cons 'ready-ns run-total) (cons 'delivery-ns export-total)
                (cons 'oracle-ns oracle-total))))
      (finally (gerbil-ascent-session-close! session)))))

(def actor-query-delivery-test
  (test-suite "ten-thousand-row production Actor query delivery"
    (test-case "indexed lookup of a published relation"
      (measure-query-delivery 'indexed))
    (test-case "detached export of a published relation"
      (measure-query-delivery 'published))
    (test-case "recompute and export after full replacement"
      (measure-query-delivery 'replace))
    (test-case "recompute and export after one append"
      (measure-query-delivery 'append))
    (test-case "ordered append keeps old publications and refuses excess input"
      (for-each
        (lambda (ascending?)
          (let* ((rows (edges 32 2 0))
                 (rows (if ascending? rows (reverse rows)))
                 (extra (if ascending? (list 64 65) (list -2 -1)))
                 (saved (map identity extra))
                 (session (open-session rows 34 2 #f)))
            (try
              (let (old (gerbil-ascent-session-run session))
                (gerbil-ascent-session-append-source! session 'edge extra)
                (set-car! extra 9000)
                (let* ((current (gerbil-ascent-session-run session))
                       (delivered ((.ref current 'rows-of) 'reach))
                       (hits []))
                  (check delivered => (append rows (list saved)))
                  ((.ref current 'visit-rows) 'reach '(0) (list (car saved))
                   (lambda (row) (set! hits (cons row hits))))
                  (check hits => (list saved))
                  (set-car! (car delivered) 9001)
                  (check ((.ref current 'rows-of) 'reach) => (append rows (list saved)))
                  (check ((.ref old 'rows-of) 'reach) => rows)
                  ;; A duplicate falls back to normal set semantics, while
                  ;; its physical occurrence still consumes input budget.
                  (gerbil-ascent-session-append-source! session 'edge saved)
                  (let (after (gerbil-ascent-session-run session))
                    (check (length ((.ref after 'rows-of) 'reach)) => 33)
                    (check-exception
                      (gerbil-ascent-session-append-source! session 'edge (list 10000 10001))
                      true)
                    (check (eq? (gerbil-ascent-session-last-completed session) after) => #t))))
              (finally (gerbil-ascent-session-close! session)))))
        '(#t #f)))))

;; Diagnostic: one controller races each real closure with a bounded burst
;; of public state requests. An in-flight reply reports the admitted epoch.
(export actor-closure-state-overlap-test)
(def actor-closure-state-overlap-test
  (test-suite "public state replies during large recursive queries"
    (test-case "one Session verifies concurrent state and recursive results"
      (check (##current-vm-processor-count) => 1)
      (let* ((groups 128) (width 128) (span (* groups width))
             (rounds 64) (burst 32)
             (first (edges groups width 0))
             (other (edges groups width span))
             (session (open-session first groups width #t))
             (samples []) (running []) (overlap-rounds 0)
             (run-total 0) (oracle-total 0))
        (def (distribution label values)
          (let* ((ordered (list-sort < values)) (count (length ordered)))
            (when (> count 0)
              (receipt label
                (list (cons 'count count)
                      (cons 'p50-ns (list-ref ordered (quotient (- count 1) 2)))
                      (cons 'p95-ns (list-ref ordered (- (quotient (+ (* count 95) 99) 100) 1)))
                      (cons 'p99-ns (list-ref ordered (- (quotient (+ (* count 99) 99) 100) 1)))
                      (cons 'max-ns (list-ref ordered (- count 1))))))))
        (try
          (let ((start (tick)) (cpu (cpu-time)) (before (##process-statistics)))
            (do ((round 0 (+ round 1))) ((= round rounds))
              (let* ((swap? (even? round))
                     (offset (if swap? span 0))
                     (before-run
                      (begin
                        (gerbil-ascent-session-replace-source! session 'edge (if swap? other first))
                        (gerbil-ascent-session-state session)))
                     (epoch (+ (car before-run) 1))
                     (observed? #f))
                (check (cadr before-run) => 'idle)
                (let ((runner (spawn (lambda ()
                                       (let* ((began (tick))
                                              (result (gerbil-ascent-session-run session)))
                                         (vector result (nanoseconds began))))))
                      (last-generation (car before-run)))
                  (try
                    (do ((i 0 (+ i 1))) ((= i burst))
                      (let* ((begin (tick))
                             (state (gerbil-ascent-session-state session))
                             (elapsed (nanoseconds begin))
                             (generation (car state))
                             (phase (cadr state)))
                        (unless (and (<= last-generation generation epoch)
                                     (or (eq? phase 'idle)
                                         (and (eq? phase 'running) (= generation epoch))))
                          (error "unexpected Actor state order" round state))
                        (set! last-generation generation)
                        (set! samples (cons elapsed samples))
                        (when (eq? phase 'running)
                          (set! observed? #t)
                          (set! running (cons elapsed running)))))
                    (let* ((outcome (thread-join! runner))
                           (result (vector-ref outcome 0))
                           (verify-start (tick)))
                      (unless (.ref result 'finished) (error "incomplete concurrent result"))
                      (verify ((.ref result 'rows-of) 'reach) groups width offset #t)
                      (set! oracle-total (+ oracle-total (nanoseconds verify-start)))
                      (set! run-total (+ run-total (vector-ref outcome 1))))
                    (finally (thread-join! runner)))
                  (check (gerbil-ascent-session-state session) => (list epoch 'idle)))
                (when observed? (set! overlap-rounds (+ overlap-rounds 1)))))
            (let ((after (##process-statistics)))
              (receipt 'closure-and-state
                (list (cons 'verified-queries rounds)
                      (cons 'rows-per-query (output-count groups width))
                      (cons 'rounds-with-running-state overlap-rounds)
                      (cons 'verified-state-requests (length samples))
                      (cons 'wall-ns (nanoseconds start))
                      (cons 'cpu-s (- (cpu-time) cpu))
                      (cons 'gc-wall-s (- (f64vector-ref after 5) (f64vector-ref before 5)))
                      (cons 'collections (- (f64vector-ref after 6) (f64vector-ref before 6)))
                      (cons 'run-total-ns run-total)
                      (cons 'export-and-oracle-total-ns oracle-total))))
            (distribution 'closure-all-state samples)
            (distribution 'closure-running-state running)
            (check (length samples) => (* rounds burst))
            (check (> overlap-rounds 0) => #t))
          (finally (gerbil-ascent-session-close! session)))))))
