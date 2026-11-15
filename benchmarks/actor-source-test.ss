;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/func gerbil-ascent-program
                 gerbil-ascent-relation gerbil-ascent-variable gerbil-ascent-rule gerbil-ascent-atom)
        (only-in :gerbil-ascent/program/analysis gerbil-ascent-program-schema)
        (only-in :gerbil-ascent/program/planning gerbil-ascent-prepare-program)
        (only-in :gerbil-ascent/program/initialization make-initial-source-state
                 gerbil-ascent-initialize-sources!)
        (only-in :gerbil-ascent/program/source-cut gerbil-ascent-make-source-cut
                 gerbil-ascent-source-cut-update gerbil-ascent-source-cut-initial-lane
                 source-slot-newest-first)
        (only-in :gerbil-ascent/program/index gerbil-ascent-make-row-indexes row-indexes-rows)
        (only-in :gerbil-ascent/core/positive-plan make-positive-plan-cost
                 call-with-positive-plan-cost positive-plan-cost-snapshot))
(export actor-source-test)

(def (report-source-phase phase rows samples fields)
  (let* ((ordered (list-sort < samples))
         (count (length ordered)))
    (display "ACTOR-SOURCE ")
    (write (cons* (cons 'phase phase) (cons 'input-rows rows) (cons 'samples count)
                  (cons 'total-cpu-us (* (foldl + 0. ordered) 1000000.))
                  (cons 'p50-cpu-us (* (list-ref ordered (- (quotient (+ count 1) 2) 1)) 1000000.))
                  (cons 'p95-cpu-us (* (list-ref ordered (- (quotient (+ (* count 95) 99) 100) 1)) 1000000.))
                  fields))
    (newline)))

(def (measure-source-admission rows relations schema analysis sources cut-root)
  (let* ((width (length relations))
         (total (make-vector width []))
         (delta (make-vector width []))
         (sizes (make-vector width 0))
         (fresh (make-vector width 0))
         (seen (make-vector width #f))
         (state (make-initial-source-state total delta sizes fresh
                  (make-vector width #f) seen (make-vector width #f)))
         (started (cpu-time)))
    (let-values (((admitted materialized)
                  (gerbil-ascent-initialize-sources! relations schema state rows rows #f sources analysis)))
      (let ((cpu (- (cpu-time) started))
            (membership (vector-ref seen 0))
            (lane (vector-ref total 0)))
        (check-equal? admitted rows)
        (check-equal? materialized rows)
        (check-equal? (vector-ref sizes 0) rows)
        (check-equal? lane cut-root)
        (check-equal? (eq? lane cut-root) (and sources #t))
        (check-equal? (eq? lane (vector-ref delta 0)) #t)
        (check-equal? (and membership (hash-length membership)) (and (not sources) rows))
        cpu))))

(def (measure-buckets repeats rows total schema key)
  (let* ((literal (cons 'literal key))
         (terms (list literal '(wildcard . #f)))
         (atom (vector 0 terms '(0) terms (list literal)))
         (versions (vector 0 0))
         (sizes (vector rows 0))
         (expected (list (list key (+ key 1)))))
    (def (make-lookup)
      (row-indexes-rows
       (gerbil-ascent-make-row-indexes (vector total []) (vector total [])
         sizes sizes versions versions (vector-ref schema 5))))
    (let-values (((cold warm)
                  (let sample ((remaining repeats) (cold []) (warm []))
                    (if (zero? remaining) (values cold warm)
                      (let* ((lookup (make-lookup))
                             (cold-start (cpu-time))
                             (first (lookup atom [] #f #f))
                             (built (- (cpu-time) cold-start))
                             (warm-start (cpu-time))
                             (second (lookup atom [] #f #f))
                             (probed (- (cpu-time) warm-start)))
                        (check-equal? first expected)
                        (check-equal? second expected)
                        (sample (- remaining 1) (cons built cold) (cons probed warm)))))))
      (let ((cost (make-positive-plan-cost #f #f)) (counted (make-lookup)))
        (call-with-positive-plan-cost cost
          (lambda ()
            (check-equal? (counted atom [] #f #f) expected)
            (check-equal? (counted atom [] #f #f) expected)))
        (let (physical (positive-plan-cost-snapshot cost))
          (check-equal? (cdr (assq 'index-build-input-rows physical)) rows)
          (check-equal? (cdr (assq 'physical-index-probes physical)) 2)))
      (report-source-phase 'cold-keyed-read rows cold
        (list (cons 'historical-bucket-inputs key) (cons 'new-bucket-inputs (- rows key))))
      (report-source-phase 'warm-keyed-read rows warm '((probes . 1))))))

(def actor-source-test
  (test-suite "Single VM Actor source admission and physical index"
    (test-case "one append separates source admission from rebuilding its historical buckets"
      (let* ((repeats 1000) (size 16384) (count (+ size 1))
             (edges (map (lambda (id) (list id (+ id 1))) (iota size)))
             (tail (list size (+ size 1)))
             (x (gerbil-ascent-variable 'x))
             (y (gerbil-ascent-variable 'y))
             (relations (list (gerbil-ascent-relation 'edge 2 (append edges (list tail)))
                              (gerbil-ascent-relation 'answer 2 [])))
             (rules (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'answer (list x y)))
                                             (list (gerbil-ascent-atom 'edge (list x y))))))
             (program (gerbil-ascent-program relations rules (+ size 1) 50000 50000))
             (schema (gerbil-ascent-program-schema program relations))
             (analysis (gerbil-ascent-prepare-program relations rules schema #f))
             (positions (vector-ref schema 4))
             (arities (vector-ref schema 2))
             (base (gerbil-ascent-make-source-cut positions arities
                     (list (cons 'edge edges) '(answer))))
             (appended (gerbil-ascent-source-cut-update base positions arities
                         (list (list 'edge tail)) #t (+ size 1)))
             (root (source-slot-newest-first (gerbil-ascent-source-cut-initial-lane appended 0))))
        (check-equal? (eq? (cdr root)
                           (source-slot-newest-first (gerbil-ascent-source-cut-initial-lane base 0))) #t)
        (let ((reference [])
              (owned []))
          (for-each
           (lambda (ordinal)
             (def (sample sources)
               (measure-source-admission count relations schema analysis sources root))
             (if (even? ordinal)
               (begin (set! reference (cons (sample #f) reference))
                      (set! owned (cons (sample appended) owned)))
               (begin (set! owned (cons (sample appended) owned))
                      (set! reference (cons (sample #f) reference)))))
           (iota repeats))
          (report-source-phase 'reference-admission count reference
            (list (cons 'source-spine-pairs count) (cons 'source-membership-writes count)))
          (report-source-phase 'owned-admission count owned
            '((source-spine-pairs . 0) (source-membership-writes . 0))))
        (measure-buckets repeats count root schema size)))))
