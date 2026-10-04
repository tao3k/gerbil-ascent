;;; Paired whole-solve allocation counters; this does not measure latency.
;;; Gambit process-statistics slot 7 is cumulative allocated bytes.
;;; Slot 16 is the latest GC gauge and cannot measure allocations per solve.
(import :gerbil/runtime/gambit
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-rule gerbil-ascent-program
                 gerbil-ascent-generator)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/t/qualification/ascent-set-source-reference-evaluate
                 ascent-set-source-reference-evaluate-program))
(def (statistic samples fraction)
  (list-ref (list-sort < samples)
            (- (quotient (* (length samples) fraction) 100) 1)))

(def (allocated) (inexact->exact (f64vector-ref (##process-statistics) 7)))
(def (timed call repetitions)
  ;; Read cumulative allocation; automatic GC does not reset this counter.
  (let ((start (allocated)) (result #f))
    (let loop ((left repetitions))
      (when (> left 0)
        (set! result (call))
        (loop (- left 1))))
    (values result (quotient (- (allocated) start) repetitions))))

(def (matched name old new check repetitions require-wins?)
  (displayln "CASE " name " samples=1000 repetitions=" repetitions)
  (force-output)
  (for-each (lambda (_) (check (old) (new))) (iota 20))
  (let ((old-samples []) (new-samples []))
    (let loop ((sample 0))
      (when (< sample 1000)
        (let-values (((old-result old-bytes new-result new-bytes)
                      (if (even? sample)
                        (let-values (((left left-bytes) (timed old repetitions))
                                     ((right right-bytes) (timed new repetitions)))
                          (values left left-bytes right right-bytes))
                        (let-values (((right right-bytes) (timed new repetitions))
                                     ((left left-bytes) (timed old repetitions)))
                          (values left left-bytes right right-bytes)))))
          (check old-result new-result)
          (set! old-samples (cons old-bytes old-samples))
          (set! new-samples (cons new-bytes new-samples)))
        (when (zero? (modulo (+ sample 1) 100))
          (displayln "PROGRESS " name " " (+ sample 1) "/1000")
          (force-output))
        (loop (+ sample 1))))
    (let* ((old-p50 (statistic old-samples 50))
           (new-p50 (statistic new-samples 50))
           (wins (foldl (lambda (pair total)
                          (if (< (cdr pair) (car pair)) (+ total 1) total))
                        0 (map cons old-samples new-samples))))
      (displayln "RESULT " name " old-p50-bytes=" old-p50
                 " new-p50-bytes=" new-p50 " paired-wins=" wins "/1000")
      (force-output)
      (list (cons 'name name) (cons 'repetitions repetitions)
            (cons 'require-wins? require-wins?)
            (cons 'old-p50-bytes old-p50) (cons 'new-p50-bytes new-p50)
            (cons 'old-p95-bytes (statistic old-samples 95))
            (cons 'new-p95-bytes (statistic new-samples 95))
            (cons 'paired-wins wins)
            (cons 'old-samples-bytes (reverse old-samples))
            (cons 'new-samples-bytes (reverse new-samples))))))


(def (chain-program width)
  (let* ((x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y))
         (edges (map (lambda (n) (list n (+ n 1))) (iota width))))
    (gerbil-ascent-program
     (list (gerbil-ascent-relation 'edge 2 edges)
           (gerbil-ascent-relation 'reach 1 '((0))))
     (list (gerbil-ascent-rule
            (list (gerbil-ascent-atom 'reach (list y)))
            (list (gerbil-ascent-atom 'reach (list x))
                  (gerbil-ascent-atom 'edge (list x y)))))
     (+ width 16) (+ width 16) (* (+ width 16) 3))))

(def (solver width)
  (let* ((program (chain-program width))
         (expected (map list (iota (+ width 1)))))
    (matched
     (string->symbol (string-append "recursive-chain-" (number->string width)))
     (lambda () (ascent-set-source-reference-evaluate-program program))
     (lambda () (gerbil-ascent-evaluate-program program))
     (lambda (old new)
       (let ((left ((.ref old 'rows-of) 'reach))
             (right ((.ref new 'rows-of) 'reach)))
         (unless (and (equal? left right) (equal? right expected)
                      (.ref old 'finished) (.ref new 'finished))
           (error "size optimization changed recursive fixed point" width left right))))
     (if (= width 16) 20 1) #f)))

(def (sources width distinct)
  (let* ((input (map (lambda (n) (list (modulo n distinct))) (iota width)))
         (p (gerbil-ascent-program
             (list (gerbil-ascent-relation 'out 1 input)) []
             (+ width 16) (+ width 16) (+ width 16))))
    (matched
     (string->symbol (string-append "sources-" (number->string width)
                                    "-distinct-" (number->string distinct)))
     (lambda () (ascent-set-source-reference-evaluate-program p))
     (lambda () (gerbil-ascent-evaluate-program p))
     (lambda (old new)
       (let ((left ((.ref old 'rows-of) 'out))
             (right ((.ref new 'rows-of) 'out)))
         (unless (and (equal? left input) (equal? right input)
                      (andmap eq? left input) (andmap eq? right input)
                      (.ref old 'finished) (.ref new 'finished))
           (error "Set source initialization changed order, identity or duplicates"))))
     (if (< width 16) 20 1) (>= width 10000))))

(let (receipts (append (map solver '(16 256 1024))
                       (list (sources 0 1) (sources 1 1) (sources 2 1)
                             (sources 10000 10000) (sources 10000 16))))
  (let (path (getenv "ASCENT_SET_SOURCE_ALLOCATION_RECEIPT"))
    (call-with-output-file path
      (lambda (port) (write receipts port) (newline port))))
  (for-each
   (lambda (receipt)
     (unless (and (<= (cdr (assq 'new-p50-bytes receipt))
                      (cdr (assq 'old-p50-bytes receipt)))
                  (or (not (cdr (assq 'require-wins? receipt)))
                      (>= (cdr (assq 'paired-wins receipt)) 900)))
       (error "Set allocation reduction failed matched admission" (car receipt))))
   receipts)
  (displayln "OK"))
