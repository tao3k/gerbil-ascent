(import (only-in :std/list/list append-map)
        (only-in :std/test test-suite check-equal?)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-set-batch-admit!)
        (only-in :gerbil-ascent/t/qualification/ascent-set-batch-reference
                 ascent-set-batch-reference-admit!))
(export ascent-set-batch-test)

(def (logs width)
  (if (= width 0) (list [])
    (append-map (lambda (tail)
                  (map (lambda (n) (cons (list n) tail)) '(0 1 2)))
                (logs (- width 1)))))
(def (gold log count initial)
  (let loop ((remaining (reverse (take log count)))
             (known initial) (accepted []))
    (if (null? remaining) (values accepted known)
      (let (row (car remaining))
        (if (member row known)
          (loop (cdr remaining) known accepted)
          (loop (cdr remaining) (cons row known) (cons row accepted)))))))
(def (run admit log count share? initial)
  (let (seen (make-hash-table))
    (for-each (lambda (row) (hash-put! seen row #t)) initial)
    (let-values (((rows present) (admit log count seen share?)))
      (vector rows present seen))))
(def (verify log count share? initial)
  (let-values (((expected known) (gold log count initial)))
    (for-each
     (lambda (admit)
       (let* ((result (run admit log count share? initial))
              (rows (vector-ref result 0)) (present (vector-ref result 1)))
         (check-equal? rows expected)
         (check-equal? (andmap eq? rows expected) #t)
         (check-equal? (hash-length present) (length known))
         (for-each (lambda (row) (check-equal? (hash-get present row) #t)) known)
         (when (<= count 16)
           (let (keys (hash-keys present))
             (for-each
              (lambda (row)
                (check-equal? (not (not (memq row keys))) #t))
              known)))
         (check-equal? (eq? present (vector-ref result 2))
                       (not (and share? (null? initial))))
         (when (and share? (null? initial) (= count (length log))
                    (= count (length known)))
           (check-equal? (eq? rows log) #t))))
     (list ascent-set-batch-reference-admit! gerbil-ascent-set-batch-admit!))))

(def ascent-set-batch-test
  (test-suite "source-order Set batch admission"
    (poo-flow-test-case "finite logs and staged prefixes preserve independent goldens and row identity"
      (let (comparisons 0)
        (for-each
         (lambda (width)
           (for-each
            (lambda (log)
              (for-each
               (lambda (count)
                 (for-each
                  (lambda (share?)
                    (for-each
                     (lambda (initial)
                       (verify log count share? initial)
                       (set! comparisons (+ comparisons 1)))
                     '(() ((0)) ((0) (1)))))
                  '(#f #t)))
               (iota (+ width 1))))
            (logs width)))
         (iota 5))
        (check-equal? comparisons 3282)))
    (poo-flow-test-case "nullary and heterogeneous rows preserve membership"
      (verify '(() () ()) 3 #t [])
      (verify '((1 "a") (2 #t) (1 "a")) 3 #t [])
      (verify '((1 "a") (2 #t) (1 "a")) 2 #t []))
    (poo-flow-test-case "large duplicate batches preserve first occurrence identity"
      (let (log (reverse (map (lambda (n) (list (modulo n 16))) (iota 10000))))
        (verify log 10000 #t [])
        (verify log 10000 #f '((0)))
        (verify log 9999 #t [])))
    (poo-flow-test-case "unique full logs retain the original spine"
      (verify (reverse (map list (iota 10000))) 10000 #t []))))
