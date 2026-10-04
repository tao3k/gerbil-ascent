;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Paired physical index lifecycle, using the pre-change access implementation.
;;; Source rows, lookup keys and batch order are identical; no caller data mutates.
(import :gerbil/runtime/gambit
        (only-in :gerbil/expander core-resolve-library-module-path)
        (only-in :gerbil-ascent/core/positive-plan
                 gerbil-ascent-index-key/terms gerbil-ascent-index-value)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/access
                 gerbil-ascent-physical-index-build gerbil-ascent-physical-index-extend!
                 gerbil-ascent-physical-index-rows gerbil-ascent-physical-index-single-rows)
        (rename-in :gerbil-ascent/t/performance/scalar-index/reference-access
                   (gerbil-ascent-physical-index-build old-build)
                   (gerbil-ascent-physical-index-extend! old-extend!)
                   (gerbil-ascent-physical-index-rows old-rows)))
(export main)

(def provider gerbil-ascent-hash-index-provider)
;;; Both variants and their key producer must resolve to the same compiled
;;; library, never one native implementation versus an interpreted reference.
(def (assert-native-modules! library)
 (for-each
 (lambda (name)
   (let ((expected (path-expand (string-append "gerbil-ascent/" name ".ssi")
                                library))
         (actual (core-resolve-library-module-path
                  (string->symbol (string-append ":gerbil-ascent/" name)))))
     (unless (equal? expected actual) (error "unqualified paired index module" name actual))
     (unless (file-exists? (string-append (path-strip-extension expected) ".o1"))
       (error "paired index module lacks native object" name))))
 '("table/access" "table/funs" "core/positive-plan" "program/index" "program/evaluate"
   "t/performance/scalar-index/reference-access"))
 (displayln "NATIVE-MODULES-OK") (force-output))
(def (median samples) (list-ref (list-sort < samples) (quotient (length samples) 2)))
(def (measure call repetitions)
  (let ((before (##process-statistics)) (start (current-jiffy)))
    (let loop ((left repetitions) (result #f))
      (if (zero? left)
        (let (after (##process-statistics))
          (values result
                  (quotient (inexact->exact (- (f64vector-ref after 7) (f64vector-ref before 7))) repetitions)
                  (quotient (- (current-jiffy) start) repetitions)
                  (/ (- (+ (f64vector-ref after 0) (f64vector-ref after 1))
                        (+ (f64vector-ref before 0) (f64vector-ref before 1))) repetitions)))
        (loop (- left 1) (call))))))

(def (lifecycle build extend! lookup key-value source batch columns terms)
  (let (index (build provider source columns))
    (extend! provider index batch columns)
    (let loop ((remaining terms) (answers []))
      (if (null? remaining) (reverse answers)
        (loop (cdr remaining)
              (cons (lookup provider index (key-value (car remaining))) answers))))))

(def (paired name source batch columns keys)
  (let (terms (map (lambda (key) (map (lambda (value) (cons 'literal value)) key)) keys))
  (def (key-value selected) (gerbil-ascent-index-key/terms selected []))
  (def (old) (lifecycle old-build old-extend! old-rows key-value source batch columns terms))
  (def (new) (lifecycle gerbil-ascent-physical-index-build
                      gerbil-ascent-physical-index-extend!
                      (if (= (length columns) 1)
                        (lambda (_provider index value)
                          (gerbil-ascent-physical-index-single-rows index value))
                        gerbil-ascent-physical-index-rows)
                      (if (= (length columns) 1)
                        (lambda (selected) (gerbil-ascent-index-value (car selected) [] #f))
                        key-value)
                      source batch columns terms))
  ;; Warm both variants after one collection. Natural batch collections are
  ;; measured; forcing a collection per variant distorts the steady workload.
  (##gc)
  (unless (equal? (old) (new)) (error "index lifecycle differs" name))
  (let ((old-bytes []) (new-bytes []) (old-times []) (new-times []) (wins 0)
        (old-cpus []) (new-cpus []) (cpu-wins 0)
        (repetitions (if (< (length source) 32) 1000 5)))
    (let loop ((sample 0))
      (when (< sample 100)
        (let-values (((left lb lt lc right rb rt rc)
                      (if (even? sample)
                        (let-values (((a ab at ac) (measure old repetitions)) ((b bb bt bc) (measure new repetitions)))
                          (values a ab at ac b bb bt bc))
                        (let-values (((b bb bt bc) (measure new repetitions)) ((a ab at ac) (measure old repetitions)))
                          (values a ab at ac b bb bt bc)))))
          (unless (equal? left right) (error "paired index lifecycle differs" name sample))
          (set! old-bytes (cons lb old-bytes)) (set! new-bytes (cons rb new-bytes))
          (set! old-times (cons lt old-times)) (set! new-times (cons rt new-times))
          (set! old-cpus (cons lc old-cpus)) (set! new-cpus (cons rc new-cpus))
          (when (< rc lc) (set! cpu-wins (+ cpu-wins 1)))
          (when (< rt lt) (set! wins (+ wins 1))))
        (when (zero? (modulo (+ sample 1) 10))
          (displayln "PROGRESS " name " " (+ sample 1) "/100") (force-output))
        (loop (+ sample 1))))
    (displayln "RESULT " name " old-bytes=" (median old-bytes)
               " new-bytes=" (median new-bytes)
               " old-us=" (quotient (* (median old-times) 1000000) (jiffies-per-second))
               " new-us=" (quotient (* (median new-times) 1000000) (jiffies-per-second))
               " time-wins=" wins "/100"
               " old-cpu-us=" (* 1000000 (median old-cpus))
               " new-cpu-us=" (* 1000000 (median new-cpus))
               " cpu-wins=" cpu-wins "/100")
    (unless (if (= (length columns) 1)
              (< (median new-bytes) (* 0.9 (median old-bytes)))
              (= (median new-bytes) (median old-bytes)))
      (error "paired index allocation gate failed" name))
    ;; Whole batches reduce timer/scheduling noise. Tiny indices are an
    ;; allocation control; the evaluator does not build them below 32 rows.
    (unless (or (< (length source) 32)
                (if (= (length columns) 1)
                  (and (<= (median new-times) (* 0.9 (median old-times)))
                       (<= (median new-cpus) (* 0.9 (median old-cpus))) (>= cpu-wins 75))
                  (and (<= (median new-times) (* 1.05 (median old-times)))
                       (<= (median new-cpus) (* 1.05 (median old-cpus))))))
      (error "paired index CPU/median time gate failed" name wins cpu-wins))
    (force-output))))

(def source (map (lambda (n) (list n (modulo n 17) n)) (iota 4096)))
(def batch (map (lambda (n) (list n (modulo n 17) n)) (iota 1024 4096)))
(def (main case-name library)
  (assert-native-modules! library)
  (let (scenario (string->symbol case-name))
    (unless (memq scenario '(all single-first single-later composite-control tiny-control))
      (error "unknown scalar-index scenario" scenario))
    (when (memq scenario '(all single-first))
      (paired 'single-first source batch '(0) (map list (iota 5120))))
    (when (memq scenario '(all single-later))
      (paired 'single-later source batch '(2) (map list (iota 5120))))
    (when (memq scenario '(all composite-control))
      (paired 'composite-control source batch '(0 2) (map (lambda (n) (list n n)) (iota 5120))))
    (when (memq scenario '(all tiny-control))
      (paired 'tiny-control (take source 8) (take batch 2) '(0) (map list (iota 8))))
    (displayln "OK") (force-output)))
