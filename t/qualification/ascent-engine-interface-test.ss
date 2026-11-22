;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/encoding/json :gerbil-ascent/interface/engine-api
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/core/view-value make-relation-view make-ordered-binary-visitors
                 make-packed-binary-visitors gerbil-ascent-ordered-binary-copy!
                 gerbil-ascent-view-with-export)
        (only-in :gerbil-ascent/program/result gerbil-ascent-make-published-result)
        (only-in :gerbil-ascent/core/execution-control current-ascent-execution-control)
        (only-in :gerbil-ascent/program/func gerbil-ascent-program gerbil-ascent-relation
                 gerbil-ascent-variable gerbil-ascent-rule gerbil-ascent-atom)
        (only-in :gerbil-ascent/program/actor-session gerbil-ascent-open-actor-session
                 gerbil-ascent-session-close! gerbil-ascent-session-last-completed)
        (only-in :gerbil-ascent/program/session gerbil-ascent-session-run
                 gerbil-ascent-session-replace-source!))
(export ascent-engine-interface-test)
(def (request value)
  (parameterize ((current-json-read-options (JSONReadOptions object-as-hash: #t)))
    (string->json (ascent-engine-dispatch (json->string value)))))
(def (v name) (hash ("var" name)))
(def (a relation . terms) (hash ("relation" relation) ("terms" terms)))
(def (r head . body) (hash ("head" (list head)) ("body" body)))
(def (relation n width source rows)
  (hash ("name" n) ("columns" (make-list width (hash ("kind" "symbol"))))
        ("source" source) ("rows" rows)))
(def (program)
  (let ((x (v "x")) (y (v "y")) (z (v "z")))
    (hash ("relations" (list (relation "edge" 2 #t '(("a" "b") ("b" "c")))
                            (relation "blocked" 1 #t '(("c")))
                            (relation "path" 2 #f []) (relation "safe" 2 #f [])))
          ("rules" (list (r (a "path" x y) (a "edge" x y))
                         (r (a "path" x z) (a "path" x y) (a "edge" y z))
                         (r (a "safe" x y) (a "path" x y)
                            (hash ("relation" "blocked") ("terms" (list y)) ("not" #t)))))
          ("queries" '("path" "safe")))))
(def (run handle (timeout 1000000000))
  (request (hash ("operation" "run") ("handle" handle) ("timeoutNanoseconds" timeout))))
(def (rows result name) (hash-ref (hash-ref result "relations") name))
(def (same? actual expected)
  (and (= (length actual) (length expected)) (andmap (lambda (row) (and (member row actual) #t)) expected)))

(def (open-reachability edges bound)
  (let (source
         (object->string
          `(ascent
            (relation edge (from to) (quote ,edges))
            (relation reach (from to))
            ((reach x y) <-- (edge x y))
            ((reach x z) <-- (reach x y) (edge y z))
            (bounds 32 ,bound 128))))
    (hash-ref
     (ascent-engine-call (hash ("operation" "open-sources") ("sources" (list source))))
     "handle")))

(def (open-ordered-projection)
  (hash-ref
   (ascent-engine-call
    (hash ("operation" "open-sources")
          ("sources" '("(ascent (relation edge (from to) '()) (relation reach (from to)) ((reach x y) <-- (edge x y)) (bounds 2048 2048 4096))"))))
   "handle"))

(def (ordered-rows offset)
  (map (lambda (i) (list (- offset i) (+ offset (* 2 i)))) (iota 2048)))

(def (open-ordered-actor edges (recursive? #f))
  (let* ((x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y))
         (z (gerbil-ascent-variable 'z))
         (edge (gerbil-ascent-atom 'edge (list x y)))
         (reach (gerbil-ascent-atom 'reach (list x y)))
         (base (gerbil-ascent-rule (list reach) (list edge))))
    (gerbil-ascent-open-actor-session
     (gerbil-ascent-program
      (list (gerbil-ascent-relation 'edge 2 edges)
            (gerbil-ascent-relation 'reach 2 []))
      (if recursive?
        (list base
              (gerbil-ascent-rule
               (list (gerbil-ascent-atom 'reach (list x z)))
               (list reach (gerbil-ascent-atom 'edge (list y z)))))
        (list base))
      2048 2048 4096)
     workers: 1)))

(def (source-run handle duration (packed-rows? #f))
  (ascent-engine-call
   (hash ("operation" "source-run") ("handle" handle)
         ("timeoutNanoseconds" duration) ("queries" '("reach")))
   packed-rows?))

(def (open-typed-reachability edges)
  (let (source
         (object->string
          `(define-program (make)
             (sources edge) (outputs reach)
             (relation edge ((a exact-integer?) (b exact-integer?)) (quote ,edges))
             (relation reach ((a exact-integer?) (b exact-integer?)))
             ((reach a b) <-- (edge a b))
             ((reach a c) <-- (reach a b) (edge b c)))))
    (hash-ref
     (ascent-engine-call
      (hash ("operation" "open-program") ("source" source)
            ("constructor" "make") ("arguments" []) ("trusted" #t)))
     "handle")))

(def (proof-scope handle result)
  (ascent-engine-call
   (hash ("operation" "owned-result") ("handle" handle)
         ("result" (hash-ref result "resultHandle"))
         ("action" "proof-scope") ("relation" "reach"))))

(def (replace-edges! handle edges (packed-rows? #f))
  (ascent-engine-call
   (hash ("operation" "source-replace") ("handle" handle)
         ("sources" (list (hash ("relation" "edge") ("rows" edges)))))
   packed-rows?))

(def (same-datum? left right)
  (cond
    ((hash-table? left)
     (and (hash-table? right) (= (hash-length left) (hash-length right))
          (andmap (lambda (entry)
                    (and (hash-key? right (car entry))
                         (same-datum? (cdr entry) (hash-ref right (car entry)))))
                  (hash->list left))))
    ((pair? left)
     (and (pair? right) (same-datum? (car left) (car right))
          (same-datum? (cdr left) (cdr right))))
    (else (equal? left right))))

(def (check-source-projection handle packed?)
  (let* ((request (hash ("operation" "source-projection") ("handle" handle)))
         (ordinary (ascent-engine-call request))
         (encoded (ascent-engine-call request #t))
         (before (hash-ref ordinary "program"))
         (after (hash-ref encoded "program")))
    (check-equal? (hash-ref encoded "status") "supported")
    (check-equal? (hash-ref encoded "sourceGeneration") (hash-ref ordinary "sourceGeneration"))
    (check-equal? (hash-length before) (hash-length after))
    (for-each
      (lambda (entry)
        (unless (equal? (car entry) "relations")
          (check-equal? (same-datum? (cdr entry) (hash-ref after (car entry))) #t)))
      (hash->list before))
    (check-equal? (length (hash-ref before "relations")) (length (hash-ref after "relations")))
    (for-each
      (lambda (left right)
        (check-equal? (hash-length left) (hash-length right))
        (for-each
          (lambda (entry)
            (if (equal? (car entry) "rows")
              (let* ((rows (cdr entry)) (packet (hash-ref right "rows"))
                     (expected? (and packed? (not (null? rows)))))
                (check-equal? (s64vector? packet) expected?)
                (if expected?
                  (check-equal? (s64vector->list packet)
                                (append (list (length rows) (length (car rows)))
                                        (apply append rows)))
                  (check-equal? (same-datum? rows packet) #t)))
              (check-equal? (same-datum? (cdr entry) (hash-ref right (car entry))) #t)))
          (hash->list left)))
      (hash-ref before "relations") (hash-ref after "relations"))
    ;; Private transport must not mutate the Session's retained catalogue.
    (check-equal? (same-datum? ordinary (ascent-engine-call request)) #t)))

(def ascent-engine-interface-test
  (test-suite "Public inert engine contract for C ABI consumers"
    (test-case "affine and recursive copiers preserve the detached row order"
      (for-each
       (lambda (case)
         (let* ((recursive? (car case))
                (rows (cadr case))
                (count (caddr case))
                (session (open-ordered-actor rows recursive?))
                (target (make-s64vector (+ 2 (* 2 count)) -1)))
           (try
             (let* ((result (gerbil-ascent-session-run session))
                    (list-rows ((.ref result 'rows-of) 'reach))
                    (copy! ((.ref result 'with-ordered-binary-fields)
                            'reach (lambda (_count _visit copy!) copy!) #t)))
               (check-equal? (length list-rows) count)
               (check-equal? (procedure? copy!) #t)
               (check-exception (copy! target 3) true)
               (check-equal? target (make-s64vector (+ 2 (* 2 count)) -1))
               (check-equal? (ascent-engine-session-copy-integer-relation! session 'reach target 1) count)
               (check-equal? (s64vector->list target)
                             (cons -1 (append (apply append list-rows) '(-1))))
               (s64vector-set! target 1 -2)
               (let ((independent ((.ref result 'rows-of) 'reach))
                     (first (caar list-rows)))
                 (check-equal? independent list-rows)
                 (set-car! (car list-rows) 'caller-mutated)
                 (set-cdr! list-rows [])
                 (check-equal? (caar independent) first)
                 (check-equal? (length independent) count)
                 (check-equal? ((.ref result 'rows-of) 'reach) independent)))
             (finally (gerbil-ascent-session-close! session)))))
       (let* ((limit (##greatest-fixnum))
              (descending (map (lambda (i) (list (- limit i) (- i))) (iota 40)))
              (chain (map (lambda (i) (list i (+ i 1))) (iota 40)))
              (nonuniform
               (map (lambda (i)
                      (list (if (< i 20) i (+ i 3))
                            (if (< (+ i 1) 20) (+ i 1) (+ i 4))))
                 (iota 40)))
              (second-chain
               (map (lambda (i) (list (+ 1000 (* 3 i)) (+ 1003 (* 3 i))))
                 (iota 40))))
         (list (list #f descending 40)
               (list #t chain 820)
               (list #t (reverse chain) 820)
               (list #t nonuniform 820)
               (list #t (append chain second-chain) 1640)))))

    (test-case "packed caller buffers preserve capture order without exposing backing cells"
      (let* ((rows (map (lambda (i) (list (- 11 i) (modulo i 7))) (iota 64)))
             (session (open-ordered-actor rows))
             (target (make-s64vector 130 -999))
             (expected (cons -999 (append (apply append rows) '(-999)))))
        (try
          (let (result (gerbil-ascent-session-run session))
            (check-equal?
             ((.ref result 'with-ordered-binary-fields)
              'reach (lambda (_count _visit copy!) (procedure? copy!)) #t) #t)
            (check-equal? (ascent-engine-relation-answer result 'reach #f values) rows)
            (check-equal? (ascent-engine-session-copy-integer-relation! session 'reach target 1) 64)
            (check-equal? (s64vector->list target) expected)
            (s64vector-set! target 1 65536)
            (let (checks 0)
              (parameterize ((current-ascent-execution-control
                               (lambda (_work _facts)
                                 (set! checks (+ checks 1))
                                 (when (= checks 5) (error "cancel packed buffer before commit")))))
                (check-equal?
                 (with-catch error-message
                   (lambda () (ascent-engine-session-copy-integer-relation! session 'reach target 1)))
                 "cancel packed buffer before commit"))
              (check-equal? (s64vector-ref target 1) 65536))
            (check-equal? (ascent-engine-session-copy-integer-relation! session 'reach target 1) 64)
            (check-equal? (s64vector->list target) expected))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "caller buffer copies one ordered publication during a reentrant update"
      (let* ((before (ordered-rows 17)) (after (ordered-rows -31))
             (session (open-ordered-actor before))
             (destination (make-s64vector 4098 -999))
             (next #f) (checks 0))
        (try
          (begin
            (check-equal? (ascent-engine-session-copy-integer-relation! session 'reach destination 1) #f)
            (check-equal? destination (make-s64vector 4098 -999))
            (let (first (gerbil-ascent-session-run session))
              (gerbil-ascent-session-replace-source! session 'edge after)
              (parameterize
                ((current-ascent-execution-control
                  (lambda (_work _facts)
                    (set! checks (+ checks 1))
                    (when (= checks 4)
                      (parameterize ((current-ascent-execution-control #f))
                        (set! next (gerbil-ascent-session-run session)))))))
                (check-equal? (ascent-engine-session-copy-integer-relation!
                               session 'reach destination 1) 2048))
              (check-equal? (eq? next (gerbil-ascent-session-last-completed session)) #t)
              (check-equal? (s64vector->list destination) (cons -999 (append (apply append before) '(-999))))
              (check-equal? (ascent-engine-session-copy-integer-relation! session 'reach destination 1) 2048)
              (check-equal? (s64vector->list destination) (cons -999 (append (apply append after) '(-999))))
              ;; The destination can change without changing either Result.
              (s64vector-set! destination 1 99)
              (check-equal? (ascent-engine-relation-answer first 'reach #f values) before)
              (check-equal? (ascent-engine-relation-answer next 'reach #f values) after)))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "caller buffer stays intact on capacity refusal, cancellation and unsupported values"
      (let* ((session (open-ordered-actor (ordered-rows 17)))
             (destination (make-s64vector 4096 -999)))
        (try
          (let (first (gerbil-ascent-session-run session))
            (check-exception
             (ascent-engine-session-copy-integer-relation! session 'reach destination 1) true)
            (check-exception
             (ascent-engine-session-copy-integer-relation! session 'reach destination -1) true)
            (check-equal? destination (make-s64vector 4096 -999))
            (for-each
             (lambda (stop)
               (let (checks 0)
                 (parameterize ((current-ascent-execution-control
                                  (lambda (_work _facts)
                                    (set! checks (+ checks 1))
                                    (when (= checks stop) (error "interrupt buffer delivery")))))
                   (check-equal?
                    (with-catch error-message
                      (lambda () (ascent-engine-session-copy-integer-relation! session 'reach destination)))
                    "interrupt buffer delivery"))
                 (check-equal? destination (make-s64vector 4096 -999))
                 (check-equal? (eq? first (gerbil-ascent-session-last-completed session)) #t)))
             '(1 4 6))
            (gerbil-ascent-session-replace-source! session 'edge '((label 1)))
            (let (last (gerbil-ascent-session-run session))
              (check-equal? (ascent-engine-session-copy-integer-relation! session 'reach destination) #f)
              (check-equal? destination (make-s64vector 4096 -999))
              (check-equal? (ascent-engine-relation-answer last 'reach #f values) '((label 1)))))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "a different complete exporter takes precedence over the old field order"
      (let* ((emit (lambda (_columns _key consume) (consume [] 1 2) (consume [] 3 4)))
             (export (lambda () (list (list 1 2) (list 3 4))))
             (original (make-relation-view #f #f 0 'total 2 2 void void export
                         (make-packed-binary-visitors emit emit export
                           (lambda (destination start)
                             (s64vector-copy! destination start '#s64(1 2 3 4))))))
             (reordered (gerbil-ascent-view-with-export original
                          (lambda () (list (list 3 4) (list 1 2))))))
        (def (packet view)
          (let (result (gerbil-ascent-make-published-result '#(reach) '#(2) (vector view) '#(2)
                         [] '#(fixture () 0 #f) (lambda (_) 0) #t #t))
            (ascent-engine-relation-answer result 'reach #t values)))
        (check-equal? (s64vector->list (packet original)) '(2 2 1 2 3 4))
        (check-equal? (s64vector->list (packet reordered)) '(2 2 3 4 1 2))
        (check-equal? (procedure? (gerbil-ascent-ordered-binary-copy! original)) #t)
        (check-equal? (gerbil-ascent-ordered-binary-copy! reordered) #f)
        (for-each
         (lambda (count)
           (let (broken (make-relation-view #f #f 0 'total count count void void export
                           (make-ordered-binary-visitors emit emit export)))
             (check-exception (packet broken) true)))
         '(1 3))))
    (test-case "ordered binary replies preserve descending order and the previous generation's bytes"
      (let ((handle (open-ordered-projection)) (before (ordered-rows 7)) (after (ordered-rows -5)))
        (try
          (begin
            (source-run handle 1000000000)
            (replace-edges! handle before)
            (let* ((first (source-run handle 0 #t)) (packet (rows first "reach"))
                   (expected (append '(2048 2) (apply append before)))
                   (checks 0))
              (check-equal? (hash-ref first "executionRuntime") "actor")
              (check-equal? (s64vector->list packet) expected)
              (check-equal? (rows (source-run handle 0) "reach") before)
              (parameterize ((current-ascent-execution-control
                              (lambda (work _facts)
                                (when (= work 0) (set! checks (+ checks 1)))
                                (when (= checks 4) (error "cancel during ordered packet")))))
                (check-equal?
                 (with-catch error-message (lambda () (source-run handle 0 #t)))
                 "cancel during ordered packet"))
              (check-equal? checks 4)
              (check-exception (replace-edges! handle (cons '(2048 4096) before)) true)
              (let (unchanged (source-run handle 0 #t))
                (check-equal? (hash-ref unchanged "runIndex") (+ 2 (hash-ref first "runIndex")))
                (check-equal? (hash-ref unchanged "sourceGeneration") (hash-ref first "sourceGeneration")))
              (set! checks 0)
              (parameterize ((current-ascent-execution-control
                              (lambda (work _facts)
                                (when (= work 0)
                                  (set! checks (+ checks 1))
                                  (when (= checks 4)
                                    (parameterize ((current-ascent-execution-control #f))
                                      (replace-edges! handle after)))))))
                (check-equal?
                 (with-catch error-message (lambda () (source-run handle 0 #t)))
                 "ASCENT source changed during result delivery"))
              (let (next (source-run handle 0 #t))
                (check-equal? (hash-ref next "sourceGeneration") (+ 1 (hash-ref first "sourceGeneration")))
                (check-equal? (s64vector->list (rows next "reach")) (append '(2048 2) (apply append after)))
                (check-equal? (s64vector->list packet) expected))))
          (finally
            (ascent-engine-call (hash ("operation" "close") ("handle" handle)))))))
    (test-case "input projection does not require a completed Actor result"
      (let (handle (open-reachability '((0 1) (1 2) (2 3)) 16))
        (try
          (begin
            (check-source-projection handle #t)
            (let (partial (source-run handle 0 #t))
              (check-equal? (hash-ref partial "executionRuntime") "actor")
              (check-equal? (hash-ref partial "complete") #f)
              (check-exception (proof-scope handle partial) true))
            (check-source-projection handle #t))
          (finally
            (ascent-engine-call (hash ("operation" "close") ("handle" handle)))))))
    (test-case "projected source packets preserve complete catalogues and source generations"
      (let (handle (open-reachability [] 16))
        (try
          (begin
            ;; In the existing closure DSL, nonempty declarations are fixed
            ;; facts. Use its mutable empty source, then publish the first cut.
            (source-run handle 1000000000)
            (replace-edges! handle
              '((-9223372036854775808 0) (-9223372036854775808 0)
                (0 9223372036854775807)))
            (check-source-projection handle #t)
            (let (initial (source-run handle 1000000000))
              (for-each
                (lambda (point)
                  (replace-edges! handle (car point))
                  (check-source-projection handle (cadr point)))
                '((((0 9223372036854775808)) #f)
                  (((#f 7)) #f)
                  (() #f)
                  (((2 3) (2 3)) #t)))
              (check-exception (replace-edges! handle '((#(1) #(2)))) true)
              (check-source-projection handle #t)
              (check-exception (proof-scope handle initial) true)))
          (finally
            (ascent-engine-call (hash ("operation" "close") ("handle" handle)))))))
    (test-case "complex projected values retain their complete shared value pool"
      (let* ((source "(def (make) (gerbil-ascent-program (list (gerbil-ascent-relation 'edge 2 '((#(1) #(2)) (#(1) #(2))))) [] 32 64 96 '(edge)))")
             (opened (ascent-engine-call
                       (hash ("operation" "open-program") ("source" source)
                             ("constructor" "make") ("arguments" []) ("trusted" #t))))
             (handle (hash-ref opened "handle")))
        (try
          (check-source-projection handle #f)
          (finally
            (ascent-engine-call (hash ("operation" "close") ("handle" handle)))))))
    (test-case "private integer inputs preserve source updates and rejection precedence"
      (let (handle (open-reachability [] 4))
        (dynamic-wind
          void
          (lambda ()
            (let (initial (source-run handle 1000000000))
              (check-equal? (hash-ref initial "executionRuntime") "actor")
              (check-exception
               (replace-edges! handle '#s64(1 2 0 1)) true)
              (check-equal?
               (with-catch error-message
                 (lambda () (replace-edges! handle '#s64(33 3) #t)))
               "ASCENT source fact budget exceeded")
              (check-equal?
               (with-catch error-message
                 (lambda () (replace-edges! handle '#s64(2 1 1 2) #t)))
               "scheme row arity")
              (check-equal?
               (with-catch error-message
                 (lambda () (replace-edges! handle '#s64(2 2 0 1 2) #t)))
               "invalid native source row packet")
              (check-equal? (hash-ref (proof-scope handle initial) "sourceGeneration") 0)
              (check-equal?
               (hash-ref (replace-edges! handle '#s64(3 2 2 3 1 2 1 2) #t)
                         "sourceGeneration")
               1)
              (check-equal? (same? (rows (source-run handle 1000000000) "reach")
                                   '((2 3) (1 2) (1 3))) #t)
              (check-exception (proof-scope handle initial) true)))
          (lambda ()
            (ascent-engine-call (hash ("operation" "close") ("handle" handle)))))))
    (test-case "complete Actor integer rows preserve order and signed bounds"
      (let (handle (open-reachability [] 4))
        (try
          (begin
            (check-equal? (rows (source-run handle 1000000000 #t) "reach") [])
            (replace-edges! handle '((-9223372036854775808 0) (0 9223372036854775807)))
            (let* ((ordinary (rows (source-run handle 1000000000) "reach"))
                   (packed (source-run handle 1000000000 #t))
                   (packet (rows packed "reach")))
              (check-equal? (s64vector? packet) #t)
              (check-equal? (s64vector->list packet)
                            (append (list (length ordinary) 2) (apply append ordinary)))
              (check-equal? (hash-ref packed "scalarProjection") "supported")
              (check-equal? (hash-ref (proof-scope handle packed) "sourceGeneration") 1))
            (replace-edges! handle '((0 9223372036854775808)))
            (check-equal? (rows (source-run handle 1000000000 #t) "reach")
                          '((0 9223372036854775808)))
            (replace-edges! handle '((#f 7)))
            (check-equal? (rows (source-run handle 1000000000 #t) "reach") '((#f 7))))
          (finally
           (ascent-engine-call (hash ("operation" "close") ("handle" handle)))))))
    (test-case "ordinary typed DSL keeps its executor and uses lossless integer packets"
      (let* ((handle (open-typed-reachability []))
             (used-worker? #f))
        (try
          (parameterize
              ((current-ascent-execution-control
                (lambda (_work _facts)
                  (when (eq? (thread-name (current-thread)) 'ascent-session-evaluation)
                    (set! used-worker? #t)))))
            (check-equal? (rows (source-run handle 1000000000 #t) "reach") [])
            (replace-edges! handle '((-9223372036854775808 0) (0 9223372036854775807)))
            (let* ((ordinary (source-run handle 1000000000))
                   (packed (source-run handle 1000000000 #t))
                   (packet (rows packed "reach")))
              (check-equal? (s64vector? packet) #t)
              (check-equal? (s64vector->list packet)
                            (append (list (length (rows ordinary "reach")) 2)
                                    (apply append (rows ordinary "reach"))))
              (check-equal? (hash-ref packed "complete") #t)
              (check-equal? (hash-ref packed "executionRuntime") "session")
              (check-equal? (hash-ref packed "sourceGeneration") 1)
              (check-equal? (hash-ref packed "scalarProjection") "supported")
              (check-equal? (hash-ref (proof-scope handle packed) "sourceGeneration") 1)
              (replace-edges! handle '((0 9223372036854775808)))
              (check-equal? (rows (source-run handle 1000000000 #t) "reach")
                            '((0 9223372036854775808)))
              (check-exception (proof-scope handle packed) true))
            (check-exception (replace-edges! handle '((#f 7))) true)
            (check-equal? (rows (source-run handle 1000000000 #t) "reach")
                          '((0 9223372036854775808)))
            (replace-edges! handle '((0 1) (1 2) (2 3) (3 4)))
            ;; Eager replacement already accepted this cut. A zero-deadline
            ;; query may return its completed result without further evaluation.
            (let (complete (source-run handle 0 #t))
              (check-equal? (hash-ref complete "complete") #t)
              (check-equal? (hash-ref (proof-scope handle complete) "sourceGeneration") 3))
            (check-equal? used-worker? #f))
          (finally
           (ascent-engine-call (hash ("operation" "close") ("handle" handle)))))))
    (test-case "ordinary packed replies cannot promote an initially incomplete cut"
      (let (handle (open-typed-reachability '((0 1) (1 2) (2 3) (3 4))))
        (try
          (let (partial (source-run handle 0 #t))
            (check-equal? (hash-ref partial "complete") #f)
            (check-exception (proof-scope handle partial) true))
          (finally
           (ascent-engine-call (hash ("operation" "close") ("handle" handle)))))))
    (test-case "typed source-run resumes a resident Actor and confines partial proof scope"
      (let ((handle (open-reachability '((0 1) (1 2) (2 3) (3 4)) 32))
            (used-worker? #f))
        (try
          (let (partial
                 (parameterize
                     ((current-ascent-execution-control
                       (lambda (_work _facts)
                         (when (eq? (thread-name (current-thread)) 'ascent-session-evaluation)
                           (set! used-worker? #t)))))
                   (source-run handle 0 #t)))
            (check-equal? used-worker? #t)
            (check-equal? (hash-ref partial "executionRuntime") "actor")
            (check-equal? (hash-ref partial "complete") #f)
            (check-equal? (list? (rows partial "reach")) #t)
            (check-exception (proof-scope handle partial) true)
            (let (complete (source-run handle 1000000000))
              (check-equal? (hash-ref complete "complete") #t)
              (check-equal? (length (rows complete "reach")) 10)
              (check-equal? (hash-ref (proof-scope handle complete) "sourceGeneration") 0)
              (check-exception (proof-scope handle partial) true)
              (check-equal? (hash-ref (source-run handle 0) "nativeResultReused") #t)))
          (finally
           (ascent-engine-call (hash ("operation" "close") ("handle" handle)))))
        (check-exception (source-run handle 0) true)))
    (test-case "typed Actor replacement publishes complete cuts and revokes only older scopes"
      (let ((handle (open-reachability [] 3)) (used-worker? #f))
        (try
          (let (initial (source-run handle 1000000000))
            (parameterize
                ((current-ascent-execution-control
                  (lambda (_work _facts)
                    (when (eq? (thread-name (current-thread)) 'ascent-session-evaluation)
                      (set! used-worker? #t)))))
              (check-equal? (hash-ref (replace-edges! handle '((0 1) (1 2))) "sourceGeneration") 1))
            (check-equal? used-worker? #t)
            (check-exception (proof-scope handle initial) true)
            (let (complete (source-run handle 0))
              (check-equal? (hash-ref complete "complete") #t)
              (check-equal? (same? (rows complete "reach") '((0 1) (1 2) (0 2))) #t)
              (check-exception (replace-edges! handle '((0 1) (1 2) (2 3))) true)
              (check-equal? (hash-ref (proof-scope handle complete) "sourceGeneration") 1)))
          (finally
           (ascent-engine-call (hash ("operation" "close") ("handle" handle)))))))
    (test-case "retained recursion negation replacement and detached answers"
      (let* ((handle (hash-ref (request (hash ("operation" "open") ("program" (program)))) "handle"))
             (first (run handle)))
        (check-equal? (hash-ref first "complete") #t)
        (check-equal? (same? (rows first "path") '(("a" "b") ("b" "c") ("a" "c"))) #t)
        (check-equal? (rows first "safe") '(("a" "b")))
        (request (hash ("operation" "replace") ("handle" handle)
                       ("sources" (list (hash ("relation" "edge") ("rows" '(("c" "d"))))))))
        (check-equal? (rows (run handle) "path") '(("c" "d")))
        (check-equal? (same? (rows first "path") '(("a" "b") ("b" "c") ("a" "c"))) #t)
        (request (hash ("operation" "close") ("handle" handle)))
        (check-exception (run handle) true)))
    (test-case "invalid typed transaction and derived update leave current facts intact"
      (let* ((handle (hash-ref (request (hash ("operation" "open") ("program" (program)))) "handle"))
             (before (rows (run handle) "path")))
        (check-exception (request (hash ("operation" "replace") ("handle" handle)
          ("sources" (list (hash ("relation" "edge") ("rows" '(("x" "y"))))
                           (hash ("relation" "blocked") ("rows" '((42)))))))) true)
        (check-equal? (same? (rows (run handle) "path") before) #t)
        (check-exception (request (hash ("operation" "replace") ("handle" handle)
          ("sources" (list (hash ("relation" "path") ("rows" [])))))) true)
        (check-equal? (same? (rows (run handle) "path") before) #t)
        (request (hash ("operation" "close") ("handle" handle)))))
    (test-case "zero deadline is incomplete and arbitrary executable syntax rejects"
      (let (handle (hash-ref (request (hash ("operation" "open") ("program" (program)))) "handle"))
        (check-equal? (hash-ref (run handle 0) "complete") #f)
        (check-equal? (hash-ref (run handle) "complete") #t)
        (request (hash ("operation" "close") ("handle" handle))))
      (check-exception (ascent-engine-dispatch "(begin (display 42))") true)
      (check-exception (ascent-engine-dispatch "{\"operation\":\"describe\"} {}") true)
      (check-exception (request (hash ("operation" "describe") ("eval" "42"))) true))))
