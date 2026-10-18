;;; Cached and cold ancestry stay equivalent to the frozen 099b381 algorithm.
(import :std/test
        (only-in :gerbil/runtime/gambit type-exception?)
        (only-in ../object make-object object-supers-set!
                 object-%precedence-list compute-precedence-list!
                 .o .mix .ref .putslot! uninstantiate-object!)
        (only-in ../object $constant-slot-spec)
        (only-in ./precedence-cache-reference-fixture precedence-reference!))
(export precedence-cache-test)

(def (graph mask)
  (let (nodes (list->vector (map (lambda (_) (make-object)) (iota 3))))
    (for-each
     (lambda (from)
       (object-supers-set!
        (vector-ref nodes from)
        (filter-map
         (lambda (to)
           (and (not (zero? (bitwise-and mask (arithmetic-shift 1 (+ (* from 3) to)))))
                (vector-ref nodes to)))
         (iota 3))))
     (iota 3))
    nodes))

(def (outcome compute nodes root)
  (with-catch (lambda (failure) (list 'error (error-message failure)))
    (lambda ()
      (list 'precedence
            (map (lambda (node)
                   (let find ((index 0))
                     (if (eq? node (vector-ref nodes index))
                       index (find (+ index 1)))))
                 (compute (vector-ref nodes root)))))))

(def precedence-cache-test
  (test-suite "precedence list cache admission"
    (test-case "all three-node graphs preserve cold linearization and errors"
      (for-each
       (lambda (mask)
         (for-each
          (lambda (root)
            (check-equal? (outcome precedence-reference! (graph mask) root)
                          (outcome compute-precedence-list! (graph mask) root)))
          (iota 3))
         (when (zero? (modulo (+ mask 1) 32))
           (displayln "PRECEDENCE-PARITY " (+ mask 1) "/512 roots=3")
           (force-output)))
       (iota 512)))
    (test-case "cached list identity and heads precedence are preserved"
      (let* ((root (.o)) (left (.o (:: @ root))) (right (.o (:: @ root)))
             (diamond (.mix left right))
             (cached (precedence-reference! diamond)))
        (check-equal? cached (list diamond left right root))
        (check-equal? (eq? cached (compute-precedence-list! diamond)) #t)
        ;; The original cached branch also precedes the supplied heads guard.
        (check-equal? (eq? cached (compute-precedence-list! diamond (list diamond))) #t)
        (check-equal? (eq? cached (precedence-reference! diamond (list diamond))) #t)))
    (test-case "malformed heads retain their existing cache-hit behavior"
      (let* ((root (.o)) (cached (compute-precedence-list! root)))
        (def (failure compute heads)
          (with-catch
           (lambda (exception)
             (if (type-exception? exception)
               '(type-error)
               (list 'error (error-message exception))))
           (lambda () (compute root heads) 'accepted)))
        (for-each
         (lambda (heads)
           (let ((old (failure precedence-reference! heads))
                 (new (failure compute-precedence-list! heads)))
             (check-equal? old new)))
         (list #f 1 "heads" (cons root 1)))))
    (test-case "slot invalidation recomputes ancestry without changing lookup"
      (let* ((root (.o (value 1))) (child (.o (:: @ root))))
        (check-equal? (.ref child 'value) 1)
        (check-equal? (eq? (compute-precedence-list! child)
                          (object-%precedence-list child)) #t)
        (.putslot! child 'value ($constant-slot-spec 2))
        ;; .putslot! edits the specification; already cached values retain
        ;; their existing lifetime until explicit uninstantiation.
        (check-equal? (.ref child 'value) 1)
        (uninstantiate-object! child)
        (check-equal? (object-%precedence-list child) #f)
        (check-equal? (compute-precedence-list! child) (list child root))
        (check-equal? (.ref child 'value) 2)))))
