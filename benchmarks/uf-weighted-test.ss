;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Select one original scenario with native gerbil test -r '^uf-weighted-heavy-test$'.
(import :std/test
        (only-in :std/os/pid getpid)
        (only-in :gerbil-ascent/t/performance/paired-study run-paired-scenario)
        :gerbil-ascent/t/performance/uf-weighted/fixture)
(export
  uf-weighted-heavy-test
  uf-weighted-grouped-test
  uf-weighted-left-query-test
  uf-weighted-right-query-test
  uf-weighted-dense-test
  uf-weighted-sparse-test
  uf-weighted-small-test
  uf-weighted-heavy-scale-test
  uf-weighted-large-scale-test
  uf-weighted-ordered-detachment-test)

;; The fixture and measured operations are unchanged. Output naming is outside
;; the measurement; each native test process owns its receipt.
(def (weighted-scenario scenario
                        (contract-path "t/performance/uf-weighted/benchmark.ss")
                        (expected ui-expected))
  (let ((contract (call-with-input-file contract-path read))
        (receipt (getenv "ASCENT_BENCHMARK_RECEIPT"
                   (path-expand
                     (string-append "ascent-uf-weighted-" scenario "-"
                                    (number->string (getpid)) ".sexp")
                     (getenv "TMPDIR" "/tmp")))))
    (run-paired-scenario contract ui-prepare ui-consume expected scenario receipt)))

;; The first injection prepends both endpoints as one ordered block. Later
;; singleton births and the final count-only merge yield 1, 0, 2, ..., n-1.
;; Enumerate that square without reading either UF's captured member axes.
;; Marking each visible pair makes any repeated pair observable on a later
;; read, without retaining a quadratic identity table beside the output.
(def (cycle-axis-member position)
  (if (< position 2) (- 1 position) position))

(def (check-ordered-cycle rows width marker)
  (let next ((pending rows) (left 0) (right 0))
    (cond
     ((= left width)
      (unless (null? pending) (error "extra rows in dense cycle export" width)))
     (else
      (unless (and (pair? pending) (pair? (car pending))
                   (pair? (cdar pending)) (null? (cddar pending))
                   (eqv? (caar pending) (cycle-axis-member left))
                   (eqv? (cadar pending) (cycle-axis-member right)))
        (error "dense cycle export order or pair ownership differs" width left right))
      (let ((row (car pending)) (rest (cdr pending)))
        (when marker
          (set-car! (cdr row) marker)
          (set-car! row marker)
          (set-car! pending marker))
        (if (= (+ right 1) width)
          (next rest (+ left 1) 0)
          (next rest left (+ right 1))))))))

(def (check-cycle-detachment scenario width old?)
  (let* ((view (capture-view (ui-prepare old? scenario) old? #f))
         (mutable (capture-rows view old?))
         (held (capture-rows view old?)))
    (##gc)
    (check-ordered-cycle mutable width (gensym 'consumed-pair))
    (check-ordered-cycle held width #f)
    (check-ordered-cycle (capture-rows view old?) width #f)))

(def uf-weighted-ordered-detachment-test
  (test-suite "Dense cycle export order and pair detachment"
    (test-case "ordered values with a shared terminal pair are rejected"
      (let* ((shared (list 1))
             (rows (list (cons 1 shared) (list 1 0) (cons 0 shared) (list 0 0))))
        (check-ordered-cycle rows 2 #f)
        (check-exception (check-ordered-cycle rows 2 (gensym 'consumed-pair)) true)))
    (test-case "384 vertices in both implementations"
      (check-cycle-detachment 'heavy 384 #t)
      (check-cycle-detachment 'heavy 384 #f))
    (test-case "512 vertices in both implementations"
      (check-cycle-detachment 'large 512 #t)
      (check-cycle-detachment 'large 512 #f))))

(def uf-weighted-heavy-test
  (test-suite "uf-weighted/heavy"
    (test-case "original complete capture and export contract"
      (weighted-scenario "heavy"))))

(def uf-weighted-grouped-test
  (test-suite "uf-weighted/grouped"
    (test-case "original complete capture and export contract"
      (weighted-scenario "grouped"))))

(def uf-weighted-left-query-test
  (test-suite "uf-weighted/left-query"
    (test-case "original complete capture and export contract"
      (weighted-scenario "left-query"))))

(def uf-weighted-right-query-test
  (test-suite "uf-weighted/right-query"
    (test-case "original complete capture and export contract"
      (weighted-scenario "right-query"))))

(def uf-weighted-dense-test
  (test-suite "uf-weighted/dense"
    (test-case "original complete capture and export contract"
      (weighted-scenario "dense"))))

(def uf-weighted-sparse-test
  (test-suite "uf-weighted/sparse"
    (test-case "original complete capture and export contract"
      (weighted-scenario "sparse"))))

(def uf-weighted-small-test
  (test-suite "uf-weighted/small"
    (test-case "original complete capture and export contract"
      (weighted-scenario "small"))))

(def uf-weighted-heavy-scale-test
  (test-suite "uf-weighted/scale/heavy"
    (test-case "one hundred paired complete batches below strict P95"
      (weighted-scenario "heavy" "t/performance/uf-weighted/scale.ss" ui-scale-expected))))

(def uf-weighted-large-scale-test
  (test-suite "uf-weighted/scale/large"
    (test-case "one hundred paired complete batches below strict P95"
      (weighted-scenario "large" "t/performance/uf-weighted/scale.ss" ui-scale-expected))))
