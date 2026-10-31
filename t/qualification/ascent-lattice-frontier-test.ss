;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test (only-in :std/error Error-message Error-irritants)
        :clan/poo/object
        :gerbil-ascent/program/lattice-frontier
        (only-in :gerbil-ascent/program/objects gerbil-ascent-program
                 gerbil-ascent-relation gerbil-ascent-lattice)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine)
        (rename-in (only-in :gerbil-ascent/t/performance/lattice-frontier/reference
                           gerbil-ascent-make-engine)
          (gerbil-ascent-make-engine old-engine))
        :gerbil-ascent/t/performance/lattice-frontier/fixture)
(export ascent-lattice-frontier-test)

(def (outcome call)
  (with-catch (lambda (failure) (list (Error-message failure) (Error-irritants failure))) call))
(def (evaluate-with-trace old? rows (refuse? #f) (limit 16384))
  (let* ((events [])
         (join (lambda (left right)
                 (set! events (cons (list left right) events))
                 (when refuse? (error "fixture join refusal" left right))
                 (min left right)))
         (program (frontier-program 2 rows #t join limit))
         (verdict (outcome (lambda ()
                    (let (engine (if old? (old-engine program #f)
                                   (gerbil-ascent-make-engine program #f)))
                      (frontier-view engine program))))))
    (list verdict (reverse events))))

(def ascent-lattice-frontier-test
  (test-suite "round-owned effective lattice frontier"
    (test-case "all six-event three-key traces preserve last effective update order"
      (for-each
       (lambda (trace)
         (let ((frontier (make-lattice-frontier)) (expected []))
           (let loop ((encoded trace) (step 0))
             (when (< step 6)
               (let* ((key (list (modulo encoded 3))) (row (list (car key) step))
                      (fresh? (not (assoc key expected))))
                 (check-equal? (lattice-frontier-stage! frontier key row) fresh?)
                 (set! expected (cons (cons key row)
                                      (filter (lambda (entry) (not (equal? key (car entry)))) expected)))
                 (check-equal? (lattice-frontier-rows frontier) (map cdr expected))
                 (check-equal? (lattice-frontier-ref frontier (map values key)) row))
               (loop (quotient encoded 3) (+ step 1))))
           (let (held (lattice-frontier-rows frontier))
             (lattice-frontier-clear! frontier)
             (check-equal? (lattice-frontier-rows frontier) [])
             (check-equal? (lattice-frontier-ref frontier '(0)) #f)
             (check-equal? (lattice-frontier-stage! frontier '(0) '(0 99)) #t)
             (check-equal? held (map cdr expected))))
         (when (= (modulo (+ trace 1) 81) 0)
           (displayln "LATTICE-TRACES " (+ trace 1) "/729") (force-output)))
       (iota 729)))
    (test-case "lookup does not reorder equal composite or false keys"
      (let (frontier (make-lattice-frontier))
        (lattice-frontier-stage! frontier '(#f 0) '(#f 0 9))
        (lattice-frontier-stage! frontier '(#t 0) '(#t 0 8))
        (check-equal? (lattice-frontier-ref frontier (list #f 0)) '(#f 0 9))
        (check-equal? (lattice-frontier-rows frontier) '((#t 0 8) (#f 0 9)))
        (check-equal? (lattice-frontier-stage! frontier (list #f 0) '(#f 0 2)) #f)
        (check-equal? (lattice-frontier-rows frontier) '((#f 0 2) (#t 0 8)))))
    (test-case "source admission orders every accepted occurrence and charges duplicate inputs"
      (def (source-view old? rows bound)
        (outcome
         (lambda ()
           (let* ((program (gerbil-ascent-program
                            (list (gerbil-ascent-relation 'input 2 [])
                                  (gerbil-ascent-lattice 'best 2 rows min))
                            [] bound 32 32))
                  (engine (if old? (old-engine program #f)
                            (gerbil-ascent-make-engine program #f))))
             (frontier-view engine program)))))
      (for-each (lambda (rows)
                  (check-equal? (source-view #f rows 32) (source-view #t rows 32))
                  (check-equal? (source-view #f rows 1) (source-view #t rows 1)))
                '(((0 9) (1 5) (0 11)) ((0 9) (1 5) (0 9))
                  ((#f 9) (#t 5) (#f 11)) ()))
      (let (view (source-view #f '((0 9) (1 5) (0 11)) 32))
        ;; Published source rows reverse the private newest-first engine cut.
        (check-equal? (cdr (assq 'best (cadr view))) '((1 5) (0 9)))))
    (test-case "complete retained cold repeated-key and Set consumers match frozen evaluation"
      (for-each
       (lambda (scenario)
         (let ((old (frontier-prepare #t scenario)) (new (frontier-prepare #f scenario)))
           (frontier-verify! old) (frontier-verify! new)
           (check-equal? (frontier-consume new scenario) (frontier-consume old scenario)))
         (displayln "LATTICE-CONSUMER " scenario) (force-output))
       '(sparse repeated source distinct cold small set)))
    (test-case "join callback arguments and repeated effective key observations retain exact order"
      (for-each
       (lambda (rows)
         (check-equal? (evaluate-with-trace #f rows) (evaluate-with-trace #t rows)))
       '(((0 9) (1 8) (0 7) (2 6) (1 5) (0 4))
         ((#f 9) (#t 8) (#f 2) (#t 1)) ((0 2) (0 7) (0 4)) ())))
    (test-case "join failures retain the first callback and original diagnostics"
      (check-equal? (evaluate-with-trace #f '((0 9) (0 7) (0 2)) #t)
                    (evaluate-with-trace #t '((0 9) (0 7) (0 2)) #t)))
    (test-case "pending keys charge the same budget before publication"
      (for-each
       (lambda (rows)
         (check-equal? (evaluate-with-trace #f rows #f 1)
                       (evaluate-with-trace #t rows #f 1)))
       '(((0 9) (0 7) (0 2)) ((0 9) (1 8) (0 2)))))))
