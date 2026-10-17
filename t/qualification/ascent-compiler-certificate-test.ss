;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        :gerbil-ascent/core/positive-plan
        :gerbil-ascent/core/positive-certificate
        :gerbil-ascent/core/execution-policy
        :gerbil-ascent/table/access :gerbil-ascent/table/provider)
(export ascent-compiler-certificate-test)

(def (fixture)
  (let* ((first (vector 0 '((variable . x) (variable . x) (literal . 7)) '(2) [] []))
         (second (vector 0 '((variable . y) (variable . x) (variable . z)) '(1 1) [] []))
         (heads (list (vector 0 '((variable . z) (variable . x)))))
         (body (list (vector 'atom first) (vector 'atom second))))
    (values heads body (gerbil-ascent-compile-positive-plan heads body))))
(def (copy-plan plan)
  (let (copy (vector-copy plan))
    (vector-set! copy 0 (map vector-copy (vector-ref plan 0)))
    (vector-set! copy 1 (map vector-copy (vector-ref plan 1)))
    copy))

(def ascent-compiler-certificate-test
  (test-suite "Actual compiler descriptor and physical bucket admission"
    (test-case "independent certificate accepts actual repeated-variable lowering"
      (let-values (((heads body plan) (fixture)))
        (check-equal? (gerbil-ascent-positive-certificate? heads body plan) #t)))
    (test-case "corrupted slots, index keys, head, width and delta extent are refused"
      (let-values (((heads body plan) (fixture)))
        (for-each
          (lambda (mutate!)
            (let (corrupt (copy-plan plan))
              (mutate! corrupt)
              (check-equal? (gerbil-ascent-positive-certificate? heads body corrupt) #f)))
          (list
            (lambda (p) (vector-set! (car (vector-ref p 1)) 1 '((fresh . 1) (bound . 1) (literal . 7))))
            (lambda (p) (vector-set! (cadr (vector-ref p 1)) 2 '((bound . 1) (bound . 1))))
            (lambda (p) (vector-set! (car (vector-ref p 0)) 1 '((bound . 0) (bound . 2))))
            (lambda (p) (vector-set! p 2 2))
            (lambda (p) (vector-set! p 2 3.0))
            (lambda (p) (vector-set! p 4 1))))))
    (test-case "row-local repeated variables cannot be lookup keys"
      (let* ((atom (vector 0 '((variable . x) (variable . x)) '(1) [] []))
             (head (vector 0 '((variable . x)))))
        (check-equal? (gerbil-ascent-compile-positive-plan (list head) (list (vector 'atom atom))) #f)))
    (test-case "physical build and extension preserve every matching occurrence"
      (let* ((provider gerbil-ascent-hash-index-provider)
             (rows '((a b c) (a b c) (d b e) (a f c)))
             (batch '((g b h) (a b c))))
        (for-each
          (lambda (columns)
            (let* ((key (map (lambda (column) (list-ref (car rows) column)) columns))
                   (matching? (lambda (row)
                     (equal? (map (lambda (column) (list-ref row column)) columns) key)))
                   (index (gerbil-ascent-physical-index-build provider rows columns))
                   (before (gerbil-ascent-physical-index-rows provider index key)))
              (check-equal? before (filter matching? rows))
              (gerbil-ascent-physical-index-extend! provider index batch columns)
              (check-equal? (gerbil-ascent-physical-index-rows provider index key)
                (append (reverse (filter matching? batch)) before))
              (check-equal? before (filter matching? rows)))) '(() (0) (1) (2 0) (1 1)))))
    (test-case "expanded policies evaluate every argument once before branching"
      (let (observed [])
        (def (argument name value) (set! observed (cons name observed)) value)
        (check-equal? (gerbil-ascent-old-lane
                       (argument 'position 0) (argument 'pivot 1)
                       (argument 'present #f) (argument 'set #t)) #f)
        (check-equal? (reverse observed) '(position pivot present set))
        (set! observed [])
        (check-equal? (gerbil-ascent-joined-round 1 1 (argument 'active 0) 0 #f #t) #t)
        (check-equal? observed '(active))))
    (test-case "shared control decisions keep failure distinct from completion"
      (check-equal? (gerbil-ascent-actor-complete #t #t) #f)
      (check-equal? (gerbil-ascent-actor-complete #f #f) #f)
      (check-equal? (gerbil-ascent-round-continue 10 #f) #f)
      (check-equal? (gerbil-ascent-readable-key 3 3 #f #t) #f)
      (check-equal? (gerbil-ascent-old-lane 0 1 #f #t) #f)
      (check-equal? (gerbil-ascent-old-lane 0 1 #t #f) #f))))
