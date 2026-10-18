;;; Empty-frontier pruning must preserve observable engine behavior.
(import (only-in :std/test test-suite check-equal? test-case)
        (only-in :clan/poo/object .ref .o)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-rule gerbil-ascent-program
                 gerbil-ascent-guard gerbil-ascent-generator
                 gerbil-ascent-lattice gerbil-ascent-expression)
        (only-in :gerbil-ascent/program/evaluate
                 gerbil-ascent-evaluate-program gerbil-ascent-make-engine)
        (only-in :gerbil-ascent/t/qualification/ascent-set-size-reference-evaluate
                 ascent-set-size-reference-evaluate-program ascent-set-size-reference-make-engine))
(import (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider))
(import (only-in :gerbil-ascent/table/storage gerbil-ascent-set-storage-provider))
(export ascent-set-size-test)

(def (program edges seeds (provider #f))
  (let ((x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y)))
    (gerbil-ascent-program
     (list (if provider (gerbil-ascent-relation 'edge 2 edges provider)
                (gerbil-ascent-relation 'edge 2 edges))
           (gerbil-ascent-relation 'reach 1 seeds))
     (list (gerbil-ascent-rule
            (list (gerbil-ascent-atom 'reach (list y)))
            (list (gerbil-ascent-atom 'reach (list x))
                  (gerbil-ascent-atom 'edge (list x y)))))
     256 256 512)))

(def (rows result name) ((.ref result 'rows-of) name))
(def (same old new)
  (check-equal? (.ref old 'finished) (.ref new 'finished))
  (check-equal? ((.ref old 'relation-sizes)) ((.ref new 'relation-sizes)))
  (for-each (lambda (name) (check-equal? (rows old name) (rows new name)))
            '(edge reach)))
(def (chain width)
  (map (lambda (n) (list n (+ n 1))) (iota width)))

(def (multi-program edges gates provider indexed-prefix?)
  (let ((x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y))
        (g (gerbil-ascent-variable 'g)))
    (gerbil-ascent-program
     (list (gerbil-ascent-relation 'edge 2 edges provider)
           (gerbil-ascent-relation 'gate 1 gates)
           (gerbil-ascent-relation 'reach 1 '((0))))
     (list (gerbil-ascent-rule
            (list (gerbil-ascent-atom 'reach (list y)))
            (cons (gerbil-ascent-atom 'reach (list x))
                  (if indexed-prefix?
                    (list (gerbil-ascent-atom 'edge (list x y))
                          (gerbil-ascent-atom 'gate (list g)))
                    (list (gerbil-ascent-atom 'gate (list g))
                          (gerbil-ascent-atom 'edge (list x y)))))))
     256 256 512)))

(def ascent-set-size-test
  (test-suite "built-in Set cardinality maintenance"
    (test-case "custom storage expansion preserves callback observations and sizes"
      (let* ((calls [])
             (storage (.o (:: @ gerbil-ascent-set-storage-provider)
                        (.extend-rows
                         (lambda (_state all pending row budget)
                           (set! calls (cons (list (length all) (length pending)
                                                  row budget) calls))
                           (list row (list (+ (car row) 1000)))))))
             (x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y))
             (p (gerbil-ascent-program
                 (list (gerbil-ascent-relation 'edge 2 (chain 16))
                       (gerbil-ascent-relation 'reach 1 '((0))
                         gerbil-ascent-hash-index-provider storage))
                 (list (gerbil-ascent-rule
                        (list (gerbil-ascent-atom 'reach (list y)))
                        (list (gerbil-ascent-atom 'reach (list x))
                              (gerbil-ascent-atom 'edge (list x y)))))
                 64 64 128))
             (old (ascent-set-size-reference-evaluate-program p))
             (old-calls calls))
        (set! calls [])
        (let (new (gerbil-ascent-evaluate-program p))
          (same old new)
          (check-equal? calls old-calls)
          (check-equal? (length (rows new 'reach)) 34)
          (check-equal? (not (not (member '(1016) (rows new 'reach)))) #t))))
    (test-case "three-atom empty frontiers preserve exact fixed points"
      (for-each
       (lambda (width)
         (for-each
          (lambda (gates)
            (let* ((p (multi-program (chain width) gates
                        gerbil-ascent-hash-index-provider #f))
                   (old (ascent-set-size-reference-evaluate-program p))
                   (new (gerbil-ascent-evaluate-program p)))
              (same old new)
              (check-equal? (rows old 'gate) (rows new 'gate))
              (check-equal? (rows new 'reach)
                            (if (null? gates) '((0))
                              (map list (iota (+ width 1)))))))
          '(() ((0)) ((0) (1) (2) (3)))))
       '(0 1 8 32 64)))
    (test-case "indexed prefix callbacks remain observable before an empty third atom"
      (let* ((calls 0)
             (lookup (.ref gerbil-ascent-hash-index-provider '.lookup-index))
             (provider (.o (:: @ gerbil-ascent-hash-index-provider)
                         (.lookup-index (lambda (index key)
                                          (set! calls (+ calls 1))
                                          (lookup index key)))))
             (p (multi-program (chain 64) '((0)) provider #t))
             (old (ascent-set-size-reference-evaluate-program p))
             (old-calls calls))
        (set! calls 0)
        (let (new (gerbil-ascent-evaluate-program p))
          (same old new)
          (check-equal? calls old-calls)
          (check-equal? (> calls 65) #t))))
    (test-case "recursive chains retain exact row order and sizes"
      (for-each
       (lambda (width)
         (let* ((p (program (chain width) '((0) (0))))
                (old (ascent-set-size-reference-evaluate-program p))
                (new (gerbil-ascent-evaluate-program p)))
           (same old new)
           (check-equal? (rows new 'reach) (cons '(0) (map list (iota (+ width 1)))))))
       '(0 1 2 8 32 128)))
    (test-case "all two-node graphs retain independent reachability goldens"
      (for-each
       (lambda (mask)
         (let (edges (filter-map
                      (lambda (n) (and (not (zero? (bitwise-and mask (arithmetic-shift 1 n)))) (list (quotient n 2) (modulo n 2))))
                      (iota 4)))
           (for-each
            (lambda (root)
              (let* ((p (program edges (list (list root))))
                     (old (ascent-set-size-reference-evaluate-program p))
                     (new (gerbil-ascent-evaluate-program p))
                     (other (- 1 root)))
                (same old new)
                (check-equal? (length (rows new 'reach))
                              (if (member (list root other) edges) 2 1))))
            '(0 1))))
       (iota 16)))
    (test-case "session appends and replacements keep committed sizes"
      (let* ((p (program '((0 1)) '((0))))
             (old (ascent-set-size-reference-make-engine p #t))
             (new (gerbil-ascent-make-engine p #t)))
        (same ((.ref old '.run)) ((.ref new '.run)))
        (for-each
         (lambda (edge)
           ((.ref old '.append-source!) 'edge edge)
           ((.ref new '.append-source!) 'edge edge)
           (same ((.ref old '.run)) ((.ref new '.run))))
         '((1 2) (2 3) (1 2) (3 0)))
        ((.ref old '.replace-source!) 'edge '((0 4)))
        ((.ref new '.replace-source!) 'edge '((0 4)))
        (same ((.ref old '.run)) ((.ref new '.run)))))
    (test-case "custom index Provider callbacks retain their exact count"
      (let* ((calls 0) (builds 0)
             (lookup (.ref gerbil-ascent-hash-index-provider '.lookup-index))
             (build (.ref gerbil-ascent-hash-index-provider '.build-index))
             (provider (.o (:: @ gerbil-ascent-hash-index-provider)
                         (.lookup-index (lambda (index key)
                                          (set! calls (+ calls 1))
                                          (lookup index key)))
                         (.build-index (lambda (rows columns)
                                         (set! builds (+ builds 1))
                                         (build rows columns)))))
             (p (program (chain 64) '((0)) provider))
             (old (ascent-set-size-reference-evaluate-program p))
             (old-calls calls) (old-builds builds))
        (set! calls 0) (set! builds 0)
        (let (new (gerbil-ascent-evaluate-program p))
          (same old new)
          (check-equal? calls old-calls)
          (check-equal? builds old-builds)
          (check-equal? calls 65)
          (check-equal? builds 1))))
    (test-case "guard and generator prefix callback counts are unchanged"
      (for-each
       (lambda (kind)
         (let* ((calls 0)
                (x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y))
                (prefix (if (eq? kind 'guard)
                          (gerbil-ascent-guard [] (lambda () (set! calls (+ calls 1)) #t))
                          (gerbil-ascent-generator 'x []
                            (lambda () (set! calls (+ calls 1)) '(0)))))
                (body (if (eq? kind 'guard)
                        (list prefix (gerbil-ascent-atom 'reach (list x))
                              (gerbil-ascent-atom 'edge (list x y)))
                        (list prefix (gerbil-ascent-atom 'edge (list x y)))))
                (p (gerbil-ascent-program
                    (list (gerbil-ascent-relation 'edge 2 '((0 1) (1 2)))
                          (gerbil-ascent-relation 'reach 1 '((0))))
                    (list (gerbil-ascent-rule
                           (list (gerbil-ascent-atom 'reach (list y))) body))
                    16 16 32))
                (old (ascent-set-size-reference-evaluate-program p))
                (old-calls calls))
           (set! calls 0)
           (let (new (gerbil-ascent-evaluate-program p))
             (same old new)
             (check-equal? calls old-calls)
             (check-equal? (> calls 0) #t))))
       '(guard generator)))
    (test-case "lattice replacement keeps key cardinality and strongest rows"
      (let* ((x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y))
             (d (gerbil-ascent-variable 'd))
             (p (gerbil-ascent-program
                 (list (gerbil-ascent-relation 'edge 2 '((0 1) (1 2) (0 2)))
                       (gerbil-ascent-lattice 'best 2 '((0 0)) min))
                 (list (gerbil-ascent-rule
                        (list (gerbil-ascent-atom 'best
                                (list y (gerbil-ascent-expression '(d) (lambda (d) (+ d 1))))))
                        (list (gerbil-ascent-atom 'best (list x d))
                              (gerbil-ascent-atom 'edge (list x y)))))
                 16 16 32))
             (old (ascent-set-size-reference-evaluate-program p))
             (new (gerbil-ascent-evaluate-program p)))
        (check-equal? ((.ref old 'relation-sizes)) ((.ref new 'relation-sizes)))
        (check-equal? (rows old 'best) (rows new 'best))
        (check-equal? (list-sort (lambda (a b) (< (car a) (car b))) (rows new 'best))
                      '((0 0) (1 1) (2 1)))))
    (test-case "timeout resumption preserves the final fixed point"
      (let* ((p (program (chain 64) '((0))))
             (old (ascent-set-size-reference-make-engine p #t))
             (new (gerbil-ascent-make-engine p #t)))
        ;; Independent engines may complete different prefixes at the deadline.
        ((.ref old '.run-timeout) 0)
        ((.ref new '.run-timeout) 0)
        (same ((.ref old '.run)) ((.ref new '.run)))))))
