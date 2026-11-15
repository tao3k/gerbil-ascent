;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/scheme-language relational-program)
        (only-in :gerbil-ascent/program/session
                 gerbil-ascent-open-session gerbil-ascent-session-run
                 gerbil-ascent-session-append-source! gerbil-ascent-session-replace-sources!))
(export session-publication-test)

(def (declaration base count)
  (let (seed (list (list count)))
    (relational-program
      (relation archive (id) base)
      (relation seed (id) seed)
      (relation input (id) '((0)))
      (relation output (id))
      (rule (archive ?id) (seed ?id))
      (rule (output ?id) (input ?id))
      (limits (+ count 8) 4 (+ count 10)))))

(def (observe-phase scenario count phase action (operations 1))
  (let* ((allocation (make-f64vector 2 0.))
         (before (##process-statistics))
         (_ (##get-bytes-allocated! allocation 0))
         (wall-start (current-jiffy))
         (cpu-start (cpu-time))
         (result (action))
         (cpu-us (* 1000000. (- (cpu-time) cpu-start)))
         (wall-us (/ (* 1000000 (- (current-jiffy) wall-start)) (jiffies-per-second)))
         (_ (##get-bytes-allocated! allocation 1))
         (after (##process-statistics))
         (bytes (- (f64vector-ref allocation 1) (f64vector-ref allocation 0)))
         (collections (- (f64vector-ref after 6) (f64vector-ref before 6))))
    (display "SESSION-PUBLICATION ")
    (write (list (cons 'scenario scenario) (cons 'rows count) (cons 'phase phase)
                 (cons 'operations operations)
                 (cons 'wall-us wall-us) (cons 'cpu-us cpu-us)
                 (cons 'allocation-counter-delta (and (zero? collections) (>= bytes 0) bytes))
                 (cons 'collections collections)
                 (cons 'last-gc-live-bytes (f64vector-ref after 17))))
    (newline)
    result))

(def (output result name) ((.ref result 'rows-of) name))

(def (benchmark-session count)
  (let* ((base (map list (iota count)))
         (expected-archive (append base (list (list count))))
         (program (declaration base count)))
    (def (observe phase action (operations 1))
      (observe-phase 'independent-replacement count phase action operations))
    (let* ((session (observe 'open (cut gerbil-ascent-open-session program)))
           (run (cut gerbil-ascent-session-run session))
           (first (observe 'first run)))
      (check-equal? (.ref first 'finished) #t)
      (observe 'warm
        (lambda ()
          (let repeat ((remaining 1000))
            (unless (zero? remaining)
              (unless (eq? first (run)) (error "warm Session changed the publication"))
              (repeat (- remaining 1)))))
        1000)
      (observe 'stage-append (cut gerbil-ascent-session-append-source! session 'input '(1)))
      (let* ((appended (observe 'solve-append run))
             (replaced (observe 'replace-independent
                         (cut gerbil-ascent-session-replace-sources! session '((input (2)))))))
        ;; Demand the archive only after replacement. The untouched derived
        ;; archive must be seeded from the completed publication in this cut.
        (check-equal? (.ref replaced 'evaluation-path) 'stratified-dependency-invalidation)
        (check (and (memq 'archive (.ref replaced 'reused-relations)) #t) => #t)
        (check-equal? (observe 'first-export (cut output replaced 'archive)) expected-archive)
        (check-equal? (observe 'warm-export (cut output replaced 'archive)) expected-archive)
        (check-equal? (output replaced 'output) '((2)))
        (check-equal? (output appended 'output) '((0) (1)))
        (check-equal? (output first 'output) '((0)))
        (check-equal? (output first 'archive) expected-archive)))))

(def session-publication-test
  (test-suite "Retained Session source and publication phases"
    (test-case "4096 retained archive rows across an independent source change"
      (benchmark-session 4096))
    (test-case "16384 retained archive rows across an independent source change"
      (benchmark-session 16384))))
