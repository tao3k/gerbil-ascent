;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object :gerbil-ascent/program/objects
        :gerbil-ascent/t/performance/view-lattice-round/fixture
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine)
        (prefix-in :gerbil-ascent/t/performance/view-lattice-round/reference-evaluate old-)
        (only-in :gerbil-ascent/table/interface gerbil-ascent-hash-index-provider
                 gerbil-ascent-eqrel-storage-provider gerbil-ascent-trrel-uf-storage-provider))
(export ascent-view-lattice-round-test)
(def (run engine) ((.ref engine '.run)))
(def (rows result name) ((.ref result 'rows-of) name))
(def ascent-view-lattice-round-test
  (test-suite "Native view and lattice round ownership"
    (test-case "eight complete engines match independent closure truth"
      (for-each (lambda (scenario)
                  (let ((old (vl-prepare #t scenario)) (new (vl-prepare #f scenario)))
                    (check-equal? (vl-consume old scenario #t) (vl-expected old scenario))
                    (check-equal? (vl-consume new scenario #f) (vl-expected new scenario))))
                '(view lattice mixed cold small set dense custom)))
    (test-case "every committed view and lattice timeout cut matches frozen ownership"
      (for-each
       (lambda (scenario)
         (let* ((program (vl-program scenario))
                (old (old-gerbil-ascent-make-engine program #t))
                (new (gerbil-ascent-make-engine program #t))
                (first ((.ref new '.run-timeout) 0)) (saved (vl-project first)))
           (check-equal? saved (vl-project ((.ref old '.run-timeout) 0)))
           (for-each (lambda (_)
                       (check-equal? (vl-project ((.ref new '.run-timeout) 0))
                                     (vl-project ((.ref old '.run-timeout) 0)))) (iota 4))
           (check-equal? (vl-project (run new)) (vl-project (run old)))
           (check-equal? (vl-project first) saved)
           (check-equal? (eq? (run new) (run new)) #t))) '(view lattice mixed)))
    (test-case "no-op EqRel and UF emissions admit touched owners before clean reuse"
      (for-each
       (lambda (provider)
         (let* ((x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y))
                (atom (gerbil-ascent-atom 'view (list x y)))
                (program (gerbil-ascent-program
                           (list (gerbil-ascent-relation 'view 2 '((0 1)) gerbil-ascent-hash-index-provider provider)
                                 (gerbil-ascent-relation 'unused 2 []))
                           (list (gerbil-ascent-rule (list atom) (list atom))) 10 20 30))
                (new (gerbil-ascent-make-engine program #t))
                (old (old-gerbil-ascent-make-engine program #t))
                (result (run new)))
           (check-equal? (vl-project result) (vl-project (run old)))
           (check-equal? (eq? result (run new)) #t)
           ((.ref new '.append-source!) 'view '(1 2))
           ((.ref old '.append-source!) 'view '(1 2))
           (check-equal? (vl-project (run new)) (vl-project (run old)))
           (check-equal? (eq? (run new) (run new)) #t)))
       (list gerbil-ascent-eqrel-storage-provider gerbil-ascent-trrel-uf-storage-provider)))
    (test-case "failed view field admission requires source replay and preserves old cut"
      (let ((reject? #f) (x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y)))
        (let* ((program (gerbil-ascent-program
                         (list (gerbil-ascent-relation 'source 2 '((0 1)))
                               (gerbil-ascent-relation 'view 2 [] gerbil-ascent-hash-index-provider
                                 gerbil-ascent-eqrel-storage-provider
                                 (list (lambda (v) (when (and reject? (= v 2)) (error "rejected")) #t) integer?)))
                         (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'view (list x y)))
                                                  (list (gerbil-ascent-atom 'source (list x y))))) 10 30 40))
               (new (gerbil-ascent-make-engine program #t))
               (old (old-gerbil-ascent-make-engine program #t))
               (first (run new)) (saved (vl-project first)))
          (run old)
          (for-each (lambda (engine) ((.ref engine '.append-source!) 'source '(1 2))) (list new old))
          (set! reject? #t)
          (check-exception (run new) true)
          (check-exception (run old) true)
          (check-exception (run new) true)
          (check-equal? (vl-project first) saved)
          (set! reject? #f)
          (for-each (lambda (engine) ((.ref engine '.replace-source!) 'source '((0 1) (1 2)))) (list new old))
          (check-equal? (vl-project (run new))
                        (vl-project (run old))))))
    (test-case "lattice key revisits keep join order and effective membership"
      (def (observe maker)
        (let ((trace []) (k (gerbil-ascent-variable 'k)) (v (gerbil-ascent-variable 'v)))
          (let* ((program (gerbil-ascent-program
                           (list (gerbil-ascent-relation 'input 2 '((0 9) (1 8) (0 7) (1 6) (0 5)))
                                 (gerbil-ascent-lattice 'score 2 '((0 20) (1 20))
                                   (lambda (a b) (set! trace (cons (list a b) trace)) (min a b)))
                                 (gerbil-ascent-relation 'unused 2 []))
                           (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'score (list k v)))
                                                    (list (gerbil-ascent-atom 'input (list k v))))) 10 30 40))
                 (result ((maker program #f))))
            (list (vl-project result) (reverse trace)))))
      (check-equal? (observe gerbil-ascent-make-engine) (observe old-gerbil-ascent-make-engine)))))
