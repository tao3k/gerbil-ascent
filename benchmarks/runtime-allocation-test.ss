;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test)
(export runtime-allocation-test)

;; The control supplies logical payload counts independently of the runtime.
;; Read the dynamic counter and the last collection's charged bytes separately.
(def (observe-control name work logical-bytes action verify)
  (##gc)
  (let* ((before (##process-statistics))
         (result (action))
         (during (##process-statistics)))
    (##gc)
    (let (after (##process-statistics))
      (verify result)
      (display "ALLOCATION-CONTROL ")
      (write (list (cons 'kind name) (cons 'work work) (cons 'logical-payload-bytes logical-bytes)
                   (cons 'natural-collections (- (f64vector-ref during 6) (f64vector-ref before 6)))
                   (cons 'dynamic-before (f64vector-ref before 7))
                   (cons 'dynamic-after (f64vector-ref after 7))
                   (cons 'gc-charge-before (f64vector-ref before 16))
                   (cons 'gc-charge-after (f64vector-ref after 16))
                   (cons 'movable-live-delta (- (f64vector-ref after 18) (f64vector-ref before 18)))
                   (cons 'still-live-delta (- (f64vector-ref after 19) (f64vector-ref before 19)))))
      (newline))))

(def (allocate-pairs count)
  (let next ((index 0) (rows []))
    (if (= index count) rows (next (+ index 1) (cons index rows)))))

(def runtime-allocation-test
  (test-suite "Gambit allocation and retained-heap controls"
    (test-case "retained pairs and an empty control"
      (observe-control 'empty 0 0 (lambda () 0) (lambda (count) (check-equal? count 0)))
      (for-each
       (lambda (count)
         (observe-control 'pairs count #f (cut allocate-pairs count)
           (lambda (rows)
             (check-equal? (length rows) count)
             (check-equal? (car rows) (- count 1)))))
       '(8192 32768)))
    (test-case "the same still allocation can survive or be collected"
      (let* ((size 1048576)
             (template (make-u8vector size 51)))
        (observe-control 'still-retained 1 size (cut ##still-copy template)
          (lambda (copy)
            (check-equal? (u8vector-length copy) size)
            (check-equal? (u8vector-ref copy (- size 1)) 51)
            (check-equal? (eq? copy template) #f)))
        (observe-control 'still-released 1 size
          (lambda ()
            (let (copy (##still-copy template))
              (unless (= (u8vector-length copy) size) (error "still control copied the wrong size"))
              (u8vector-ref copy (- size 1))))
          (lambda (last) (check-equal? last 51)))))))
