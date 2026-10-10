;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Measure complete checked construction boundaries, excluding module startup.
(import :gerbil/runtime/gambit
        (only-in :gerbil/expander core-resolve-library-module-path)
        (only-in :clan/poo/object .ref)
        (only-in :clan/poo/mop element?)
        (only-in :core/types poo-flow-predicate-contract)
        (only-in :gerbil-ascent/program/types GerbilAscentRelationContract)
        (only-in :gerbil-ascent/table/provider
                 GerbilAscentIndexProviderContract gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage
                 GerbilAscentStorageProviderContract gerbil-ascent-set-storage-provider)
        (only-in :gerbil-ascent/program/scheme-checked
                 relational-finite-rows relational-finite-view relational-source)
        (rename-in :gerbil-ascent/t/performance/finite-mapping/reference
                   (relational-finite-rows old-rows)
                   (relational-finite-view old-view)
                   (relational-source old-source)
                   (relational-source/shared-core shared-old-source)))
(export main)
(def (median xs) (list-ref (list-sort < xs) (quotient (length xs) 2)))
(def (assert-native! library)
  (for-each
   (lambda (name)
     (let (expected (path-expand (string-append "gerbil-ascent/" name ".ssi") library))
       (unless (and (equal? expected (core-resolve-library-module-path
                                     (string->symbol (string-append ":gerbil-ascent/" name))))
                    (file-exists? (string-append (path-strip-extension expected) ".o1")))
         (error "finite mapping benchmark requires both native implementations" name))))
   '("program/types" "program/scheme-checked" "program/objects"
     "t/performance/finite-mapping/reference-types" "t/performance/finite-mapping/reference-objects"
     "t/performance/finite-mapping/reference"))
  (displayln "NATIVE-MODULES-OK") (force-output))
(def (measure call)
  (let ((before (##process-statistics)) (started (current-jiffy)))
    (let loop ((left 10) (result #f))
      (if (zero? left)
        (let (after (##process-statistics))
          (values result
            (/ (- (f64vector-ref after 7) (f64vector-ref before 7)) 10)
            (/ (- (+ (f64vector-ref after 0) (f64vector-ref after 1))
                  (+ (f64vector-ref before 0) (f64vector-ref before 1))) 10)
            (/ (- (current-jiffy) started) 10)))
        (loop (- left 1) (call))))))
(def (paired name old new rows-of optimized?)
  (##gc)
  (unless (equal? (rows-of (old)) (rows-of (new))) (error "finite mapping warm parity" name))
  (let ((ab []) (bb []) (ac []) (bc []) (at []) (bt []) (wins 0))
    (let loop ((sample 0))
      (when (< sample 100)
        (let-values (((a bytes-a cpu-a time-a b bytes-b cpu-b time-b)
                      (if (even? sample)
                        (let-values (((a x y z) (measure old)) ((b u v w) (measure new)))
                          (values a x y z b u v w))
                        (let-values (((b u v w) (measure new)) ((a x y z) (measure old)))
                          (values a x y z b u v w)))))
          (unless (equal? (rows-of a) (rows-of b)) (error "finite mapping paired parity" name sample))
          (set! ab (cons bytes-a ab)) (set! bb (cons bytes-b bb))
          (set! ac (cons cpu-a ac)) (set! bc (cons cpu-b bc))
          (set! at (cons time-a at)) (set! bt (cons time-b bt))
          (when (< cpu-b cpu-a) (set! wins (+ wins 1))))
        (when (zero? (modulo (+ sample 1) 10))
          (displayln "PROGRESS " name " " (+ sample 1) "/100") (force-output))
        (loop (+ sample 1))))
    (displayln "RESULT " name " old-bytes=" (median ab) " new-bytes=" (median bb)
               " old-cpu-us=" (* 1000000 (median ac)) " new-cpu-us=" (* 1000000 (median bc))
               " cpu-wins=" wins "/100"
               " old-wall-us=" (/ (* 1000000 (median at)) (jiffies-per-second))
               " new-wall-us=" (/ (* 1000000 (median bt)) (jiffies-per-second)))
    ;; CPU and allocation qualify this construction boundary. Wall time is
    ;; diagnostic on a shared host; no per-call latency claim is admitted.
    (unless (if optimized?
              (and (<= (median bb) (* 0.8 (median ab)))
                   (<= (median bc) (* 0.9 (median ac))) (>= wins 75))
              (and (= (median bb) (median ab)) (<= (median bc) (* 1.05 (median ac)))))
      (error "finite mapping allocation/CPU gate failed" name wins))
    (displayln "OK") (force-output)))
(def (main case-name library)
  (assert-native! library)
  (let* ((scenario (string->symbol case-name))
         (width (if (eq? scenario 'narrow-rows) 1 8))
         (entries (map (lambda (n) (list (make-list width n) (make-list width #f))) (iota 128))))
    (case scenario
      ((canonical-provider)
       ;; Freeze the two original slot predicates. Both variants invoke the
       ;; same public element? protocol, including its outer predicate contract.
       (let* ((responsibilities (.ref GerbilAscentRelationContract 'responsibilities))
              (new-index (.ref responsibilities 'index-provider))
              (new-storage (.ref responsibilities 'storage-provider))
              (old-index (poo-flow-predicate-contract 'ascent/index-provider
                           (lambda (value) (element? GerbilAscentIndexProviderContract value))
                           (lambda (_value _context) [])))
              (old-storage (poo-flow-predicate-contract 'ascent/storage-provider
                             (lambda (value) (element? GerbilAscentStorageProviderContract value))
                             (lambda (_value _context) []))))
         (def (checks index storage)
           (list (element? index gerbil-ascent-hash-index-provider)
                 (element? storage gerbil-ascent-set-storage-provider)))
         (paired scenario (lambda () (checks old-index old-storage))
                          (lambda () (checks new-index new-storage)) values #t)))
      ((narrow-rows wide-rows)
       (paired scenario (lambda () (old-rows width width entries))
                        (lambda () (relational-finite-rows width width entries)) values #t))
      ((wide-view)
       (paired scenario (lambda () (old-view 'view width width entries))
                        (lambda () (relational-finite-view 'view width width entries))
                        (lambda (fragment) (.ref (car (.ref fragment 'relations)) 'rows)) #t))
      ((source-control)
       (let (rows (old-rows width width entries))
         (paired scenario (lambda () (shared-old-source 'source (* 2 width) rows))
                          (lambda () (relational-source 'source (* 2 width) rows))
                          (lambda (relation) (.ref relation 'rows)) #f)))
      (else (error "unknown finite mapping scenario" scenario)))))
