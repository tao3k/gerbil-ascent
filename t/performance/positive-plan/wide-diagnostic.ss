;;; Paired whole-solve positive-rule plan evaluation; both allocation and time.
;;; Allocation is the admission gate. Time gains require 900 strict paired wins.
;;; Gambit process-statistics slot 7 is cumulative allocated bytes.
;;; Slot 16 is the latest GC gauge and cannot measure allocations per solve.
(import :gerbil/runtime/gambit
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-rule gerbil-ascent-program
                 gerbil-ascent-generator)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/t/qualification/ascent-positive-plan-reference-evaluate
                 ascent-positive-plan-reference-evaluate-program))
(def (statistic samples fraction)
  (list-ref (list-sort < samples)
            (- (quotient (* (length samples) fraction) 100) 1)))

(def (allocated) (inexact->exact (f64vector-ref (##process-statistics) 7)))
(def (measured call repetitions)
  (let ((start-bytes (allocated)) (start (current-jiffy)) (result #f))
    (let loop ((left repetitions))
      (when (> left 0) (set! result (call)) (loop (- left 1))))
    (let ((elapsed (quotient (* (- (current-jiffy) start) 1000000000)
                             (* repetitions (jiffies-per-second))))
          (bytes (quotient (- (allocated) start-bytes) repetitions)))
      (values result bytes elapsed))))

(def (matched name old new check repetitions require-wins?)
  (displayln "CASE " name " samples=1000 repetitions=" repetitions)
  (force-output)
  (check (old) (new)) (exit 0)
  (let ((old-samples []) (new-samples []) (old-times []) (new-times []))
    (let loop ((sample 0))
      (when (< sample 1000)
        (let-values (((old-result old-bytes old-ns new-result new-bytes new-ns)
                      (if (even? sample)
                        (let-values (((left left-bytes left-ns) (measured old repetitions))
                                     ((right right-bytes right-ns) (measured new repetitions)))
                          (values left left-bytes left-ns right right-bytes right-ns))
                        (let-values (((right right-bytes right-ns) (measured new repetitions))
                                     ((left left-bytes left-ns) (measured old repetitions)))
                          (values left left-bytes left-ns right right-bytes right-ns)))))
          (check old-result new-result)
          (set! old-samples (cons old-bytes old-samples))
          (set! new-samples (cons new-bytes new-samples))
          (set! old-times (cons old-ns old-times))
          (set! new-times (cons new-ns new-times)))
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
            (cons 'new-samples-bytes (reverse new-samples))
            (cons 'old-p50-ns (statistic old-times 50))
            (cons 'new-p50-ns (statistic new-times 50))
            (cons 'old-p95-ns (statistic old-times 95))
            (cons 'new-p95-ns (statistic new-times 95))
            (cons 'time-paired-wins
                  (foldl (lambda (pair total) (if (< (cdr pair) (car pair)) (+ total 1) total))
                         0 (map cons old-times new-times)))
            (cons 'old-samples-ns (reverse old-times))
            (cons 'new-samples-ns (reverse new-times))))))


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
     (lambda () (ascent-positive-plan-reference-evaluate-program program))
     (lambda () (gerbil-ascent-evaluate-program program))
     (lambda (old new)
       (let ((left ((.ref old 'rows-of) 'reach))
             (right ((.ref new 'rows-of) 'reach)))
         (unless (and (equal? left right) (equal? right expected)
                      (.ref old 'finished) (.ref new 'finished))
           (error "size optimization changed recursive fixed point" width left right))))
     1 (>= width 256))))

(def (join width fanout)
  (let* ((x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y))
         (z (gerbil-ascent-variable 'z))
         (left (map (lambda (n) (list n (+ n 1))) (iota width)))
         (right (apply append (map (lambda (n)
                                   (map (lambda (m) (list n m n)) (iota fanout))) (iota width))))
         (p (gerbil-ascent-program
             (list (gerbil-ascent-relation 'left 2 left)
                   (gerbil-ascent-relation 'right 3 right)
                   (gerbil-ascent-relation 'out 3 []))
             (list (gerbil-ascent-rule
                    (list (gerbil-ascent-atom 'out (list x y z)))
                    (list (gerbil-ascent-atom 'left (list x y))
                          (gerbil-ascent-atom 'right (list x z x)))))
             20000 20000 40000)))
    (matched
     (string->symbol (string-append "indexed-fanout-" (number->string width) "-" (number->string fanout)))
     (lambda () (ascent-positive-plan-reference-evaluate-program p))
     (lambda () (gerbil-ascent-evaluate-program p))
     (lambda (old new)
       (unless (and (equal? ((.ref old 'rows-of) 'out) ((.ref new 'rows-of) 'out))
                    (= (length ((.ref new 'rows-of) 'out)) (* width fanout))
                    (.ref old 'finished) (.ref new 'finished))
         (error "positive join changed ordered results")))
     1 #t)))

(def (wide-join)
  (let* ((variables (map (lambda (n) (gerbil-ascent-variable
                                    (string->symbol (string-append "v" (number->string n))))) (iota 40)))
         (input (map (lambda (n) (map (lambda (column) (+ (* n 40) column)) (iota 40))) (iota 256)))
         (p (gerbil-ascent-program
             (list (gerbil-ascent-relation 'left 40 input)
                   (gerbil-ascent-relation 'right 40 input)
                   (gerbil-ascent-relation 'out 40 []))
             (list (gerbil-ascent-rule
                    (list (gerbil-ascent-atom 'out (reverse variables)))
                    (list (gerbil-ascent-atom 'left variables)
                          (gerbil-ascent-atom 'right variables)))) 1024 1024 2048))
         (expected (map reverse (reverse input))))
    (matched 'indexed-wide-40-256
     (lambda () (ascent-positive-plan-reference-evaluate-program p))
     (lambda () (gerbil-ascent-evaluate-program p))
     (lambda (old new)
       (unless (and (equal? ((.ref old 'rows-of) 'out) expected)
                    (equal? ((.ref new 'rows-of) 'out) expected))
         (error "wide positive plan changed independent ordered golden"
                (list (length ((.ref old 'rows-of) 'out)) (take ((.ref old 'rows-of) 'out) 2))
                (list (length ((.ref new 'rows-of) 'out)) (take ((.ref new 'rows-of) 'out) 2))
                (take expected 2))))
     1 #t)))

(def (source-control)
  (let (p (gerbil-ascent-program (list (gerbil-ascent-relation 'source 1 '((1) (1)))) [] 16 16 16))
    (matched 'source-only
     (lambda () (ascent-positive-plan-reference-evaluate-program p))
     (lambda () (gerbil-ascent-evaluate-program p))
     (lambda (old new)
       (unless (and (equal? ((.ref old 'rows-of) 'source) '((1) (1)))
                    (equal? ((.ref new 'rows-of) 'source) '((1) (1))))
         (error "positive plan changed source-only control")))
     1 #f)))


(wide-join)
