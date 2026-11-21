;;; -*- Gerbil -*-
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/list/list append-map)
        (only-in :clan/poo/object .o .ref)
        (only-in :gerbil-ascent/interface/engine-api ascent-engine-relation-answer
                 ascent-engine-session-copy-integer-relation!)
        (only-in :gerbil-ascent/program/func gerbil-ascent-program gerbil-ascent-relation
                 gerbil-ascent-variable gerbil-ascent-rule gerbil-ascent-atom)
        (only-in :gerbil-ascent/program/session gerbil-ascent-session-run
                 gerbil-ascent-session-replace-source!)
        (only-in :gerbil-ascent/program/actor-session gerbil-ascent-open-actor-session
                 gerbil-ascent-session-close!))
(export actor-million-integer-list-test actor-million-integer-view-test
        actor-million-integer-buffer-test actor-million-integer-packed-buffer-test)

(def row-count 1000000)
(def request-count 128)
(def clock (make-u64vector 1 0))
(def frequency (begin (##get-monotonic-time-frequency! clock 0) (u64vector-ref clock 0)))

(def (tick)
  (##get-monotonic-time! clock 0)
  (u64vector-ref clock 0))

(def (make-input offset packed?)
  (append-map
    (lambda (group)
      (let (left (+ offset (* group 2)))
        (list (list left (if packed? (+ left (modulo group 7)) (+ left 1))))))
    (iota row-count)))

(def (open-session rows)
  (let ((x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y)))
    (gerbil-ascent-open-actor-session
     (gerbil-ascent-program
      (list (gerbil-ascent-relation 'edge 2 rows) (gerbil-ascent-relation 'reach 2 []))
      (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'reach (list x y)))
              (list (gerbil-ascent-atom 'edge (list x y)))))
      row-count row-count (* 2 row-count))
     workers: 1)))

;; Check the wire header, decode both fields, and consume every row in order.
;; This client stays in Scheme and needs no additional list after decode.
(def (verify-integer-delivery packet offset)
  (let (size (+ 2 (* 2 row-count)))
    (unless (and (s64vector? packet) (= (s64vector-length packet) size)
                 (= (s64vector-ref packet 0) row-count) (= (s64vector-ref packet 1) 2))
      (error "invalid binary reply packet"))
    (let deliver ((i 2) (expected offset))
      (if (fx= i size) (fxquotient (fx- expected offset) 2)
        (let ((left (s64vector-ref packet i)) (right (s64vector-ref packet (fx+ i 1))))
          (unless (and (fx= left expected) (fx= right (fx+ expected 1)))
            (error "integer reply delivered incorrect order or fields" i left right))
          (deliver (fx+ i 2) (fx+ expected 2)))))))

;; Independent fixture for the bulk consumer. Build it before starting the
;; clock, and compare every delivered cell in the measured request.
(def (expected-payload offset packed?)
  (let (cells (make-s64vector (* 2 row-count)))
    (do ((row 0 (+ row 1))) ((= row row-count) cells)
      (let ((index (* row 2)) (left (+ offset (* row 2))))
        (s64vector-set! cells index left)
        (s64vector-set! cells (+ index 1) (+ left (if packed? (modulo row 7) 1)))))))

(def (report name samples)
  (let* ((ordered (list-sort < (vector->list samples)))
         (index (- (quotient (+ (* request-count 95) 99) 100) 1))
         (scale (/ 1000. frequency)))
    (write (list 'TIMING name 'p95-ms (* scale (list-ref ordered index))
                 'max-ms (* scale (list-ref ordered (- request-count 1)))))
    (newline)))

(def (measure mode)
  (check (##current-vm-processor-count) => 1)
  (let* ((packed? (eq? mode 'packed-buffer))
         (buffer? (or packed? (eq? mode 'buffer)))
         (span (* 2 row-count)) (original (make-input 0 packed?)) (alternate (make-input span packed?))
         (destination (and buffer? (make-s64vector span)))
         (expected-original (and buffer? (expected-payload 0 packed?)))
         (expected-alternate (and buffer? (expected-payload span packed?)))
         (session (open-session original))
         (requests (make-vector request-count 0))
         (packs (make-vector request-count 0))
         (deliveries (make-vector request-count 0))
         (allocation-samples 0) (allocation-total 0))
    (try
      (let ((begin (tick)) (before (##process-statistics)))
        (do ((i 0 (+ i 1))) ((= i request-count))
          (let* ((start-stats (##process-statistics))
                 (start (tick)) (second? (even? i)) (offset (if second? span 0)))
            (gerbil-ascent-session-replace-source! session 'edge (if second? alternate original))
            (let* ((result (gerbil-ascent-session-run session))
                   (delivery (case mode
                               ((view)
                                (.o (:: @ result)
                                    (rows-of (lambda (_) (error "ordered reply materialized rows")))))
                               ((list)
                                (.o (:: @ result)
                                    (with-ordered-binary-fields (lambda (_name _receive) #f))))
                               (else result))))
              (unless (.ref result 'finished) (error "integer reply result did not finish"))
              (let* ((pack-start (tick))
                     (reply (if buffer?
                              (ascent-engine-session-copy-integer-relation! session 'reach destination)
                              (ascent-engine-relation-answer delivery 'reach #t values)))
                     (decode-start (tick)))
                (if buffer?
                  (unless (and (eqv? reply row-count)
                               (equal? destination (if second? expected-alternate expected-original)))
                    (error "incorrect bulk integer delivery"))
                  (unless (= row-count (verify-integer-delivery reply offset))
                    (error "short integer reply")))
                (let* ((done (tick)) (done-stats (##process-statistics))
                       (bytes (- (f64vector-ref done-stats 7) (f64vector-ref start-stats 7))))
                  (vector-set! packs i (- decode-start pack-start))
                  (vector-set! deliveries i (- done decode-start))
                  (vector-set! requests i (- done start))
                  (when (and (>= bytes 0)
                             (= (f64vector-ref start-stats 6) (f64vector-ref done-stats 6)))
                    (set! allocation-samples (+ allocation-samples 1))
                    (set! allocation-total (+ allocation-total bytes)))))))
          (when (zero? (modulo (+ i 1) 64))
            (write (list 'VERIFIED (+ i 1))) (newline) (force-output)))
        (let* ((wall (/ (- (tick) begin) frequency)) (after (##process-statistics))
               (collections (- (f64vector-ref after 6) (f64vector-ref before 6)))
               (allocation (- (f64vector-ref after 7) (f64vector-ref before 7))))
          (write (list 'DELIVERY mode
                       'requests request-count 'rows (* request-count row-count)
                       'rows-per-second (/ (* 1.0 request-count row-count) wall)
                       'collections collections
                       'raw-allocation-counter-delta allocation
                       'allocation-bytes (and (zero? collections) (>= allocation 0) allocation)
                       'no-gc-allocation-samples allocation-samples
                       'no-gc-mean-allocation-bytes
                       (and (> allocation-samples 0) (/ allocation-total allocation-samples))))
          (newline)
          (report 'request requests)
          (report (if buffer? 'capture-pack-copy 'pack) packs)
          (report (if buffer? 'validate-copied-fields 'decode-and-deliver) deliveries)))
      (finally (gerbil-ascent-session-close! session)))))

(def actor-million-integer-list-test
  (test-suite "Integer replies through list staging"
    (test-case "decode and deliver all rows from the list-based writer" (measure 'list))))

(def actor-million-integer-view-test
  (test-suite "Integer replies from ordered views"
    (test-case "decode and deliver all rows without invoking the list exporter" (measure 'view))))

(def actor-million-integer-buffer-test
  (test-suite "Integer replies from an Actor Session into a caller buffer"
    (test-case "copy and verify every ordered field after each source replacement" (measure 'buffer))))

(def actor-million-integer-packed-buffer-test
  (test-suite "Integer replies from a packed Actor Session into a caller buffer"
    (test-case "copy every non-affine tuple in publication order" (measure 'packed-buffer))))
