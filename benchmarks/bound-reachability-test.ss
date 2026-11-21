;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/iter for in-range)
        (only-in :std/list/list-builder with-list-builder)
        (only-in :gerbil/runtime/gambit call-with-input-string)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/core/positive-plan call-with-positive-plan-cost make-positive-plan-cost
                 positive-plan-cost-snapshot positive-plan-cost-visits)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/program/func gerbil-ascent-program gerbil-ascent-relation
                 gerbil-ascent-literal gerbil-ascent-variable gerbil-ascent-rule gerbil-ascent-atom)
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session
                 gerbil-ascent-session-run gerbil-ascent-session-replace-source! gerbil-ascent-session-append-source!)
        (only-in :gerbil-ascent/program/actor-session gerbil-ascent-open-actor-session
                 gerbil-ascent-session-close!)
        :gerbil-ascent/program/bound-reachability)
(export bound-reachability-demand-test bound-reachability-session-test bound-reachability-counter-test
        bound-reachability-edits-test bound-reachability-shape-test)

(def vertex-count 22687)
(def edge-count 54705)
(def origin 680)
(def neighbor 681)
(def work-limit 200000)
(def clock (make-u64vector 1 0))
(def frequency (begin (##get-monotonic-time-frequency! clock 0) (u64vector-ref clock 0)))

(def (tick)
  (##get-monotonic-time! clock 0)
  (u64vector-ref clock 0))

(def (record! timings name sample)
  (hash-update! timings name (lambda (prior) (cons sample prior)) []))

(def (timed timings name thunk)
  (let* ((start (tick)) (value (thunk)) (elapsed (- (tick) start)))
    (record! timings name elapsed)
    value))

(def (combine! timings name . phases)
  (record! timings name
    (foldl (lambda (phase sum) (+ sum (car (hash-ref timings phase)))) 0 phases)))

(def (report timings tag unit scale)
  (for-each
    (lambda (name)
      (let* ((sorted (list-sort < (hash-ref timings name)))
             (count (length sorted))
             (p50 (list-ref sorted (- (quotient (+ (* 50 count) 99) 100) 1)))
             (p95 (list-ref sorted (- (quotient (+ (* 95 count) 99) 100) 1)))
             (worst (list-ref sorted (- count 1))))
        (write (list tag name count unit (* scale p50) (* scale p95) (* scale worst))) (newline)))
    (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) (hash-keys timings)))
  (force-output))

(def (load-edges)
  (call-with-input-file (getenv "ASCENT_GNUTELLA25")
    (lambda (input)
      (let loop ((rows []))
        (let (line (read-line input))
          (cond
            ((eof-object? line) (reverse! rows))
            ((or (zero? (string-length line)) (char=? (string-ref line 0) #\#)) (loop rows))
            (else
             (loop (cons (call-with-input-string line (lambda (tokens) (list (read tokens) (read tokens))))
                         rows)))))))))

(def (cut rows)
  (filter (lambda (row) (not (equal? row (list origin neighbor)))) rows))

;; This oracle computes the entire bound result with a FIFO and a dense array.
;; It can also count the edge examines in that algorithm up to the first hit.
(def (oracle rows from)
  (let ((adjacent (make-vector vertex-count [])) (selected (make-vector vertex-count #f))
        (queue (make-vector vertex-count 0)) (tail 0) (scans 0))
    (for-each (lambda (row)
                (let ((from (car row)) (to (cadr row)))
                  (vector-set! adjacent from (cons to (vector-ref adjacent from))))) rows)
    (def (visit source)
      (for-each
        (lambda (target)
          (set! scans (+ scans 1))
          (unless (vector-ref selected target)
            (vector-set! selected target scans)
            (vector-set! queue tail target)
            (set! tail (+ tail 1))))
        (vector-ref adjacent source)))
    (visit from)
    (let advance ((head 0))
      (when (< head tail)
        (visit (vector-ref queue head))
        (advance (+ head 1))))
    (values selected scans adjacent)))

(def (validate-path path from to adjacent)
  (unless (and (pair? (cdr path)) (= from (car path))
               (let walk ((rest path))
                 (if (null? (cdr rest)) (= to (car rest))
                   (and (memv (cadr rest) (vector-ref adjacent (car rest))) (walk (cdr rest))))))
    (error "invalid dataset witness" from to path)))

(def (prepare rows)
  (gerbil-ascent-open-bound-reachability rows edge-limit: edge-count work-limit: work-limit))

(def (measure-query graph from to test expected adjacent timings work witness-phase)
  (let* ((query (timed timings test
                  (lambda () (call-with-values
                    (lambda () (gerbil-ascent-bound-reachability-query graph from to work-limit: work-limit)) cons))))
         (proof (car query)))
    (record! work test (cdr query))
    (unless (eq? (and proof #t) (and expected #t))
      (error "indexed demand disagrees with full oracle" test from to))
    (when proof
      (let (path (timed timings (car witness-phase)
                   (lambda () (gerbil-ascent-bound-reachability-path proof work-limit: work-limit))))
        (unless (timed timings (cadr witness-phase)
                  (lambda () (gerbil-ascent-bound-reachability-verify graph proof work-limit: work-limit)))
          (error "witness lost its graph version"))
        (validate-path path from to adjacent)))
    proof))

(def bound-reachability-demand-test
  (test-suite "Versioned demand over the complete SNAP p2p-Gnutella25 graph"
    (test-case "Cold index, updates, first probes and version witnesses"
      (let* ((rows (load-edges)) (deleted (cut rows)) (timings (make-hash-table-eq)) (work (make-hash-table-eq)))
        (check (length rows) => edge-count)
        (check (length deleted) => (- edge-count 1))
        (write (list 'SOURCE 'initial edge-count 'delete-replacement (length deleted) 'restore-appended 1))
        (newline)
        (let-values (((full scans adjacent) (oracle rows origin))
                     ((after after-scans after-adjacent) (oracle deleted origin))
                     ((cycle cycle-scans cycle-adjacent) (oracle rows 0)))
          (write (list 'ORACLE 'bound-closure scans after-scans cycle-scans
                       'near (vector-ref full neighbor) 'far (vector-ref full 22686)))
          (newline)
          (let (graph #f)
            (for (_ (in-range 16))
              (set! graph (timed timings 'cold-index (lambda () (prepare rows))))
              (measure-query graph origin neighbor 'cold-first (vector-ref full neighbor) adjacent timings work
                '(near-witness-export near-witness-verify))
              (combine! timings 'cold-ready 'cold-index 'cold-first))
            (let (prior (measure-query graph origin neighbor 'baseline-version
                          (vector-ref full neighbor) adjacent timings work '(near-witness-export near-witness-verify)))
              (for (_ (in-range 1000))
                (let* ((edit (timed timings 'delete
                               (lambda () (call-with-values
                                 (lambda () (gerbil-ascent-bound-reachability-edit
                                             graph origin neighbor #f work-limit: work-limit)) list))))
                       (removed (car edit)))
                  (unless (= (cadr edit) 2) (error "delete rebuilt an unexpected number of buckets"))
                  (record! work 'delete-buckets (cadr edit))
                  (record! work 'delete-edge-reads (caddr edit))
                  (measure-query removed origin neighbor 'after-delete
                    (vector-ref after neighbor) after-adjacent timings work '(near-witness-export near-witness-verify))
                  (combine! timings 'delete-to-first 'delete 'after-delete)
                  (when (gerbil-ascent-bound-reachability-verify removed prior)
                    (error "deleted version accepted old witness"))
                  (let* ((edit (timed timings 'restore
                                 (lambda () (call-with-values
                                   (lambda () (gerbil-ascent-bound-reachability-edit
                                               removed origin neighbor #t work-limit: work-limit)) list))))
                         (restored (car edit)))
                    (unless (= (cadr edit) 2) (error "restore rebuilt an unexpected number of buckets"))
                    (record! work 'restore-buckets (cadr edit))
                    (record! work 'restore-edge-reads (caddr edit))
                    (measure-query restored origin neighbor 'after-restore-near
                      (vector-ref full neighbor) adjacent timings work '(near-witness-export near-witness-verify))
                    (combine! timings 'restore-to-near 'restore 'after-restore-near)
                    (measure-query restored origin 22686 'after-restore-far
                      (vector-ref full 22686) adjacent timings work '(far-witness-export far-witness-verify))
                    (combine! timings 'restore-to-far 'restore 'after-restore-far)
                    (measure-query restored 0 origin 'after-restore-miss
                      (vector-ref cycle origin) cycle-adjacent timings work '(near-witness-export near-witness-verify))
                    (measure-query restored 0 0 'after-restore-cycle
                      (vector-ref cycle 0) cycle-adjacent timings work '(cycle-witness-export cycle-witness-verify))
                    (set! graph restored))))))
          (report timings 'TIMING 'milliseconds (/ 1000. frequency))
          (report work 'WORK 'count 1))))))

(def (bound-program rows from to reverse?)
  (let ((start (gerbil-ascent-literal (if reverse? to from)))
        (goal (gerbil-ascent-literal (if reverse? from to)))
        (x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y)))
    (def (edge left right)
      (gerbil-ascent-atom 'edge (if reverse? (list right left) (list left right))))
    (gerbil-ascent-program
      (list (gerbil-ascent-relation 'edge 2 rows)
            (gerbil-ascent-relation 'reach 1 []) (gerbil-ascent-relation 'answer 1 []))
      (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'reach (list y)))
              (list (edge start y)))
            (gerbil-ascent-rule (list (gerbil-ascent-atom 'reach (list y)))
              (list (gerbil-ascent-atom 'reach (list x)) (edge x y)))
            (gerbil-ascent-rule (list (gerbil-ascent-atom 'answer (list goal)))
              (list (gerbil-ascent-atom 'reach (list goal)))))
      edge-count (+ vertex-count 1) (+ edge-count vertex-count 1))))

(def (measure-session runtime open close rows removed target reverse? samples)
  (let ((timings (make-hash-table-eq)) (path #f))
    (def (probe result)
      (unless (.ref result 'finished) (error "reference Session did not finish"))
      (set! path (.ref result 'evaluation-path))
      (equal? ((.ref result 'rows-of) 'answer) (list (list (if reverse? origin target)))))
    (for (_ (in-range samples))
      (let (session (timed timings 'cold-open (lambda () (open (bound-program rows origin target reverse?)))))
        (try
          (let (ready (timed timings 'cold-evaluate (lambda () (gerbil-ascent-session-run session))))
            (check (timed timings 'cold-first (lambda () (probe ready))) => #t))
          (combine! timings 'cold-ready 'cold-open 'cold-evaluate 'cold-first)
          (timed timings 'delete-stage (lambda () (gerbil-ascent-session-replace-source! session 'edge removed)))
          (let (ready (timed timings 'delete-publish (lambda () (gerbil-ascent-session-run session))))
            (check (timed timings 'after-delete (lambda () (probe ready))) => #f))
          (combine! timings 'delete-to-first 'delete-stage 'delete-publish 'after-delete)
          (timed timings 'restore-stage (lambda () (gerbil-ascent-session-append-source! session 'edge (list origin neighbor))))
          (let (ready (timed timings 'restore-publish (lambda () (gerbil-ascent-session-run session))))
            (check (timed timings 'after-restore (lambda () (probe ready))) => #t))
          (combine! timings 'restore-to-first 'restore-stage 'restore-publish 'after-restore)
          (finally (close session)))))
    (write (list 'SESSION runtime path origin target (if reverse? 'reverse 'forward))) (newline)
    (report timings 'TIMING 'milliseconds (/ 1000. frequency))))

(def bound-reachability-session-test
  (test-suite "Existing native Sessions with an already-bound rule and singleton answer"
    (test-case "Direct Scheme and Actor evaluation on the bridge update"
      (let* ((rows (load-edges)) (removed (cut rows)))
        (for-each
          (lambda (target)
            (for-each
              (lambda (reverse?)
                (measure-session 'direct gerbil-ascent-open-session (lambda (_) (void)) rows removed target reverse? 12)
                (measure-session 'actor gerbil-ascent-open-actor-session gerbil-ascent-session-close!
                  rows removed target reverse? 12))
              '(#f #t)))
          (list neighbor 22686))))))

;; The existing diagnostic collector belongs to a fresh serial solve. Its
;; counters describe that path, never the separately timed retained Sessions.
(def bound-reachability-counter-test
  (test-suite "Physical work of the existing bound rule in a fresh serial solve"
    (test-case "Count edge candidates and index-build input rows on the same cuts"
      (let* ((rows (load-edges)) (removed (cut rows)))
        (def (observe phase target reverse? rows expected)
          (let* ((cost (make-positive-plan-cost #f #t))
                 (result (call-with-positive-plan-cost cost
                           (lambda () (gerbil-ascent-evaluate-program (bound-program rows origin target reverse?)))))
                 (counts (positive-plan-cost-snapshot cost))
                 (edges (foldl
                          (lambda (visit total)
                            (let* ((witness (list-ref visit 5)) (current (car (reverse witness))))
                              ;; Edge is the only binary atom in this program.
                              (if (= (length current) 2) (+ total 1) total)))
                          0 (positive-plan-cost-visits cost))))
            (check (.ref result 'finished) => #t)
            (check (not (null? ((.ref result 'rows-of) 'answer))) => expected)
            (check (positive? (cdr (assq 'index-builds counts))) => #t)
            (write (list 'ENGINE-WORK phase target (if reverse? 'reverse 'forward)
                         'edge-candidates edges
                         (assq 'index-builds counts)
                         (assq 'index-build-input-rows counts)
                         (assq 'index-extend-input-rows counts)))
            (newline)))
        (for-each (lambda (target)
                    (observe 'deleted target #f removed #f)
                    (observe 'restored target #f rows #t)
                    (observe 'restored target #t rows #t))
                  (list neighbor 22686))
        (force-output)))))

(def bound-reachability-edits-test
  (test-suite "Independent deletions across the observed Gnutella topology"
    (test-case "Thirty-two distinct edits and restorations preserve alternate paths and old witnesses"
      (let* ((rows (load-edges)) (graph (prepare rows)) (array (list->vector rows))
             (timings (make-hash-table-eq)) (work (make-hash-table-eq)) (alternate 0))
        (for (sample (in-range 32))
          (let* ((row (vector-ref array (* sample 1723))) (from (car row)) (to (cadr row))
                 (deleted (filter (lambda (candidate) (not (eq? row candidate))) rows)))
            (let-values (((expected _scans adjacent) (oracle deleted from))
                         ((full _full-scans full-adjacent) (oracle rows from)))
              (let* ((before (measure-query graph from to 'unchanged #t full-adjacent timings work
                               '(old-witness-export old-witness-verify)))
                     (edit (timed timings 'mixed-delete
                             (lambda () (call-with-values
                               (lambda () (gerbil-ascent-bound-reachability-edit graph from to #f work-limit: work-limit)) list))))
                     (after (car edit)))
                (record! work 'mixed-delete-buckets (cadr edit))
                (record! work 'mixed-delete-edge-reads (caddr edit))
                (when (measure-query after from to 'mixed-first (vector-ref expected to) adjacent timings work
                        '(mixed-witness-export mixed-witness-verify))
                  (set! alternate (+ alternate 1)))
                (combine! timings 'mixed-delete-to-first 'mixed-delete 'mixed-first)
                (when (gerbil-ascent-bound-reachability-verify after before)
                  (error "edited branch accepted an old witness" sample))
                (let-values (((restored buckets reads)
                              (gerbil-ascent-bound-reachability-edit after from to #t work-limit: work-limit)))
                  (check buckets => 2)
                  (record! work 'mixed-restore-edge-reads reads)
                  (measure-query restored from to 'mixed-restored (vector-ref full to) full-adjacent timings work
                    '(restored-witness-export restored-witness-verify)))))))
        (write (list 'EDIT-SAMPLE 'distinct-deletions 32 'surviving-alternate-paths alternate)) (newline)
        (report timings 'TIMING 'milliseconds (/ 1000. frequency))
        (report work 'WORK 'count 1)))))

(def bound-reachability-shape-test
  (test-suite "Long traversals in two sparse directed components"
    (test-case "A long hit crosses a bridge and its deletion leaves two nonempty frontiers"
      (let* ((split (quotient vertex-count 2)) (target (- vertex-count 100))
             (source (- split 1)) (bridge (list source split))
             (rows (with-list-builder (collect!)
                     (for (v (in-range vertex-count))
                       (let* ((base (if (< v split) 0 split))
                              (width (if (< v split) split (- vertex-count split))))
                         (collect! (list v (+ base (modulo (+ (- v base) 1) width))))
                         (collect! (list v (+ base (modulo (+ (- v base) 2) width))))))))
             (joined (cons bridge rows)) (initial (prepare joined))
             (timings (make-hash-table-eq)) (work (make-hash-table-eq)))
        (let-values (((expected _joined-scans adjacent) (oracle joined 0))
                     ((absent _split-scans split-adjacent) (oracle rows 0)))
          (for (_ (in-range 64))
            (let-values (((separated buckets _reads)
                          (gerbil-ascent-bound-reachability-edit initial source split #f work-limit: work-limit)))
              (unless (= buckets 2) (error "bridge edit did not replace its two endpoint buckets"))
              (measure-query separated 0 target 'shape-miss (vector-ref absent target) split-adjacent timings work
                '(shape-export shape-verify))
              (measure-query initial 0 target 'shape-hit (vector-ref expected target) adjacent timings work
                '(shape-export shape-verify)))))
        (report timings 'TIMING 'milliseconds (/ 1000. frequency))
        (report work 'WORK 'count 1)))))
