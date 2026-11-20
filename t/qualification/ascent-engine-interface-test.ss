;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/encoding/json :gerbil-ascent/interface/engine-api
        (only-in :gerbil-ascent/core/execution-control current-ascent-execution-control))
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

(def ascent-engine-interface-test
  (test-suite "Public inert engine contract for C ABI consumers"
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
