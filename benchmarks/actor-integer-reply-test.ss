;;; -*- Gerbil -*-
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/list/list append-map)
        (only-in :clan/poo/object .o .ref)
        (only-in :gerbil-ascent/interface/engine-api ascent-engine-relation-answer)
        (only-in :gerbil-ascent/program/func gerbil-ascent-program gerbil-ascent-relation
                 gerbil-ascent-variable gerbil-ascent-rule gerbil-ascent-atom)
        (only-in :gerbil-ascent/program/session gerbil-ascent-session-run
                 gerbil-ascent-session-replace-source!)
        (only-in :gerbil-ascent/program/actor-session gerbil-ascent-open-actor-session
                 gerbil-ascent-session-close!))
(export actor-million-integer-list-test actor-million-integer-view-test)

(def row-count 1000000)
(def request-count 128)
(def clock (make-u64vector 1 0))
(def frequency (begin (##get-monotonic-time-frequency! clock 0) (u64vector-ref clock 0)))

(def (tick)
  (##get-monotonic-time! clock 0)
  (u64vector-ref clock 0))

(def (make-input offset)
  (append-map
    (lambda (group)
      (let (left (+ offset (* group 2))) (list (list left (+ left 1)))))
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

(def (report name samples)
  (let* ((ordered (list-sort < (vector->list samples)))
         (index (- (quotient (+ (* request-count 95) 99) 100) 1))
         (scale (/ 1000. frequency)))
    (write (list 'TIMING name 'p95-ms (* scale (list-ref ordered index))
                 'max-ms (* scale (list-ref ordered (- request-count 1)))))
    (newline)))

(def (measure use-view?)
  (check (##current-vm-processor-count) => 1)
  (let* ((span (* 2 row-count)) (original (make-input 0)) (alternate (make-input span))
         (session (open-session original))
         (requests (make-vector request-count 0))
         (packs (make-vector request-count 0))
         (deliveries (make-vector request-count 0)))
    (try
      (let ((begin (tick)) (before (##process-statistics)))
        (do ((i 0 (+ i 1))) ((= i request-count))
          (let* ((start (tick)) (second? (even? i)) (offset (if second? span 0)))
            (gerbil-ascent-session-replace-source! session 'edge (if second? alternate original))
            (let* ((result (gerbil-ascent-session-run session))
                   (delivery (if use-view?
                               (.o (:: @ result)
                                 (rows-of (lambda (_) (error "ordered reply materialized rows"))))
                               (.o (:: @ result)
                                 (with-ordered-binary-fields (lambda (_name _receive) #f))))))
              (unless (.ref result 'finished) (error "integer reply result did not finish"))
              (let* ((pack-start (tick))
                     (packet (ascent-engine-relation-answer delivery 'reach #t values))
                     (decode-start (tick)))
                (unless (= row-count (verify-integer-delivery packet offset)) (error "short integer reply"))
                (let (done (tick))
                  (vector-set! packs i (- decode-start pack-start))
                  (vector-set! deliveries i (- done decode-start))
                  (vector-set! requests i (- done start))))))
          (when (zero? (modulo (+ i 1) 64))
            (write (list 'VERIFIED (+ i 1))) (newline) (force-output)))
        (let* ((wall (/ (- (tick) begin) frequency)) (after (##process-statistics)))
          (write (list 'DELIVERY (if use-view? 'view 'list)
                       'requests request-count 'rows (* request-count row-count)
                       'rows-per-second (/ (* 1.0 request-count row-count) wall)
                       'collections (- (f64vector-ref after 6) (f64vector-ref before 6))))
          (newline)
          (report 'request requests)
          (report 'pack packs)
          (report 'decode-and-deliver deliveries)))
      (finally (gerbil-ascent-session-close! session)))))

(def actor-million-integer-list-test
  (test-suite "Integer replies through list staging"
    (test-case "decode and deliver all rows from the list-based writer" (measure #f))))

(def actor-million-integer-view-test
  (test-suite "Integer replies from ordered views"
    (test-case "decode and deliver all rows without invoking the list exporter" (measure #t))))
