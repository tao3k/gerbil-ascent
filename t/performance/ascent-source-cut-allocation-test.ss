;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :gerbil/runtime/gambit call-with-output-string display-exception)
        (only-in :gerbil-ascent/program/source-cut
          gerbil-ascent-make-source-cut gerbil-ascent-source-cut-rows gerbil-ascent-source-cut-update)
        (only-in :gerbil-ascent/t/performance/native-library assert-native-library!))
(export ascent-source-cut-allocation-test)
(def (diagnostic call)
  (with-catch
   (lambda (failure)
     (call-with-output-string (lambda (port) (display-exception failure port))))
   (lambda () (call) "accepted")))
(def ascent-source-cut-allocation-test
  (test-suite "Compiled source transaction allocation"
    (test-case "doubled rejected batches allocate no row spines"
      (unless (getenv "ASCENT_TEST_LIBRARY" #f)
        (error "source transaction allocation requires compiled native qualification"))
      (assert-native-library!)
      (let* ((positions (make-hash-table-eq)) (arities '#(2 1)))
        (hash-put! positions 'edge 1) (hash-put! positions 'other 2)
        (let* ((cut (gerbil-ascent-make-source-cut positions arities
                     '((edge (0 1)) (other (7)))))
               (small (list (cons 'edge (make-list 10000 '(2 3)))))
               (large (list (cons 'edge (make-list 20000 '(2 3)))))
               (counter (make-f64vector 2 0.0)))
          (def (refusal-bytes batch append?)
            (##gc)
            (##get-bytes-allocated! counter 0)
            (let (failure
                  (diagnostic (lambda ()
                    (gerbil-ascent-source-cut-update cut positions arities batch append? 2))))
              (##get-bytes-allocated! counter 1)
              (check-equal? (if (string-contains failure "input fact budget exceeded") #t #f) #t)
              (check-equal? (gerbil-ascent-source-cut-rows cut 0) '((0 1)))
              (check-equal? (gerbil-ascent-source-cut-rows cut 1) '((7)))
              (- (f64vector-ref counter 1) (f64vector-ref counter 0))))
          ;; Warm exception formatting before comparing native allocation.
          (refusal-bytes small #f)
          (for-each
           (lambda (append?)
             (let ((a (refusal-bytes small append?)) (b (refusal-bytes large append?)))
               ;; A doubled rejected row batch must not allocate row spines.
               ;; This fixture allows formatting noise, not per-row copies.
               (displayln "SOURCE-CUT-REFUSAL append=" append? " small-bytes=" a " large-bytes=" b)
               (force-output)
               (check-equal? (< b (+ a 4096)) #t))) '(#f #t))
)))))
