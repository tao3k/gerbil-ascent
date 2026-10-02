;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Paired, compiled binding and warm-declaration fixed-point evaluation.
;;; Program construction and result checks are outside each timed span.
(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/funs gerbil-ascent-bind-row)
        (only-in :gerbil-ascent/program/objects
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-rule gerbil-ascent-program)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/t/qualification/ascent-binding-reference-fixture
                 ascent-reference-bind-row ascent-binding-atom-plan)
        (only-in :gerbil-ascent/t/qualification/ascent-binding-reference-evaluate
                 ascent-reference-evaluate-program)
        (only-in :gerbil-ascent/t/qualification/ascent-index-program-fixture
                 ascent-index-fixture-program))

(def (statistic samples fraction)
  (list-ref (list-sort < samples)
            (- (quotient (* (length samples) fraction) 100) 1)))

(def (timed call repetitions)
  (let ((start (current-jiffy)) (result #f))
    (let loop ((left repetitions))
      (when (> left 0)
        (set! result (call))
        (loop (- left 1))))
    (values result
            (quotient (* (- (current-jiffy) start) 1000000000)
                      (* repetitions (jiffies-per-second))))))

(def (matched name old new check repetitions require-wins?)
  (displayln "CASE " name " samples=1000 repetitions=" repetitions)
  (force-output)
  (for-each (lambda (_) (check (old) (new))) (iota 20))
  (let ((old-samples []) (new-samples []))
    (let loop ((sample 0))
      (when (< sample 1000)
        (let-values (((old-result old-ns new-result new-ns)
                      (if (even? sample)
                        (let-values (((left left-ns) (timed old repetitions))
                                     ((right right-ns) (timed new repetitions)))
                          (values left left-ns right right-ns))
                        (let-values (((right right-ns) (timed new repetitions))
                                     ((left left-ns) (timed old repetitions)))
                          (values left left-ns right right-ns)))))
          (check old-result new-result)
          (set! old-samples (cons old-ns old-samples))
          (set! new-samples (cons new-ns new-samples)))
        (when (zero? (modulo (+ sample 1) 100))
          (displayln "PROGRESS " name " " (+ sample 1) "/1000")
          (force-output))
        (loop (+ sample 1))))
    (let* ((old-p50 (statistic old-samples 50))
           (new-p50 (statistic new-samples 50))
           (wins (foldl (lambda (pair total)
                          (if (< (cdr pair) (car pair)) (+ total 1) total))
                        0 (map cons old-samples new-samples))))
      (displayln "RESULT " name " old-p50-ns=" old-p50
                 " new-p50-ns=" new-p50 " paired-wins=" wins "/1000")
      (force-output)
      (list (cons 'name name) (cons 'repetitions repetitions)
            (cons 'require-wins? require-wins?)
            (cons 'old-p50-ns old-p50) (cons 'new-p50-ns new-p50)
            (cons 'old-p95-ns (statistic old-samples 95))
            (cons 'new-p95-ns (statistic new-samples 95))
            (cons 'paired-wins wins)
            (cons 'old-samples-ns (reverse old-samples))
            (cons 'new-samples-ns (reverse new-samples))))))

(def (names prefix width)
  (map (lambda (column)
         (string->symbol (string-append prefix (number->string column))))
       (iota width)))

(def (binding-case width)
  (let* ((variables (names "value" width))
         (raw (map (lambda (name) (cons 'variable name)) variables))
         (environment (map cons (names "prior" 16) (iota 16)))
         (prepared (vector-ref (ascent-binding-atom-plan raw (map car environment)) 3))
         (row (iota width))
         (expected (append (reverse (map cons variables row)) environment)))
    (matched
     (string->symbol (string-append "bind-" (number->string width)))
     (lambda () (ascent-reference-bind-row raw row environment))
     (lambda () (gerbil-ascent-bind-row prepared row environment))
     (lambda (old new)
       (unless (and (equal? old expected) (equal? new expected))
         (error "binding benchmark changed bindings" old new expected)))
     ;; The narrow shape is a nonregression control. The wide kernels must
     ;; show at least 900 paired wins, beyond clock-resolution ties.
     128 (>= width 16))))

(def (solver-case program name relation expected repetitions require-wins?)
  (matched
   name
   (lambda () (ascent-reference-evaluate-program program))
   (lambda () (gerbil-ascent-evaluate-program program))
   (lambda (old new)
     (let ((old-rows ((.ref old 'rows-of) relation))
           (new-rows ((.ref new 'rows-of) relation)))
       (unless (and (equal? old-rows new-rows)
                    (equal? (list-sort (lambda (left right) (< (car left) (car right)))
                                      new-rows)
                            expected))
         (error "binding benchmark changed fixed-point rows" name))))
   repetitions require-wins?))

(def (projection-case width)
  (let* ((variables (map gerbil-ascent-variable (names "column" width)))
         (rows (map (lambda (seed)
                      (map (lambda (column) (+ (* seed width) column))
                           (iota width)))
                    (iota 64)))
         (expected (map (lambda (row) (list (car row) (last row))) rows))
         (program
          (gerbil-ascent-program
           (list (gerbil-ascent-relation 'input width rows)
                 (gerbil-ascent-relation 'output 2 []))
           (list (gerbil-ascent-rule
                  (list (gerbil-ascent-atom 'output
                                           (list (car variables) (last variables))))
                  (list (gerbil-ascent-atom 'input variables))))
           128 128 256)))
    (solver-case program
                 (string->symbol (string-append "solve-project-" (number->string width)))
                 'output expected 1 #f)))

(let (receipts
      (list (binding-case 2) (binding-case 16) (binding-case 32)
            (solver-case (ascent-index-fixture-program)
                         'solve-two-hop 'two-hop
                         (map (lambda (node) (list node (+ node 2))) (iota 49)) 1 #f)
            ;; Full evaluations are median nonregression controls, without
            ;; a qualified solver speedup or tail-latency claim.
            (projection-case 16) (projection-case 32)))
  (call-with-output-file (getenv "ASCENT_BINDING_RECEIPT")
    (lambda (port)
      (write (list (cons 'baseline-commit '74f0046)
                   (cons 'sample-count 1000)
                   (cons 'measurement 'binding-and-warm-declaration-solve)
                   (cons 'cases receipts)) port)
      (newline port)))
  (for-each
   (lambda (receipt)
     (unless (and (<= (cdr (assq 'new-p50-ns receipt))
                     (cdr (assq 'old-p50-ns receipt)))
                  (or (not (cdr (assq 'require-wins? receipt)))
                      (>= (cdr (assq 'paired-wins receipt)) 900)))
       (error "binding benchmark failed the matched nonregression gate"
              (cdr (assq 'name receipt)))))
   receipts))
(displayln "OK")
(force-output)
(exit 0)
