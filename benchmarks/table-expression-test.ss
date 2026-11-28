;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/list/list append-map)
        (only-in :asp-gerbil-scheme/benchmark-api benchmark-run/result benchmark-fixture-ref)
        (only-in :clan/poo/object .call)
        (only-in :clan/poo/trie UIntTrieSet)
        (only-in :gerbil-ascent/core/ordered-pair-set gerbil-ascent-ordered-pair-set)
        (only-in :gerbil-ascent/t/scenarios/performance/ascent-table-expression/baseline
                 baseline-indexes baseline-compose baseline-ordered-keys))
(export table-expression-test)

(def (record-cpu! totals phase operation)
  (let* ((started (cpu-time)) (value (operation)))
    (vector-set! totals phase (+ (vector-ref totals phase) (- (cpu-time) started)))
    value))

(def (ring-edges radix offsets)
  (list-sort! <
    (append-map
     (lambda (source)
       (map (lambda (offset) (+ (* source radix) (modulo (+ source offset) radix)))
            offsets))
     (iota radix))))

;; Run the same input and sort-merge as the full scenario. Keep the former
;; carrier construction as a separate arm. The timers exclude truth checks.
(def (profile-sort-merge constructor ordered?)
  (let* ((radix 256)
         (pairs (.call UIntTrieSet .<-list (ring-edges radix '(1 2))))
         (expected (ring-edges radix '(1 2 3 4)))
         (fixture (call-with-input-file
                   "t/scenarios/performance/ascent-table-expression/benchmark.ss" read))
         (totals (make-vector 5 0.))
         (samples 0)
         (before (##process-statistics)))
    (def (attempt)
      (set! samples (+ samples 1))
      (let* ((index (record-cpu! totals 0
                      (lambda () (call-with-values (lambda () (baseline-indexes pairs radix)) vector))))
             (joined (record-cpu! totals 1
                       (lambda () (baseline-compose (vector-ref index 1) (vector-ref index 0) radix))))
             (keys (record-cpu! totals 2
                     (lambda ()
                       ((if ordered? baseline-ordered-keys append) (vector-ref index 2) joined))))
             (root (record-cpu! totals 3 (lambda () (constructor keys)))))
        (record-cpu! totals 4 (lambda () (.call UIntTrieSet .list<- root)))))
    (let-values (((receipt actual) (benchmark-run/result fixture attempt)))
      (let ((after (##process-statistics))
            (join-count
             (let-values (((outgoing incoming direct) (baseline-indexes pairs radix)))
               (check-equal? (length direct) 512)
               (length (baseline-compose incoming outgoing radix)))))
        (check-equal? samples 1000)
        (check-equal? join-count 1024)
        (check-equal? actual expected)
        (display "TABLE-EXPRESSION-PHASES ")
        (write (list (cons 'carrier (if ordered? 'ordered 'generic))
                     (cons 'samples samples)
                     (cons 'join-paths join-count)
                     (cons 'constructor-keys (if ordered? (length actual) (+ 512 join-count)))
                     (cons 'phase-cpu-seconds
                       (map cons '(public-input-and-index sort-merge normalize construct public-projection)
                                 (vector->list totals)))
                     (cons 'wall-seconds (- (f64vector-ref after 2) (f64vector-ref before 2)))
                     (cons 'p95-ns (benchmark-fixture-ref receipt 'p95Ns))
                     (cons 'gc-cpu-seconds
                       (- (+ (f64vector-ref after 3) (f64vector-ref after 4))
                          (+ (f64vector-ref before 3) (f64vector-ref before 4))))
                     (cons 'collections (- (f64vector-ref after 6) (f64vector-ref before 6)))
                     (cons 'last-live-bytes (f64vector-ref after 17))))
        (newline)))))

(def table-expression-test
  (test-suite "Table expression sort-merge carrier phases"
    (test-case "default public construction on the complete witness"
      (profile-sort-merge (lambda (keys) (.call UIntTrieSet .<-list keys)) #f))
    (test-case "ordered Patricia construction on the same witness"
      (profile-sort-merge gerbil-ascent-ordered-pair-set #t))))
