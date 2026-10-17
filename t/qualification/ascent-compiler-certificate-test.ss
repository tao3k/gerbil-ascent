;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        :gerbil-ascent/core/positive-plan
        :gerbil-ascent/core/positive-certificate
        :gerbil-ascent/core/descriptor-stream
        :gerbil-ascent/core/index-publication
        :gerbil-ascent/core/actor-envelope
        :gerbil-ascent/core/scc-state
        :gerbil-ascent/core/dependency-graph
        :gerbil-ascent/core/execution-policy
        :gerbil-ascent/program/actor-round
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
    (test-case "generated decoder preserves slot zero, constructor tags and wildcard payloads"
      (let (slots (make-hash-table-eq))
        (check-equal? (gerbil-ascent-certificate-terms! [] [] slots 0 #f) 0)
        (check-equal? (gerbil-ascent-certificate-terms! '((variable . x)) '((fresh . 0)) slots 0 #f) 1)
        (check-equal? (gerbil-ascent-certificate-terms! '((variable . x)) '((bound . 0)) slots 1 #t) 1)
        (for-each (lambda (action)
          (check-equal? (gerbil-ascent-certificate-terms! '((variable . x)) (list action) slots 1 #f) #f))
          '((fresh . 0) (bound . 0.0) (bound . -1) (bound . 1) (literal . 0) malformed))
        (check-equal? (gerbil-ascent-certificate-terms! '((variable . y)) '((fresh . 1)) slots 1 #t) #f)
        (check-equal? (hash-get slots 'y) #f)
        (check-equal? (gerbil-ascent-certificate-terms! '((wildcard . token)) '((wildcard . token)) slots 1 #f) 1)
        (check-equal? (gerbil-ascent-certificate-terms! '((wildcard . token)) '((wildcard . other)) slots 1 #f) #f)
        (check-equal? (gerbil-ascent-certificate-terms! '((variable . x)) '((bound . 0) . broken) slots 1 #f) #f)))
    (test-case "cache source macros preserve order, hygiene and exact provider failures"
      (let ((entry (vector 3 'old 'members)) (events []) (failure (vector 'provider-failure))
            (owner 'outer-owner) (built 'outer-built) (members 'outer-members))
        (def (lookup! item value) (set! events (cons 'lookup events)) (vector-set! item 1 value))
        (def (witness! item value) (set! events (cons 'witness events)) (vector-set! item 2 value))
        (def (version! item value) (set! events (cons value events)) (vector-set! item 0 value))
        (check-equal? (gerbil-ascent-index-rebuild! entry 4
          (begin (set! events (cons members events)) 'new-members)
          (begin (set! events (cons built events)) 'new-lookup)
          lookup! witness! version!) 'new-lookup)
        (check-equal? (reverse events) '(outer-members outer-built lookup witness 4))
        (check-equal? owner 'outer-owner)
        (set! events [])
        (check-equal? (eq? (with-catch (lambda (caught) caught) (lambda ()
          (gerbil-ascent-index-rebuild! entry 5 'staged (raise failure) lookup! witness! version!))) failure) #t)
        (check-equal? events [])
        (check-equal? entry '#(4 new-lookup new-members))
        (check-equal? (eq? (with-catch (lambda (caught) caught) (lambda ()
          (gerbil-ascent-index-extend! entry (begin (error "must not publish"))
            (begin (vector-set! entry 1 'mutated) (raise failure))
            (error "must not extend witness") lookup! version!))) failure) #t)
        (check-equal? entry '#(#f mutated new-members))
        (check-equal? (reverse events) '(#f))
        (set! events [])
        (check-equal? (eq? (with-catch (lambda (caught) caught) (lambda ()
          (gerbil-ascent-index-extend! entry (error "must not publish") 'extended
            (begin (vector-set! entry 2 'changed-members) (raise failure)) lookup! version!))) failure) #t)
        (check-equal? entry '#(#f extended changed-members))
        (check-equal? (reverse events) '(#f lookup))))
    (test-case "Actor envelope preserves every field and payload identity"
      (let ((key (vector 'key)) (task (vector 'task)) (payload (vector 'stopped)))
        (gerbil-ascent-send-round! (current-thread) 'done key (current-thread) task payload)
        (gerbil-ascent-match-round! (thread-receive)
          ([kind received-key worker received-task received-payload]
            (begin (check-equal? kind 'done)
            (check-equal? (eq? key received-key) #t)
            (check-equal? (eq? worker (current-thread)) #t)
            (check-equal? (eq? task received-task) #t)
            (check-equal? (eq? payload received-payload) #t)))
          (else (error "valid envelope rejected")))
        (check-equal? (gerbil-ascent-match-round! '(done key worker task)
          ([_ _ _ _ _] 'accepted) (else 'malformed)) 'malformed)))
    (test-case "SCC discovery zero is on stack and each branch evaluates only once"
      (let ((observed []) (known 'outer-known))
        (check-equal? (gerbil-ascent-scc-state
          (begin (set! observed (cons 'read observed)) 0) (known)
          (error "zero must not be unseen") (error "zero must not be completed")
          (begin (set! observed (cons known observed)) 'active)) 'active)
        (check-equal? known 'outer-known)
        (check-equal? (reverse observed) '(read 0))
        (check-equal? (gerbil-ascent-scc-state #f (index) 'enter (error "completed") (error "active")) 'enter)
        (check-equal? (gerbil-ascent-scc-state #t (index) (error "unseen") 'stay (error "active")) 'stay)
        (check-equal? (gerbil-ascent-graph-components '#((1) (0 2) (3) (2))) '((0 1) (2 3)))))
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
    (test-case "terminal certification preserves the original failure after cleanup"
      (check-equal?
        (with-catch (lambda (failure) (error-message failure))
          (lambda ()
            (gerbil-ascent-run-actor-round! (vector 'blocked) '(a) 2
              (lambda (_ emit! checkpoint!) (error "should not dispatch"))
              (lambda (_ row) (void)) (lambda () #f) (lambda (_) #f))))
        "ASCENT ready task dependency deadlock")
      (check-equal?
        (with-catch (lambda (failure) (error-message failure))
          (lambda ()
            (gerbil-ascent-run-actor-round! (vector 'canceled) '(a) 2
              (lambda (_ emit! checkpoint!) (error "should not dispatch"))
              (lambda (_ row) (void)) (lambda () #t))))
        "ASCENT actor round canceled")
      (let (failure (vector 'completion-callback-failure))
        (check-equal? (eq?
          (with-catch (lambda (caught) caught)
            (lambda ()
              (gerbil-ascent-run-actor-round! (vector 'callback) '(a) 1
                (lambda (_ emit! checkpoint!) (emit! 'r '(1)))
                (lambda (_ row) (void)) (lambda () #f) (lambda (_) #t)
                (lambda (_) (raise failure))))) failure) #t)))
    (test-case "shared control decisions keep failure distinct from completion"
      (check-equal? (gerbil-ascent-actor-complete #t #t) #f)
      (check-equal? (gerbil-ascent-actor-complete #f #f) #f)
      (check-equal? (gerbil-ascent-round-continue 10 #f) #f)
      (check-equal? (gerbil-ascent-readable-key 3 3 #f #t) #f)
      (check-equal? (gerbil-ascent-old-lane 0 1 #f #t) #f)
      (check-equal? (gerbil-ascent-old-lane 0 1 #t #f) #f))))
