;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object :gerbil-ascent/program/objects
        :gerbil-ascent/t/performance/engine-publication/fixture
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine)
        (prefix-in :gerbil-ascent/t/performance/engine-publication/reference old-)
        (only-in :gerbil-ascent/program/result gerbil-ascent-publication-reader))
(export ascent-execution-publication-test)
(def (simple-program)
  (gerbil-ascent-program (list (gerbil-ascent-relation 'reach 1 '((0)))) [] 128 128 128))
(def ascent-execution-publication-test
  (test-suite "Execution-owned publication cut"
    (test-case "complete consumers match frozen execution and independent truth"
      (for-each (lambda (scenario)
                  (let ((old (publication-prepare #t scenario)) (new (publication-prepare #f scenario)))
                    (check-equal? (publication-consume old scenario #t) (publication-expected old scenario))
                    (check-equal? (publication-consume new scenario #f) (publication-expected new scenario))))
                '(wide dirty duplicate cold small fresh)))
    (test-case "changed wrappers detach public metadata while private cuts stay owned"
      (let* ((engine (gerbil-ascent-make-engine (simple-program) #t))
             (first ((.ref engine '.run)))
             (native ((.ref engine '.native-publication)))
             (sizes ((.ref first 'relation-sizes)))
             (representations ((.ref first 'representation-observation))))
        (set-car! (.ref first 'relation-names) 'forged)
        (set-cdr! (car sizes) 99)
        (set-car! (car representations) 'forged)
        ((.ref engine '.append-source!) 'reach '(1))
        (let (next ((.ref engine '.run)))
          (check-equal? (eq? first next) #f)
          (check-equal? (.ref next 'relation-names) '(reach))
          (check-equal? ((.ref next 'relation-sizes)) '((reach . 2)))
          (check-equal? (caar ((.ref next 'representation-observation))) 'reach)
          (check-equal? ((gerbil-ascent-publication-reader native first) 'reach) '((0)))
          (check-equal? (gerbil-ascent-publication-reader ((.ref engine '.native-publication)) first) #f))))
    (test-case "dirty execution replaces the cut without changing held snapshots"
      (let* ((engine (gerbil-ascent-make-engine (simple-program) #t))
             (first ((.ref engine '.run))))
        ((.ref engine '.append-source!) 'reach '(1))
        (let (next ((.ref engine '.run)))
          (check-equal? ((.ref first 'rows-of) 'reach) '((0)))
          (check-equal? ((.ref next 'rows-of) 'reach) '((0) (1)))
          (check-equal? (publication-project ((.ref engine '.run))) (publication-project next)))))
    (test-case "partial timeout resumes publish a new cut then stable complete cuts"
      (let* ((old (publication-prepare #t 'small)) (new (publication-prepare #f 'small))
             (program (vector-ref new 0))
             (left (old-gerbil-ascent-make-engine program #t))
             (right (gerbil-ascent-make-engine program #t))
             (old-partial ((.ref left '.run-timeout) 0))
             (new-partial ((.ref right '.run-timeout) 0)))
        (check-equal? (publication-project old-partial) (publication-project new-partial))
        (check-equal? (.ref new-partial 'finished) #f)
        (check-equal? (publication-project ((.ref right '.run))) (publication-project ((.ref left '.run))))))
    (test-case "clean calls retain baseline result identity"
      (let* ((engine (gerbil-ascent-make-engine (simple-program) #t))
             (first ((.ref engine '.run))))
        (check-equal? (eq? first ((.ref engine '.run))) #t)))
    (test-case "unchanged private representation entries resist public mutation"
      (let* ((state (publication-prepare #f 'wide))
             (engine (vector-ref state 1))
             (first ((.ref engine '.run)))
             (metadata ((.ref first 'representation-observation))))
        (set-car! (car metadata) 'forged)
        (publication-consume state 'wide #f)
        (check-equal? (car ((.ref ((.ref engine '.run)) 'representation-observation)))
                      '(edge explicit 16 16))))))
