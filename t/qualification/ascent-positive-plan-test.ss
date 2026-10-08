;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :std/list/list append-map)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :clan/poo/object .o .ref)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-program gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-literal gerbil-ascent-wildcard gerbil-ascent-atom
                 gerbil-ascent-rule gerbil-ascent-guard)
        (only-in :gerbil-ascent/program/evaluate
                 gerbil-ascent-evaluate-program gerbil-ascent-make-engine)
        (only-in :gerbil-ascent/program/analysis
                 gerbil-ascent-program-analysis gerbil-ascent-program-schema)
        (only-in :gerbil-ascent/core/positive-plan gerbil-ascent-compile-positive-plan
                 gerbil-ascent-run-positive-plan! gerbil-ascent-index-key
                 gerbil-ascent-pure-positive-plan? gerbil-ascent-positive-plan-with-outputs)
        (only-in :gerbil-ascent/table/funs gerbil-ascent-index-build gerbil-ascent-index-extend!)
        (only-in :gerbil-ascent/program/index gerbil-ascent-make-row-indexes row-indexes-rows row-indexes-advance!)
        (only-in :gerbil-ascent/core/rule-bindings gerbil-ascent-bind-row
                 gerbil-ascent-head-row)
        (only-in :gerbil-ascent/program/reuse gerbil-ascent-activate-rules)
        (only-in :gerbil-ascent/program/update-selection gerbil-ascent-update-active-plans)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-set-storage-provider)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/t/qualification/ascent-positive-plan-reference-evaluate
                 ascent-positive-plan-reference-evaluate-program
                 ascent-positive-plan-reference-make-engine))
(export ascent-positive-plan-test)
(def (v name) (gerbil-ascent-variable name))
(def (a name . terms) (gerbil-ascent-atom name terms))
(def (rows result name) ((.ref result 'rows-of) name))
(def (compare program names)
  (let ((old (ascent-positive-plan-reference-evaluate-program program))
        (new (gerbil-ascent-evaluate-program program)))
    (for-each (lambda (name) (check-equal? (rows new name) (rows old name))) names)
    (check-equal? (.ref new 'finished) (.ref old 'finished))
    new))
(def (path-program edges)
  (let ((x (v 'x)) (y (v 'y)) (z (v 'z)))
    (gerbil-ascent-program
     (list (gerbil-ascent-relation 'edge 2 edges)
           (gerbil-ascent-relation 'path 2 []))
     (list (gerbil-ascent-rule (list (a 'path x y)) (list (a 'edge x y)))
           (gerbil-ascent-rule (list (a 'path x z))
                              (list (a 'path x y) (a 'edge y z))))
     32 64 96)))

;; The reference binds association-list environments and emits declared heads;
;; it never inspects compiled actions or the mutable slot frame.
(def (binding-stream terms heads first-rows second-rows)
  (let (emitted [])
    (for-each
     (lambda (first-row)
       (let (initial (gerbil-ascent-bind-row '((variable . a)) first-row []))
         (for-each
          (lambda (second-row)
            (let (bound (gerbil-ascent-bind-row terms second-row initial))
              (when bound
                (for-each
                 (lambda (head)
                   (set! emitted
                     (cons (cons (vector-ref head 0)
                                 (gerbil-ascent-head-row (vector-ref head 1) bound))
                           emitted))) heads))))
          second-rows))) first-rows)
    (reverse emitted)))

(def (slot-stream plan frame first-rows second-rows)
  (let (emitted [])
    (gerbil-ascent-run-positive-plan!
     plan frame -1
     (lambda (atom environment delta? slot-terms)
       (case (vector-ref atom 0)
         ((0) first-rows) ((1) second-rows)
         (else (error "unexpected slot corpus read" atom))))
     (lambda (head row)
       (set! emitted (cons (cons (vector-ref head 0) row) emitted))))
    (reverse emitted)))

;; Arbitrary-depth ordinary binding traversal, independent of compiled slots.
(def (body-binding-stream atoms heads)
  (let (emitted [])
    (def (visit remaining environment)
      (if (null? remaining)
        (for-each
         (lambda (head)
           (set! emitted
             (cons (cons (vector-ref head 0)
                         (gerbil-ascent-head-row (vector-ref head 1) environment))
                   emitted))) heads)
        (let (atom (car remaining))
          (for-each
           (lambda (row)
             (let (bound (gerbil-ascent-bind-row (car atom) row environment))
               (when bound (visit (cdr remaining) bound))))
           (cdr atom)))))
    (visit atoms [])
    (reverse emitted)))

(def (make-slot-indexes all delta provider)
  (let (sizes (lambda (sources) (list->vector (map length (vector->list sources)))))
    (gerbil-ascent-make-row-indexes all delta (sizes all) (sizes delta)
      (make-vector 3 0) (make-vector 3 0) (make-vector 3 provider))))

(def (indexed-slot-stream plan frame pivot all delta provider positions (retained #f))
  (let* ((indexes (or retained (make-slot-indexes all delta provider)))
         (access (row-indexes-rows indexes)) (emitted []) (reads []))
    (gerbil-ascent-run-positive-plan!
     plan frame pivot
     (lambda (atom environment delta? slot-terms)
       (let (position
             (let loop ((rest positions) (n 0))
               (if (eq? atom (car rest)) n (loop (cdr rest) (+ n 1)))))
         (set! reads (cons (list position delta?) reads))
         (access atom environment delta? slot-terms)))
     (lambda (head row) (set! emitted (cons (cons (vector-ref head 0) row) emitted))))
    (for-each (lambda (read) (check-equal? (cadr read) (= (car read) pivot))) reads)
    (reverse emitted)))

;; A full synchronous scan oracle; it does not read slots, pivots or indexes.
(def (scan-path-step edges current)
  (let (next current)
    (def (admit row) (unless (member row next) (set! next (cons row next))))
    (for-each admit edges)
    (for-each
     (lambda (path)
       (for-each (lambda (edge)
                   (when (= (cadr path) (car edge)) (admit (list (car path) (cadr edge))))) edges)) current)
    next))
(def (check-path-set actual expected)
  (check-equal? (length actual) (length expected))
  (for-each (lambda (row) (check-equal? (and (member row expected) #t) #t)) actual))

(def ascent-positive-plan-test
  (test-suite "Complete positive rule slot plans"
    (poo-flow-test-case "heterogeneous equality preserves repeated bindings and dirty-frame reuse"
      ;; Equal separately allocated containers distinguish structural equality
      ;; from identity; false remains a value and never an absent binding.
      (let* ((values (list #f #t 0 -7 1/3 'value (string-copy "value")
                           (vector #f 7) (list 'value #f) (expt 2 90)))
             (copies (list #f #t 0 -7 1/3 'value (string-copy "value")
                           (vector #f 7) (list 'value #f) (expt 2 90)))
             (patterns '((variable . b) (variable . a) (variable . b) (literal . #f)))
             (heads (list (vector 2 '((variable . a) (variable . b) (literal . #f)))
                          (vector 3 '((variable . b) (variable . a)))))
             (first (vector 0 '((variable . a)) [] '((variable . a)) []))
             (second (vector 1 patterns '(1) patterns '((variable . a))))
             (plan (gerbil-ascent-compile-positive-plan heads
                     (list (vector 'atom first) (vector 'atom second))))
             (first-rows (map list values))
             (second-rows
               (append-map (lambda (bound)
                             (map (lambda (fresh copy) (list fresh bound copy #f))
                                  values copies)) copies))
             (bad-rows (map (lambda (row) (list (car row) (cadr row) (caddr row) #t))
                            second-rows))
             (frame (make-vector 4 'stale))
             (expected (binding-stream patterns heads first-rows second-rows)))
        (check-equal? (vector-ref plan 2) 2)
        (check-equal? (length expected) 200)
        (check-equal? (slot-stream plan frame first-rows bad-rows) [])
        (check-equal? (slot-stream plan frame first-rows second-rows) expected)
        (check-equal? (slot-stream plan frame (reverse first-rows) (reverse second-rows))
                      (binding-stream patterns heads (reverse first-rows) (reverse second-rows)))
        (check-equal? (indexed-slot-stream plan frame -1
                        (vector first-rows second-rows []) (vector [] [] [])
                        gerbil-ascent-hash-index-provider (list first second)) expected)
        (for-each (lambda (value)
                    (vector-set! frame 0 value)
                    (check-equal? (gerbil-ascent-index-key patterns '(1) frame
                                    (vector-ref (cadr (vector-ref plan 1)) 2))
                                  (list value))) copies)
        (check-equal? (vector-ref frame 2) 'stale)
        (check-equal? (vector-ref frame 3) 'stale)))
    (poo-flow-test-case "exact parts matching preserves duplicate and projected output heads"
      (let* ((head (vector 2 '((variable . g) (variable . x) (variable . y))))
             (other (vector 3 '((variable . y) (variable . x))))
             (first (vector 0 '((variable . g) (variable . x)) []))
             (second (vector 1 '((variable . g) (variable . x) (variable . y)) '(0 1)))
             (plan (gerbil-ascent-compile-positive-plan
                     (list head other head) (list (vector 'atom first) (vector 'atom second))))
             (partial (gerbil-ascent-positive-plan-with-outputs plan (list (cadr (vector-ref plan 0)))))
             (rows '((#f 1 a) (#f 2 rejected) (#t 2 c))))
        (for-each (lambda (mode)
          (for-each (lambda (projected?)
            (let ((outputs []) (frame (make-vector 3 'stale)))
              (def (selected)
                (filter (lambda (row) (and (equal? (car row) (vector-ref frame 0))
                                           (equal? (cadr row) (vector-ref frame 1)))) rows))
              (gerbil-ascent-run-positive-plan! (if projected? partial plan) frame -1
                (lambda (atom _frame _delta _terms)
                  (if (= (vector-ref atom 0) 0) '((#f 1) (#t 2))
                      (if (eq? mode 'overselected) rows (selected))))
                (lambda (head row) (set! outputs (cons (cons (vector-ref head 0) row) outputs))) #f
                (and (eq? mode 'direct)
                  (lambda (atom _frame _delta _terms consume)
                    (and (= (vector-ref atom 0) 1)
                      (begin
                        (for-each (lambda (row) (consume (list (car row)) (cadr row) (caddr row))) (selected))
                        #t)))))
              (check-equal? (reverse outputs)
                (if projected? '((3 a 1) (3 c 2))
                  '((2 #f 1 a) (3 a 1) (2 #f 1 a) (2 #t 2 c) (3 c 2) (2 #t 2 c)))))) '(#f #t)))
          '(direct selected overselected))))
    (poo-flow-test-case "synchronous parts preserve candidate checkpoints and declined access"
      (let* ((head (vector 2 '((variable . x) (variable . x))))
             (atom (vector 0 '((variable . x) (variable . x)) []))
             (plan (gerbil-ascent-compile-positive-plan (list head) (list (vector 'atom atom))))
             (rows '((#f #f) (1 2) (1 1))))
        (let (accesses 0)
          (check-exception
            (gerbil-ascent-run-positive-plan! plan [] -1
              (lambda args (set! accesses (+ accesses 1)) rows)
              (lambda args (error "unexpected rejected-frame emission")) #f
              (lambda args (set! accesses (+ accesses 1)) #t)) true)
          (check-equal? accesses 0))
        (for-each (lambda (direct?)
          (let ((reads 0) (parts 0) (trace []) (outputs []))
            (gerbil-ascent-run-positive-plan! plan (make-vector 1 'stale) -1
              (lambda args (set! reads (+ reads 1)) rows)
              (lambda (_ row) (set! outputs (cons row outputs)) (set! trace (cons row trace)))
              (lambda () (set! trace (cons 'candidate trace)))
              (lambda (_atom _frame _delta _terms consume)
                (set! parts (+ parts 1))
                (and direct? (begin
                  (for-each (lambda (row) (consume [] (car row) (cadr row))) rows) #t))))
            (check-equal? reads (if direct? 0 1))
            (check-equal? parts 1)
            (check-equal? (reverse outputs) '((#f #f) (1 1)))
            (check-equal? (reverse trace) '(candidate (#f #f) candidate candidate (1 1)))))
          '(#f #t))))
    (poo-flow-test-case "stored atom keys and heads preserve admitted action representation"
      (for-each
       (lambda (columns)
         (let* ((first (vector 0 '((variable . x)) []))
                (second (vector 1 '((variable . x) (literal . #f) (variable . y)) columns))
                (head (vector 2 '((variable . y) (literal . #f) (variable . x) (variable . y))))
                (plan (gerbil-ascent-compile-positive-plan
                       (list head head) (list (vector 'atom first) (vector 'atom second))))
                (expected-terms '((bound . 0) (literal . #f) (fresh . 1)))
                (expected-key (map (lambda (column) (list-ref '((bound . 0) (literal . #f)) column)) columns))
                (frame (vector 'dirty-x 'dirty-y 'untouched)) (outputs []) (reads 0))
           (check-equal? (vector-ref plan 2) 2)
           (check-equal? (gerbil-ascent-pure-positive-plan? plan) #t)
           (check-equal? (vector-ref (car (vector-ref plan 1)) 1) '((fresh . 0)))
           (check-equal? (vector-ref (cadr (vector-ref plan 1)) 1) expected-terms)
           (check-equal? (vector-ref (cadr (vector-ref plan 1)) 2) expected-key)
           (for-each (lambda (output)
                       (check-equal? (vector-ref output 1)
                                     '((bound . 1) (literal . #f) (bound . 0) (bound . 1))))
                     (vector-ref plan 0))
           (def (run!)
             (gerbil-ascent-run-positive-plan! plan frame -1
               (lambda (atom environment delta? slot-terms)
                 (case (vector-ref atom 0)
                   ((0) '((#f) (7)))
                   ((1)
                    (set! reads (+ reads 1))
                    ;; The independent ordinary environment owns key truth;
                    ;; the fresh y cell must not contribute to the key.
                    (let* ((x (vector-ref environment 0))
                           (ordinary (list (cons 'x x))))
                      (check-equal?
                       (gerbil-ascent-index-key (vector-ref atom 1) columns environment slot-terms)
                       (gerbil-ascent-index-key (vector-ref atom 1) columns ordinary #f))
                      (list (list x #f 11) (list x #f #f))))
                   (else (error "unexpected stored action atom" atom))))
               (lambda (_ row) (set! outputs (cons row outputs)))))
           (run!)
           (run!)
           (check-equal? reads 4)
           (check-equal? (reverse outputs)
             (append '((11 #f #f 11) (11 #f #f 11) (#f #f #f #f) (#f #f #f #f)
                       (11 #f 7 11) (11 #f 7 11) (#f #f 7 #f) (#f #f 7 #f))
                     '((11 #f #f 11) (11 #f #f 11) (#f #f #f #f) (#f #f #f #f)
                       (11 #f 7 11) (11 #f 7 11) (#f #f 7 #f) (#f #f 7 #f))))
           (check-equal? frame (vector 7 #f 'untouched))))
       '(() (0) (0 0) (0 1) (1 0) (1 0 1)))
      (check-equal? (gerbil-ascent-compile-positive-plan
                     (list (vector 1 '((variable . absent))))
                     (list (vector 'atom (vector 0 '((variable . x)) [])))) #f))
    (poo-flow-test-case "finite frame extent rejects before reads and preserves unused dirty slots"
      (let* ((head (vector 2 '((variable . x) (variable . y))))
             (atom (vector 0 '((variable . x) (variable . y)) []))
             (plan (gerbil-ascent-compile-positive-plan (list head) (list (vector 'atom atom))))
             (short (vector 'old)) (reads 0) (outputs []))
        (check-equal? (vector-ref plan 2) 2)
        (check-exception
         (gerbil-ascent-run-positive-plan! plan short -1
           (lambda args (set! reads (+ reads 1)) '((#f 1)))
           (lambda args (error "unexpected output from rejected frame")))
         (lambda (failure) (equal? (error-message failure)
                          "ASCENT positive plan frame is smaller than compiled extent")))
        (check-equal? reads 0)
        (check-equal? short (vector 'old))
        (let (frame (vector 'stale 'stale 'untouched))
          (gerbil-ascent-run-positive-plan! plan frame -1
            (lambda args '((#f 1) (1 #f)))
            (lambda (_ row) (set! outputs (cons row outputs))))
          (check-equal? (reverse outputs) '((#f 1) (1 #f)))
          (check-equal? frame (vector 1 #f 'untouched)))))
    (poo-flow-test-case "delta ordinals reject before callbacks and preserve full ordered emissions"
      (let* ((terms '((variable . x)))
             (heads (list (vector 2 terms) (vector 3 terms) (vector 2 terms)))
             (callbacks 0) (reads []) (emissions []) (checkpoints 0)
             (plan
              (gerbil-ascent-compile-positive-plan
               heads (list (vector 'guard [] (lambda () (set! callbacks (+ callbacks 1)) #t))
                           (vector 'atom (vector 0 terms []))
                           (vector 'guard '(x) (lambda (_x) #t))
                           (vector 'atom (vector 1 terms [])))))
             (frame (make-vector (vector-ref plan 2) 'old))
             (all '#(((0) (1)) ((1) (0))))
             (delta '#(((1)) ((0)))))
        (check-equal? (vector-ref plan 4) 2)
        (for-each
         (lambda (pivot)
           (check-exception
            (gerbil-ascent-run-positive-plan! plan frame pivot
             (lambda args (set! reads (cons 'unexpected reads)) '((0)))
             (lambda args (set! emissions (cons 'unexpected emissions)))
             (lambda () (set! checkpoints (+ checkpoints 1))))
            (lambda (failure)
              (equal? (error-message failure)
                      "ASCENT positive plan delta selector outside compiled atom extent"))))
         '(-2 2 3 1/2 0.0 #f))
        (check-equal? callbacks 0)
        (check-equal? reads [])
        (check-equal? emissions [])
        (check-equal? checkpoints 0)
        (check-equal? (vector->list frame) '(old))
        (for-each
         (lambda (pivot)
           (set! reads []) (set! emissions [])
           (gerbil-ascent-run-positive-plan! plan frame pivot
            (lambda (atom _frame delta? _keys)
              (let (position (vector-ref atom 0))
                (set! reads (cons (cons position delta?) reads))
                (vector-ref (if delta? delta all) position)))
            (lambda (head row)
              (set! emissions (cons (cons (vector-ref head 0) row) emissions))))
           (let (expected
                 (body-binding-stream
                  (list (cons terms (vector-ref (if (= pivot 0) delta all) 0))
                        (cons terms (vector-ref (if (= pivot 1) delta all) 1))) heads))
             (check-equal? (reverse emissions) expected))
           (for-each
            (lambda (read)
              (check-equal? (cdr read) (= (car read) pivot))) reads))
         '(-1 0 1))
        (check-equal? callbacks 3)
        ;; Empty-body facts have only the total traversal; no delta pivot.
        (let* ((fact (gerbil-ascent-compile-positive-plan
                      (list (vector 0 [])) []))
               (fact-frame (make-vector 0)))
          (check-equal? (vector-ref fact 4) 0)
          (check-exception (gerbil-ascent-run-positive-plan! fact fact-frame 0
                             (lambda args []) (lambda args (error "unexpected fact"))) true)
          (let (facts [])
            (gerbil-ascent-run-positive-plan! fact fact-frame -1
              (lambda args (error "unexpected lookup"))
              (lambda (_ row) (set! facts (cons row facts))))
            (check-equal? facts '(()))))))
    (poo-flow-test-case "compiled keys require the prior bound prefix before current row matching"
      (let* ((x '(variable . x)) (y '(variable . y))
             (head (vector 1 (list x))) (calls 0)
             (expression (cons 'expression
                           (vector '(x) (lambda (_x) (set! calls (+ calls 1)) 0)))))
        (for-each
         (lambda (atom)
           (check-equal? (gerbil-ascent-compile-positive-plan
                          (list head) (list (vector 'atom atom))) #f))
         (list (vector 0 (list x) '(0))
               ;; The second occurrence is locally bound, but not prior-bound.
               (vector 0 (list x x) '(1))
               (vector 0 (list x '(wildcard . #f)) '(1))
               (vector 0 (list x expression) '(1))
               (vector 0 (list x) '(-1))
               (vector 0 (list x) '(1))
               (vector 0 (list x) '(0.0))
               (vector 0 (list x) '(0 . 1))))
        (check-equal? calls 0)
        ;; Prior-prefix reads, literal keys and repeated selected columns stay
        ;; supported. Compilation never evaluates the key expression itself.
        (let* ((plan (gerbil-ascent-compile-positive-plan
                      (list (vector 2 (list x y)))
                      (list (vector 'atom (vector 0 (list x) []))
                            (vector 'atom
                             (vector 1 (list x expression y '(literal . #f)) '(0 1 3 0))))))
               (second (cadr (vector-ref plan 1)))
               (keys (vector-ref second 2))
               (frame (vector #f 'dirty)))
          (check-equal? (gerbil-ascent-pure-positive-plan? plan) #f)
          (check-equal? calls 0)
          (check-equal? (gerbil-ascent-index-key [] [] frame keys) '(#f 0 #f #f))
          (check-equal? calls 1)
          (check-equal? frame (vector #f 'dirty)))))
    (poo-flow-test-case "dirty slot frames preserve ordered bindings across the finite term corpus"
      (let* ((palette '(#f 0 1))
             (terms '((variable . a) (variable . b) (literal . #f)
                      (literal . 0) (wildcard . #f)))
             (first-rows (map list palette))
             (second-rows
              (append-map (lambda (x)
                            (append-map (lambda (y)
                                          (map (lambda (z) (list x y z)) palette))
                                        palette)) palette))
             (checked 0))
        (for-each
         (lambda (one)
           (for-each
            (lambda (two)
              (for-each
               (lambda (three)
                 (let* ((patterns (list one two three))
                        (outputs
                         (append '((literal . #f) (variable . a))
                                 (if (member '(variable . b) patterns)
                                   '((variable . b)) [])))
                        (heads (list (vector 2 outputs) (vector 3 (reverse outputs))
                                     (vector 2 outputs)))
                        (body (list (vector 'atom (vector 0 '((variable . a)) []))
                                    (vector 'atom (vector 1 patterns []))))
                        (plan (gerbil-ascent-compile-positive-plan heads body))
                        (expected (binding-stream patterns heads first-rows second-rows)))
                   (for-each
                    (lambda (stale)
                      (let (frame (make-vector (vector-ref plan 2) stale))
                        (check-equal? (slot-stream plan frame first-rows second-rows) expected)
                        ;; A second whole traversal starts with the prior run's
                        ;; genuinely dirty frame; no artificial clearing occurs.
                        (check-equal? (slot-stream plan frame first-rows second-rows) expected)))
                    '(#f 0 1 stale-slot))
                   (set! checked (+ checked 1))
                   (displayln "SLOT-READ-CHECKED " checked " terms=" patterns)
                   (force-output))) terms)) terms)) terms)
        (check-equal? checked 125)))
    (poo-flow-test-case "nested branch returns preserve dirty-frame traversal order"
      (let* ((palette '(#f 0 1))
             (quadruples
              (append-map (lambda (x)
                (append-map (lambda (y)
                  (append-map (lambda (z)
                    (map (lambda (w) (list x y z w)) palette)) palette)) palette)) palette))
             (first '((variable . a)))
             (middle '((variable . b) (variable . a) (variable . b) (literal . 0)))
             (last '((variable . c) (variable . b) (variable . c) (variable . a)))
             (sources (vector (map list palette) quadruples quadruples))
             (output '((variable . a) (variable . b) (variable . c) (literal . #f)))
             (heads (list (vector 3 output) (vector 4 (reverse output)) (vector 3 output)))
             (plan (gerbil-ascent-compile-positive-plan heads
                     (list (vector 'atom (vector 0 first []))
                           (vector 'atom (vector 1 middle []))
                           (vector 'atom (vector 2 last [])))))
             (expected (body-binding-stream
                        (list (cons first (vector-ref sources 0))
                              (cons middle quadruples) (cons last quadruples)) heads)))
        (check-equal? (length expected) 81)
        (for-each
         (lambda (stale)
           (let (frame (make-vector (vector-ref plan 2) stale))
             (for-each
              (lambda (pass)
                (let ((emitted []) (reads (vector 0 0 0)))
                  (gerbil-ascent-run-positive-plan!
                   plan frame -1
                   (lambda (atom environment delta? slot-terms)
                     (let (source (vector-ref atom 0))
                       (vector-set! reads source (+ 1 (vector-ref reads source)))
                       (vector-ref sources source)))
                   (lambda (head row)
                     (set! emitted (cons (cons (vector-ref head 0) row) emitted))))
                  (check-equal? (reverse emitted) expected)
                  (check-equal? (vector->list reads) '(1 3 9))
                  (displayln "SLOT-NESTED-CHECKED stale=" stale " pass=" pass " emitted=" (length emitted))
                  (force-output))) '(first dirty-repeat))))
         '(#f 0 1 stale-slot))))
    (poo-flow-test-case "physical bucket selection and occurrence delta pivots refine the whole traversal"
      (let* ((palette '(#f 0 1 2))
             (quadruples
              (append-map (lambda (x)
                (append-map (lambda (y)
                  (append-map (lambda (z)
                    (map (lambda (w) (list x y z w)) palette)) palette)) palette)) palette))
             (first-rows (cons '(#f) (let loop ((n 0)) (if (= n 39) [] (cons (list n) (loop (+ n 1)))))))
             (first-delta '((#f) (0)))
             (changed (filter (lambda (row) (memv (car row) '(1 2))) quadruples))
             (prior (filter (lambda (row) (not (memv (car row) '(1 2)))) quadruples))
             (first '((variable . a)))
             (middle '((variable . b) (variable . a) (variable . b) (literal . 0)))
             (last '((variable . c) (variable . b) (variable . c) (variable . a)))
             (output '((variable . a) (variable . b) (variable . c) (literal . #f)))
             (heads (list (vector 3 output) (vector 4 (reverse output)) (vector 3 output)))
             (all (vector first-rows quadruples quadruples))
             (delta (vector first-delta changed changed))
             (old (vector (filter (lambda (row) (not (member row first-delta))) first-rows) prior prior))
             (all-output (body-binding-stream (list (cons first first-rows) (cons middle quadruples) (cons last quadruples)) heads))
             (old-output (body-binding-stream (list (cons first (vector-ref old 0)) (cons middle prior) (cons last prior)) heads)))
        (check-equal? (length quadruples) 256)
        (check-equal? (length changed) 128)
        (for-each
         (lambda (columns)
           (for-each
            (lambda (shared?)
              (let* ((atom0 (vector 0 first [] first []))
                     (atom1 (vector 1 middle columns middle (map (lambda (c) (list-ref middle c)) columns)))
                     (atom2 (vector (if shared? 1 2) last columns last (map (lambda (c) (list-ref last c)) columns)))
                     (positions (list atom0 atom1 atom2))
                     (plan (gerbil-ascent-compile-positive-plan heads (map (lambda (atom) (vector 'atom atom)) positions)))
                     (pivot-output []))
                (for-each
                 (lambda (pivot)
                   (let* ((selected (list (if (= pivot 0) first-delta first-rows)
                                          (if (= pivot 1) changed quadruples)
                                          (if (= pivot 2) changed quadruples)))
                          (expected (body-binding-stream
                                     (map cons (list first middle last) selected) heads)))
                     (set! pivot-output (append pivot-output expected))
                     (for-each
                      (lambda (stale)
                        (let* ((builds 0)
                               (probe (.o (:: @ gerbil-ascent-hash-index-provider)
                                 (.build-index (lambda (rows cols)
                                   (set! builds (+ builds 1))
                                   (gerbil-ascent-index-build rows cols)))
                                 (.extend-index! gerbil-ascent-index-extend!)
                                 (.lookup-index (lambda (index key) (or (hash-get index key) [])))))
                               (frame (make-vector (vector-ref plan 2) stale))
                               (probe-indexes (make-slot-indexes all delta probe))
                               (canonical-indexes (make-slot-indexes all delta gerbil-ascent-hash-index-provider)))
                          (check-equal? (indexed-slot-stream plan frame pivot all delta probe positions probe-indexes) expected)
                          (let (cold-builds builds)
                            (check-equal? (indexed-slot-stream plan frame pivot all delta probe positions probe-indexes) expected)
                            (check-equal? builds cold-builds))
                          (check-equal? (> builds 0) (not (null? columns)))
                          ;; The canonical receiver also exercises scalar keys
                          ;; for single-column indexes, using the dirty return.
                          (check-equal? (indexed-slot-stream plan frame pivot all delta
                                          gerbil-ascent-hash-index-provider positions canonical-indexes) expected)
                          (check-equal? (indexed-slot-stream plan frame pivot all delta
                                          gerbil-ascent-hash-index-provider positions canonical-indexes) expected)))
                      '(#f 0 1 stale-slot))
                     (displayln "SLOT-INDEX-PIVOT-CHECKED columns=" columns " shared=" shared? " pivot=" pivot
                                " emitted=" (length expected))
                     (force-output))) '(0 1 2))
                (for-each (lambda (row) (check-equal? (and (member row all-output) #t) #t)) pivot-output)
                (for-each
                 (lambda (row) (unless (member row old-output)
                                 (check-equal? (and (member row pivot-output) #t) #t))) all-output)
                ;; A wrong occurrence or a dropped candidate must be visible.
                (let* ((expected (body-binding-stream
                                  (list (cons first first-rows) (cons middle changed) (cons last quadruples)) heads))
                       (wrong (indexed-slot-stream plan (make-vector (vector-ref plan 2) 'stale)
                                2 all delta gerbil-ascent-hash-index-provider positions))
                       (dropped (vector first-delta [] changed)))
                  (check-equal? (equal? wrong expected) #f)
                  (check-equal? (equal? (indexed-slot-stream plan (make-vector (vector-ref plan 2) 'stale)
                                        1 all dropped gerbil-ascent-hash-index-provider positions) expected) #f))))
            '(#f #t))) '(() (1) (1 3) (3 1) (1 1)))))
    (poo-flow-test-case "persistent indexed delta rounds agree with full scans and stable reachability"
      (let* ((vertices (append (iota 12) (map (lambda (n) (+ n 20)) (iota 6))))
             (edges (append (map (lambda (n) (list n (+ n 1))) (iota 11))
                            (append-map (lambda (x) (map (lambda (y) (list x y)) (map (lambda (n) (+ n 20)) (iota 6))))
                                        (map (lambda (n) (+ n 20)) (iota 6)))))
             (nodes (map list vertices))
             (copy (gerbil-ascent-compile-positive-plan
                    (list (vector 1 '((variable . x) (variable . y)))
                          (vector 1 '((variable . x) (variable . y))))
                    (list (vector 'atom (vector 0 '((variable . x) (variable . y)) [] [] [])))))
             (recursive (gerbil-ascent-compile-positive-plan
                         (list (vector 1 '((variable . x) (variable . z))))
                         (list (vector 'atom (vector 2 '((variable . x)) [] [] []))
                               (vector 'atom (vector 1 '((variable . x) (variable . y)) '(0) [] '((variable . x))))
                               (vector 'atom (vector 0 '((variable . y) (variable . z)) '(0) [] '((variable . y)))))))
             (all (vector edges [] nodes)) (delta (vector [] [] []))
             (all-size (vector (length edges) 0 (length nodes))) (delta-size (vector 0 0 0))
             (all-version (vector 0 0 0)) (delta-version (vector 0 0 0))
             (indexes (gerbil-ascent-make-row-indexes all delta all-size delta-size all-version delta-version
                        (make-vector 3 gerbil-ascent-hash-index-provider)))
             (access (row-indexes-rows indexes)) (advance! (row-indexes-advance! indexes))
             (copy-frame (make-vector (vector-ref copy 2) 'stale))
             (recursive-frame (make-vector (vector-ref recursive 2) 'stale))
             (seen (make-hash-table)) (pending []) (rounds 0) (stable #f))
        (def (admit head row)
          (check-equal? (vector-ref head 0) 1)
          (unless (hash-get seen row) (hash-put! seen row #t) (set! pending (cons row pending))))
        ;; Missing full initialization is a real fault: static source deltas
        ;; are empty, so delta-only execution falsely reports empty completion.
        (for-each (lambda (pivot) (gerbil-ascent-run-positive-plan! copy copy-frame pivot access admit)) '(0))
        (for-each (lambda (pivot) (gerbil-ascent-run-positive-plan! recursive recursive-frame pivot access admit)) '(0 1 2))
        (check-equal? pending [])
        (check-equal? (null? (scan-path-step edges [])) #f)
        (let loop ()
          (let* ((before (vector-ref all 1)) (expected (scan-path-step edges before)))
            (set! pending [])
            (if (= rounds 0)
              (begin (gerbil-ascent-run-positive-plan! copy copy-frame -1 access admit)
                     (gerbil-ascent-run-positive-plan! recursive recursive-frame -1 access admit))
              (begin
                (gerbil-ascent-run-positive-plan! copy copy-frame 0 access admit)
                (for-each (lambda (pivot)
                            (gerbil-ascent-run-positive-plan! recursive recursive-frame pivot access admit)) '(0 1 2))))
            ;; Publication waits for all rule traversals. Frames and physical
            ;; caches persist across rounds; only admitted new rows advance.
            (advance! 1 pending #t)
            (vector-set! all 1 (append pending before))
            (vector-set! all-size 1 (+ (vector-ref all-size 1) (length pending)))
            (unless (null? pending) (vector-set! all-version 1 (+ (vector-ref all-version 1) 1)))
            (vector-set! delta 1 pending)
            (vector-set! delta-size 1 (length pending))
            (vector-set! delta-version 1 (+ (vector-ref delta-version 1) 1))
            (check-path-set (vector-ref all 1) expected)
            (set! rounds (+ rounds 1))
            (displayln "SLOT-HISTORY-ROUND " rounds " admitted=" (length pending) " known=" (vector-ref all-size 1))
            (force-output)
            (if (null? pending) (set! stable #t) (loop))))
        (check-equal? stable #t)
        (check-equal? rounds 12)
        (check-equal? (vector-ref all-size 1) 102)
        ;; Independent Boolean Floyd closure includes the disconnected clique;
        ;; it does not reuse the synchronous scan oracle or engine traversals.
        (let ((matrix (make-vector (* 18 18) #f)) (expected []))
          (def (position n) (if (< n 12) n (+ 12 (- n 20))))
          (for-each (lambda (edge) (vector-set! matrix (+ (* 18 (position (car edge))) (position (cadr edge))) #t)) edges)
          (for-each (lambda (k)
            (for-each (lambda (x)
              (for-each (lambda (y)
                (when (and (vector-ref matrix (+ (* 18 x) k)) (vector-ref matrix (+ (* 18 k) y)))
                  (vector-set! matrix (+ (* 18 x) y) #t))) (iota 18))) (iota 18))) (iota 18))
          (for-each (lambda (x)
            (for-each (lambda (y)
              (when (vector-ref matrix (+ (* 18 (position x)) (position y)))
                (set! expected (cons (list x y) expected)))) vertices)) vertices)
          (check-path-set (vector-ref all 1) expected))
        ;; Execute a further round on the actual stable frame/cache state.
        (set! pending [])
        (for-each (lambda (pivot) (gerbil-ascent-run-positive-plan! recursive recursive-frame pivot access admit)) '(0 1 2))
        (check-equal? pending [])))
    (poo-flow-test-case "failed partial writes require the next fresh overwrite"
      (let* ((patterns '((variable . b) (variable . a) (variable . b)))
             (heads (list (vector 2 '((variable . a) (variable . b)))))
             (plan (gerbil-ascent-compile-positive-plan heads
                     (list (vector 'atom (vector 0 '((variable . a)) []))
                           (vector 'atom (vector 1 patterns [])))))
             (atoms (vector-ref plan 1))
             (second (cadr atoms))
             (actions (vector-ref second 1))
             (frame (make-vector 2 'stale))
             (first-rows '((0)))
             (second-rows '((7 1 7) (4 0 4)))
             (fault
              (vector (vector-ref plan 0)
                      (list (car atoms)
                            (vector (vector-ref second 0)
                                    (cons '(bound . 1) (cdr actions))
                                    (vector-ref second 2)))
                      (vector-ref plan 2))))
        (check-equal? actions '((fresh . 1) (bound . 0) (bound . 1)))
        (check-equal? (slot-stream plan frame first-rows second-rows) '((2 0 4)))
        (check-equal? (vector->list frame) '(0 4))
        (check-equal? (binding-stream patterns heads first-rows second-rows) '((2 0 4)))
        ;; Faulted lowering reads the rejected row's old slot rather than
        ;; initializing it. The independent ordinary binder still succeeds.
        (check-equal? (slot-stream fault (vector 0 7) first-rows second-rows) [])))
    (poo-flow-test-case "analysis builds stay reentrant and failure leaves cached versions usable"
      (let* ((program (path-program '((0 1))))
             (relations (.ref program 'relations))
             (rules (.ref program 'rules)))
        (check-exception
         (gerbil-ascent-program-analysis program relations rules
           (lambda () (error "failed cold analysis"))) true)
        (let (outer
              (gerbil-ascent-program-analysis program relations rules
                (lambda ()
                  (let (inner
                        (gerbil-ascent-program-analysis program relations rules
                          (lambda () (vector relations rules 'inner))))
                    (check-equal? (vector-ref inner 2) 'inner))
                  (vector relations rules 'outer))))
          (check-equal?
           (eq? outer (gerbil-ascent-program-analysis program relations rules
                        (lambda () (error "warm analysis must not rebuild")))) #t)
          (check-exception
           (gerbil-ascent-program-analysis program relations (map identity rules)
             (lambda () (error "failed new declaration version"))) true)
          (check-equal?
           (eq? outer (gerbil-ascent-program-analysis program relations rules
                        (lambda () (error "failed build must not replace old entry")))) #t))))
    (poo-flow-test-case "schema failures preserve warm entries and new declaration identities rebuild"
      (let* ((program (path-program '((0 1))))
             (relations (.ref program 'relations))
             (schema (gerbil-ascent-program-schema program relations)))
        (check-exception
         (gerbil-ascent-program-schema program (cons (car relations) relations)) true)
        (check-equal? (eq? schema (gerbil-ascent-program-schema program relations)) #t)
        (let* ((replacement (map identity relations))
               (fresh (gerbil-ascent-program-schema program replacement)))
          (check-equal? (eq? fresh schema) #f)
          (check-equal? (vector-ref fresh 1) (vector-ref schema 1))
          (check-equal? (eq? replacement (vector-ref fresh 0)) #t)
          (check-equal? (eq? fresh (gerbil-ascent-program-schema program replacement)) #t))))
    (poo-flow-test-case "analysis shares immutable activations while every engine owns its frames"
      (let* ((program (path-program '((0 1) (1 2))))
             (first (gerbil-ascent-make-engine program #t))
             (analysis (.ref first '.analysis))
             (second (gerbil-ascent-make-engine program #t))
             (a (car (vector-ref (gerbil-ascent-activate-rules analysis) 0)))
             (b (car (vector-ref (gerbil-ascent-activate-rules analysis) 0))))
        (check-equal? (eq? analysis (.ref second '.analysis)) #t)
        (check-equal? (eq? (vector-ref analysis 6)
                          (vector-ref (.ref second '.analysis) 6)) #t)
        (check-equal? (vector-ref analysis 6) '#((1 1) (1)))
        (check-equal? (eq? (vector-ref a 4) (vector-ref b 4)) #t)
        (check-equal? (eq? (vector-ref a 5) (vector-ref b 5)) #t)
        (check-equal? (eq? (vector-ref a 6) (vector-ref b 6)) #f)
        (vector-set! (vector-ref a 6) 0 'private)
        (check-equal? (vector-ref (vector-ref b 6) 0) #f)
        (check-equal? (rows ((.ref first '.run)) 'path) (rows ((.ref second '.run)) 'path))))
    (poo-flow-test-case "partial heads share lowered atoms and preserve duplicates with fresh frames"
      (let* ((x (v 'x))
             (program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'source 1 '((7)))
                     (gerbil-ascent-relation 'left 1 [])
                     (gerbil-ascent-relation 'right 1 []))
               (list (gerbil-ascent-rule (list (a 'left (gerbil-ascent-literal 9))
                                               (a 'left x) (a 'right x) (a 'left x))
                                        (list (a 'source x)))) 4 8 12))
             (engine (gerbil-ascent-make-engine program #t))
             (active (gerbil-ascent-activate-rules (.ref engine '.analysis)))
             (full (car (vector-ref active 0)))
             (selected (car (vector-ref (gerbil-ascent-update-active-plans active '#(#f #t #f)) 0)))
             (plan (vector-ref full 5)) (partial (vector-ref selected 5))
             (emissions []))
        (check-equal? (length (vector-ref partial 0)) 3)
        (check-equal? (eq? (vector-ref plan 1) (vector-ref partial 1)) #t)
        (check-equal? (vector-ref plan 2) (vector-ref partial 2))
        (check-equal? (vector-ref plan 4) (vector-ref partial 4))
        (check-equal? (eq? (vector-ref full 6) (vector-ref selected 6)) #f)
        (check-equal? (length (vector-ref plan 0)) 4)
        (gerbil-ascent-run-positive-plan!
         partial (vector-ref selected 6) -1 (lambda args '((7)))
         (lambda (head row)
           (set! emissions (cons (cons (vector-ref head 0) row) emissions))))
        (check-equal? emissions '((1 7) (1 7) (1 9)))
        (check-equal? (vector-ref (gerbil-ascent-update-active-plans active '#(#f #f #f)) 0) [])
        (check-equal? (eq? full (car (vector-ref (gerbil-ascent-update-active-plans active '#(#f #t #t)) 0))) #t)))
    (poo-flow-test-case "positional slot selection preserves all key orders and action identity"
      (for-each
       (lambda (width)
         (let* ((terms (map (lambda (_) (cons 'variable (gensym 'slot))) (iota width)))
                (head (vector 2 terms))
                (source (vector 0 terms [])))
           (for-each
            (lambda (columns)
              (let* ((atom (vector 1 terms columns))
                     (body (list (vector 'atom source) (vector 'atom atom)))
                     (new (gerbil-ascent-compile-positive-plan (list head) body))
                     (compiled (cadr (vector-ref new 1))))
                (check-equal? (vector-ref new 2) width)
                (check-equal? (vector-ref (car (vector-ref new 1)) 1)
                              (map (cut cons 'fresh <>) (iota width)))
                (check-equal? (vector-ref compiled 1)
                              (map (cut cons 'bound <>) (iota width)))
                (check-equal? (vector-ref compiled 2) (map (cut cons 'bound <>) columns))
                (check-equal?
                 (andmap (lambda (action column)
                           (eq? action (list-ref (vector-ref compiled 1) column)))
                         (vector-ref compiled 2) columns) #t)))
            (list [] (list (- width 1)) (list 0 (- width 1))
                  (filter even? (iota width)) (iota width)
                  (reverse (iota width)) (append (iota width) (iota width))))))
       '(7 8 9 32 127 128 129 512 1024)))
    (poo-flow-test-case "wide slot keys preserve literals repeats wildcards and unsupported callbacks"
      (let* ((terms (map (lambda (n)
                          (case (modulo n 3)
                            ((0) '(variable . x))
                            ((1) '(literal . #f))
                            (else '(wildcard . #f)))) (iota 384)))
             (columns (filter (lambda (n) (= (modulo n 3) 1)) (iota 384)))
             (body (list (vector 'atom (vector 0 terms columns))))
             (heads (list (vector 1 '((variable . x) (literal . #f)))))
             (plan (gerbil-ascent-compile-positive-plan heads body))
             (compiled (car (vector-ref plan 1))))
        (check-equal? (vector-ref plan 2) 1)
        (check-equal? (vector-ref compiled 1)
          (map (lambda (n)
                 (case (modulo n 3)
                   ((0) (cons (if (zero? n) 'fresh 'bound) 0))
                   ((1) '(literal . #f))
                   (else '(wildcard . #f)))) (iota 384)))
        (check-equal? (vector-ref compiled 2)
                      (map (lambda (_) '(literal . #f)) columns))
        ;; A shape-correct projection is not a valid pre-match key: this
        ;; all-column selection contains fresh slots and wildcard actions.
        (check-equal?
         (gerbil-ascent-compile-positive-plan heads
           (list (vector 'atom (vector 0 terms (iota 384))))) #f)
        (check-equal?
         (gerbil-ascent-compile-positive-plan heads
           (list (vector 'atom (vector 0 '((expression . #f)) '(0))))) #f)))
    (poo-flow-test-case "wide composite joins preserve provider keys and output rows"
      (for-each
       (lambda (width)
         (let* ((variables (map (lambda (_) (v (gensym 'join))) (iota width)))
                (row (cons #f (cdr (iota width))))
                (calls [])
                (provider
                 (.o (:: @ gerbil-ascent-hash-index-provider)
                     (.lookup-index
                      (lambda (table key)
                        (set! calls (cons key calls))
                        ((.ref gerbil-ascent-hash-index-provider '.lookup-index) table key)))))
                (p (gerbil-ascent-program
                    (list (gerbil-ascent-relation 'left width (list row))
                          (gerbil-ascent-relation 'right width (list row) provider)
                          (gerbil-ascent-relation 'out width []))
                    (list (gerbil-ascent-rule
                           (list (gerbil-ascent-atom 'out (reverse variables)))
                           (list (gerbil-ascent-atom 'left variables)
                                 (gerbil-ascent-atom 'right variables)))) 8 8 16))
                (old (ascent-positive-plan-reference-evaluate-program p))
                (old-calls calls))
           (set! calls [])
           (let (new (gerbil-ascent-evaluate-program p))
             (check-equal? calls old-calls)
             (check-equal? (rows new 'out) (rows old 'out))
             (check-equal? (rows new 'out) (list (reverse row))))))
       '(7 8 9 64 127 128 129)))
    (poo-flow-test-case "all 512 directed three-node graphs match independent reachability"
      (let (pairs (apply append (map (lambda (x) (map (lambda (y) (list x y)) '(0 1 2))) '(0 1 2))))
        (for-each
         (lambda (bits)
           (let* ((edges (filter-map (lambda (edge index)
                                     (and (not (zero? (bitwise-and bits (arithmetic-shift 1 index)))) edge)) pairs (iota 9)))
                  (matrix (make-vector 9 #f)))
             (for-each (lambda (edge) (vector-set! matrix (+ (* 3 (car edge)) (cadr edge)) #t)) edges)
             (for-each
              (lambda (k)
                (for-each (lambda (x)
                            (for-each (lambda (y)
                                        (when (and (vector-ref matrix (+ (* 3 x) k))
                                                   (vector-ref matrix (+ (* 3 k) y)))
                                          (vector-set! matrix (+ (* 3 x) y) #t))) '(0 1 2))) '(0 1 2))) '(0 1 2))
             ;; Matrix closure is the independent oracle for this exhaustive
             ;; corpus. Historical evaluator parity remains in focused Cases;
             ;; replaying it here duplicates admission for all 512 graphs.
             (let* ((result (gerbil-ascent-evaluate-program (path-program edges)))
                    (actual (rows result 'path))
                   (expected (filter (lambda (edge) (vector-ref matrix (+ (* 3 (car edge)) (cadr edge)))) pairs)))
               (check-equal? (.ref result 'finished) #t)
               (check-equal? (rows result 'edge) edges)
               (check-equal? (length actual) (length expected))
               (check-equal? (andmap (lambda (edge) (if (member edge actual) #t #f)) expected) #t))
             (when (zero? (modulo (+ bits 1) 8))
               (displayln "POSITIVE-GRAPHS-CHECKED " (+ bits 1) "/512")
               (force-output))))
         (iota 512))))
    (poo-flow-test-case "ground binder witnesses preserve shared reads and duplicate multiple heads"
      (let* ((x (v 'x)) (y (v 'y))
             (result
              (compare
               (gerbil-ascent-program
                (list (gerbil-ascent-relation 'input 3 '((0 0 0) (1 1 1) (1 2 1)))
                      (gerbil-ascent-relation 'join 2 '((1 7) (2 8)))
                      (gerbil-ascent-relation 'out 2 [])
                      (gerbil-ascent-relation 'flag 0 []))
                (list (gerbil-ascent-rule
                       (list (a 'out x y) (a 'out x y) (a 'flag))
                       (list (a 'input x x (gerbil-ascent-literal 1)) (a 'join x y))))
                32 32 64)
               '(out flag))))
        (check-equal? (rows result 'out) '((1 7)))
        (check-equal? (rows result 'flag) '(()))))
    (poo-flow-test-case "failed candidates and repeated variables never expose stale slots"
      (let ((x (v 'x)) (y (v 'y)))
        (let (result (compare
                      (gerbil-ascent-program
                       (list (gerbil-ascent-relation 'input 3 '((1 2 0) (3 3 1) (4 4 0) (5 6 1) (#f #f 1)))
                             (gerbil-ascent-relation 'out 1 []))
                       (list (gerbil-ascent-rule (list (a 'out x))
                                                (list (a 'input x x (gerbil-ascent-literal 1))))) 32 32 64)
                      '(out)))
          (check-equal? (rows result 'out) '((3) (#f))))))
    (poo-flow-test-case "wildcards zero-arity atoms and literal heads preserve ordered outputs"
      (let ((x (v 'x)) (w (gerbil-ascent-wildcard)))
        (let (result (compare
                      (gerbil-ascent-program
                       (list (gerbil-ascent-relation 'flag 0 '(()))
                             (gerbil-ascent-relation 'input 2 '((1 a) (2 b) (1 c)))
                             (gerbil-ascent-relation 'out 2 []))
                       (list (gerbil-ascent-rule (list (a 'out (gerbil-ascent-literal 'tag) x))
                                                (list (a 'flag) (a 'input x w)))) 32 32 64)
                      '(out)))
          (check-equal? (rows result 'out) '((tag 2) (tag 1))))))
    (poo-flow-test-case "indexed fanout and multiple heads retain exact key and callback order"
      (let* ((x (v 'x)) (y (v 'y)) (calls [])
             (provider (.o (:: @ gerbil-ascent-hash-index-provider)
                           (.lookup-index (lambda (table key)
                                      (set! calls (cons key calls))
                                      ((.ref gerbil-ascent-hash-index-provider '.lookup-index) table key)))))
             (p (gerbil-ascent-program
                 (list (gerbil-ascent-relation 'left 1 '((0) (1)))
                       (gerbil-ascent-relation 'right 2 (map (lambda (n) (list (modulo n 2) n)) (iota 40)) provider)
                       (gerbil-ascent-relation 'out 2 [])
                       (gerbil-ascent-relation 'copy 1 []))
                 (list (gerbil-ascent-rule (list (a 'out x y) (a 'copy y))
                                          (list (a 'left x) (a 'right x y)))) 64 128 192))
             (old (ascent-positive-plan-reference-evaluate-program p)) (old-calls calls))
        (set! calls [])
        (let (new (gerbil-ascent-evaluate-program p))
          (check-equal? calls old-calls)
          (check-equal? (rows new 'out) (rows old 'out))
          (check-equal? (rows new 'copy) (rows old 'copy)))))
    (poo-flow-test-case "custom output expansion observes the same candidates and pending snapshots"
      (let* ((x (v 'x)) (calls [])
             (storage (.o (:: @ gerbil-ascent-set-storage-provider)
                          (.extend-rows (lambda (_state all pending row budget)
                                          (set! calls (cons (list all pending row budget) calls))
                                          (list row (list (+ 10 (car row))))))))
             (p (gerbil-ascent-program
                 (list (gerbil-ascent-relation 'input 1 '((1) (1) (2)))
                       (gerbil-ascent-relation 'out 1 [] gerbil-ascent-hash-index-provider storage))
                 (list (gerbil-ascent-rule (list (a 'out x)) (list (a 'input x)))) 32 32 64))
             (old (ascent-positive-plan-reference-evaluate-program p)) (old-calls calls))
        (set! calls [])
        (let (new (gerbil-ascent-evaluate-program p))
          (check-equal? (rows new 'out) (rows old 'out))
          (check-equal? calls old-calls))))
    (poo-flow-test-case "retained appends replacements and zero-timeout runs preserve snapshots"
      (let* ((p (path-program '((0 1) (1 2))))
             (old (ascent-positive-plan-reference-make-engine p #t))
             (new (gerbil-ascent-make-engine p #t))
             (old-first ((.ref old '.run))) (new-first ((.ref new '.run))))
        (for-each (lambda (engine) ((.ref engine '.append-source!) 'edge '(2 0))) (list old new))
        (for-each (lambda (engine) ((.ref engine '.run-timeout) 0)) (list old new))
        (check-equal? (rows ((.ref new '.run)) 'path) (rows ((.ref old '.run)) 'path))
        (check-equal? (rows old-first 'path) (rows new-first 'path))
        (for-each (lambda (engine) ((.ref engine '.replace-source!) 'edge '((2 1)))) (list old new))
        (check-equal? (rows ((.ref new '.run)) 'path) (rows ((.ref old '.run)) 'path))))
    (poo-flow-test-case "wide rules read numeric slots without a fixed variable limit"
      (let* ((variables (map (lambda (n) (v (string->symbol (string-append "v" (number->string n))))) (iota 40)))
             (source (iota 40))
             (p (gerbil-ascent-program
                 (list (gerbil-ascent-relation 'input 40 (list source))
                       (gerbil-ascent-relation 'out 40 []))
                 (list (gerbil-ascent-rule
                        (list (gerbil-ascent-atom 'out (reverse variables)))
                        (list (gerbil-ascent-atom 'input variables)))) 16 16 32)))
        (check-equal? (rows (compare p '(out)) 'out) (list (reverse source)))))
    (poo-flow-test-case "compiled emission preserves derived and output budget errors"
      (def (outcome solve p)
        (with-catch (lambda (failure) (error-message failure)) (lambda () (solve p) 'success)))
      (for-each
       (lambda (limits)
         (let* ((x (v 'x))
                (p (gerbil-ascent-program
                    (list (gerbil-ascent-relation 'input 1 '((1) (2)))
                          (gerbil-ascent-relation 'out 1 []))
                    (list (gerbil-ascent-rule (list (a 'out x)) (list (a 'input x))))
                    16 (car limits) (cadr limits))))
           (check-equal? (outcome gerbil-ascent-evaluate-program p)
                         (outcome ascent-positive-plan-reference-evaluate-program p))
           (check-equal? (outcome gerbil-ascent-evaluate-program p) (caddr limits))))
       '((1 64 "ASCENT derived fact budget exceeded")
         (64 3 "ASCENT output fact budget exceeded"))))
    (poo-flow-test-case "cached plans never share frames across concurrent engines"
      (let* ((p (path-program '((0 1) (1 2) (2 0))))
             (expected (rows (ascent-positive-plan-reference-evaluate-program p) 'path))
             (workers (map (lambda (_) (spawn (lambda () (rows (gerbil-ascent-evaluate-program p) 'path)))) (iota 8))))
        (for-each (lambda (worker) (check-equal? (thread-join! worker) expected)) workers)))
    (poo-flow-test-case "unsupported callback clauses preserve callback traces"
      (let* ((x (v 'x)) (calls [])
             (p (gerbil-ascent-program
                 (list (gerbil-ascent-relation 'input 1 '((1) (2)))
                       (gerbil-ascent-relation 'out 1 []))
                 (list (gerbil-ascent-rule (list (a 'out x))
                                          (list (a 'input x)
                                                (gerbil-ascent-guard '(x) (lambda (value) (set! calls (cons value calls)) #t))))) 32 32 64))
             (old (ascent-positive-plan-reference-evaluate-program p)) (old-calls calls))
        (set! calls [])
        (let (new (gerbil-ascent-evaluate-program p))
          (check-equal? calls old-calls)
          (check-equal? (rows new 'out) (rows old 'out)))))))
