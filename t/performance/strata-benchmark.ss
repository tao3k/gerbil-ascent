;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Matched planning only: prebuilt lowered rules, compiled old and new
;;; algorithms, alternating sample order, equal minimum strata per sample.
;;; Rule construction, POO admission, and fixed-point execution are excluded.
(import (only-in :gerbil-ascent/program/funs gerbil-ascent-rule-strata)
        (only-in :gerbil-ascent/t/qualification/ascent-strata-fixture
                 ascent-reference-rule-strata ascent-strata-rule-plans))

(def (timed solve plans kinds expected repetitions)
  (let ((start (current-jiffy)) (result #f))
    (let loop ((remaining repetitions))
      (when (> remaining 0)
        (set! result (solve plans (vector-length kinds) kinds))
        (loop (- remaining 1))))
    (let (ns (quotient (* (- (current-jiffy) start) 1000000000)
                      (* repetitions (jiffies-per-second))))
      (unless (equal? result expected)
        (error "strata benchmark changed minimum strata" result expected))
      ns)))

(def (statistic samples fraction)
  (list-ref (list-sort < (map (lambda (sample) sample) samples))
            (- (quotient (* (length samples) fraction) 100) 1)))

(def (run count kind)
  (let* ((plans
          (ascent-strata-rule-plans
           (map (lambda (node) (vector (+ node 1) node kind))
                (iota (- count 1)))))
         (kinds (make-vector count 'relation))
         (expected (if (eq? kind 'atom)
                     (make-vector count 0)
                     (list->vector (iota count))))
         ;; Amortize the clock's microsecond resolution for the fast path.
         (repetitions (if (eq? kind 'atom) 32 1))
         (old []) (new []))
    (displayln "CASE " kind " vertices=" count " samples=1000"
               " repetitions=" repetitions)
    (force-output)
    (for-each
     (lambda (_)
       (timed ascent-reference-rule-strata plans kinds expected repetitions)
       (timed gerbil-ascent-rule-strata plans kinds expected repetitions))
     (iota 20))
    (let loop ((sample 0))
      (when (< sample 1000)
        (if (even? sample)
          (begin
            (set! old (cons (timed ascent-reference-rule-strata plans kinds expected repetitions) old))
            (set! new (cons (timed gerbil-ascent-rule-strata plans kinds expected repetitions) new)))
          (begin
            (set! new (cons (timed gerbil-ascent-rule-strata plans kinds expected repetitions) new))
            (set! old (cons (timed ascent-reference-rule-strata plans kinds expected repetitions) old))))
        (when (zero? (modulo (+ sample 1) 100))
          (displayln "PROGRESS " kind " " count " " (+ sample 1) "/1000")
          (force-output))
        (loop (+ sample 1))))
    (let* ((old-p50 (statistic old 50)) (new-p50 (statistic new 50))
           (old-p95 (statistic old 95)) (new-p95 (statistic new 95))
           (wins (foldl (lambda (pair total)
                          (if (< (cdr pair) (car pair)) (+ total 1) total))
                        0 (map cons old new))))
      (displayln "RESULT " kind " vertices=" (vector-length kinds)
                 " old-p50-ns=" old-p50 " new-p50-ns=" new-p50
                 " old-p95-ns=" old-p95 " new-p95-ns=" new-p95
                 " paired-wins=" wins "/1000 semanticEquivalent=#t")
      (force-output)
      (list (cons 'kind kind) (cons 'vertices (vector-length kinds))
            (cons 'repetitions repetitions)
            (cons 'old-p50-ns old-p50) (cons 'new-p50-ns new-p50)
            (cons 'old-p95-ns old-p95) (cons 'new-p95-ns new-p95)
            (cons 'paired-wins wins)
            (cons 'old-samples-ns (reverse old))
            (cons 'new-samples-ns (reverse new))))))

(let (receipts
      (list (run 32 'atom) (run 32 'negation)
            (run 128 'negation) (run 256 'negation)))
  (call-with-output-file (getenv "ASCENT_STRATA_RECEIPT")
    (lambda (port)
      (write (list (cons 'baseline-commit '74f0046)
                   (cons 'timing-source 'current-jiffy)
                   (cons 'sample-count 1000)
                   (cons 'measurement 'strata-planning)
                   (cons 'cases receipts)) port)
      (newline port)))
  (for-each
   (lambda (receipt)
     (unless (and (<= (cdr (assq 'new-p50-ns receipt))
                     (cdr (assq 'old-p50-ns receipt)))
                  (or (eq? (cdr (assq 'kind receipt)) 'atom)
                      (>= (cdr (assq 'paired-wins receipt)) 900)))
       (error "strata planning failed the matched nonregression gate" receipt)))
   receipts))
(displayln "OK")
(force-output)
(exit 0)
