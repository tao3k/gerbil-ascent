;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite)
        (only-in :clan/poo/object .o .mix .ref)
        (only-in :core/observability/testing-case
                 poo-flow-test-case)
        (only-in :gerbil-ascent/t/qualification/ascent-lattice-program-fixture
                 ascent-lattice-fixture-evaluate
                 ascent-recursive-lattice-projection-program)
        (only-in :gerbil-ascent/t/qualification/ascent-lattice-negation-fixture
                 ascent-lattice-negation-program)
        (only-in :gerbil-ascent/program/interface
                 ascent
                 gerbil-ascent-lattice gerbil-ascent-relation
                 gerbil-ascent-atom gerbil-ascent-variable gerbil-ascent-rule
                 gerbil-ascent-program gerbil-ascent-evaluate-program
                 gerbil-ascent-open-session
                 gerbil-ascent-session-run
                 gerbil-ascent-session-run-timeout
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-replace-source!))

(export ascent-lattice-program-test)

(def (shortest edges)
  ((.ref (ascent-lattice-fixture-evaluate edges) 'rows-of) 'shortest))

(def (mixed-program scores improvements)
  (ascent
   (lattice score ((node integer?) (value integer?)) scores min)
   (relation improve ((node integer?) (value integer?)) improvements)
   (lattice copy ((node integer?) (value integer?)) [] min)
   ((score node value) <-- (improve node value))
   ((copy node value) <-- (score node value))
   (bounds 8 16 24)))

(def ascent-lattice-program-test
  (test-suite "ASCENT lattice fixed point"
    (poo-flow-test-case "recursive shortest paths replace weaker key values"
      (let (rows (shortest '((1 2 3) (1 3 1) (3 2 1)
                             (2 4 1) (3 4 5))))
        (check-equal? (length rows) 6)
        (check-equal? (not (not (member '(1 2 2) rows))) #t)
        (check-equal? (not (not (member '(1 4 3) rows))) #t)
        (check-equal? (member '(1 4 6) rows) #f)))
    (poo-flow-test-case "ordinary projection waits for lattice fixed point"
      (let* ((result
              (gerbil-ascent-evaluate-program
               (ascent-recursive-lattice-projection-program)))
             (rows-of (.ref result 'rows-of)))
        (check-equal? (rows-of 'best) '((0 1)))
        (check-equal? (rows-of 'found) '((0 1)))))
    (poo-flow-test-case "timeout resumes across the lattice projection stratum"
      (let* ((session
              (gerbil-ascent-open-session
               (ascent-recursive-lattice-projection-program)))
             (first (gerbil-ascent-session-run-timeout session 0)))
        (check-equal? (.ref first 'finished) #f)
        (check-equal? ((.ref first 'rows-of) 'found) [])
        (let resume ((remaining 12) (result first))
          (if (.ref result 'finished)
            (begin
              (check-equal? ((.ref result 'rows-of) 'best) '((0 1)))
              (check-equal? ((.ref result 'rows-of) 'found) '((0 1))))
            (begin
              (check-equal? (> remaining 0) #t)
              (check-equal?
               (let (rows ((.ref result 'rows-of) 'found))
                 (or (null? rows) (equal? rows '((0 1)))))
               #t)
              (resume (- remaining 1)
                      (gerbil-ascent-session-run-timeout session 0)))))
        (check-equal? ((.ref first 'rows-of) 'found) [])))
    (poo-flow-test-case "lattice projection feedback rejects a strict cycle"
      (check-exception
       (gerbil-ascent-evaluate-program
        (ascent
         (lattice best ((key integer?) (value integer?)) [] min)
         (relation found ((key integer?) (value integer?)) [])
         ((best key value) <-- (found key value))
         ((found key value) <-- (best key value))
         (bounds 2 4 6)))
       true))
    (poo-flow-test-case "empty and invalid lattice declarations"
      (check-equal? (shortest []) [])
      (check-exception (gerbil-ascent-lattice 'bad 0 [] min) true)
      (check-exception (gerbil-ascent-lattice 'bad 2 '((1)) min)
                       true))
    (poo-flow-test-case "C4 lattice refinements validate joined values"
      (let* ((base (gerbil-ascent-lattice 'measure 2 '((1 2)) max))
             (source-profile (.o (:: @ base) rows: '((1 2) (1 3))))
             (type-profile
              (.o (:: @ base)
                  field-predicates: (list integer? integer?)))
             (composed (.mix source-profile type-profile))
             (program
              (gerbil-ascent-program (list composed) [] 4 4 8)))
        (check-equal?
         ((.ref (gerbil-ascent-evaluate-program program) 'rows-of) 'measure)
         '((1 3)))
        (check-exception
         (gerbil-ascent-evaluate-program
          (gerbil-ascent-program
           (list (.o (:: @ composed)
                     join: (lambda (_left _right) "invalid"))
                 (gerbil-ascent-relation 'candidate 2 '((1 4))))
           (list (gerbil-ascent-rule
                  (list (gerbil-ascent-atom 'measure
                         (list (gerbil-ascent-variable 'node)
                               (gerbil-ascent-variable 'value))))
                  (list (gerbil-ascent-atom 'candidate
                         (list (gerbil-ascent-variable 'node)
                               (gerbil-ascent-variable 'value))))))
           4 4 8))
         true)))
    (poo-flow-test-case "session joins direct lattice source values"
      (let (session
            (gerbil-ascent-open-session
             (gerbil-ascent-program
              (list (gerbil-ascent-relation 'source 2 '((1 2)))
                    (gerbil-ascent-lattice 'best 2 '((1 2)) min))
              [] 4 4 8)))
        (let (first (gerbil-ascent-session-run session))
          (gerbil-ascent-session-append-source! session 'best '(1 1))
          (check-equal?
           ((.ref (gerbil-ascent-session-run session) 'rows-of) 'best)
           '((1 1)))
          (check-equal? ((.ref first 'rows-of) 'best) '((1 2))))))
    (poo-flow-test-case "direct lattice append rejects before changing state"
      (let* ((session
              (gerbil-ascent-open-session
               (gerbil-ascent-program
                (list (gerbil-ascent-lattice 'best 2 '((1 2)) min))
                [] 3 3 2)))
             (first (gerbil-ascent-session-run session)))
        (gerbil-ascent-session-append-source! session 'best '(2 3))
        (let (second (gerbil-ascent-session-run session))
          (check-exception
           (gerbil-ascent-session-append-source! session 'best '(3 4))
           true)
          (check-equal? (eq? second (gerbil-ascent-session-run session)) #t)
          (check-equal? ((.ref second 'rows-of) 'best)
                        '((1 2) (2 3)))
          (check-equal? ((.ref first 'rows-of) 'best) '((1 2))))))
    (poo-flow-test-case
      "mixed lattice source and rule updates match fresh fixed points"
      (let* ((session
              (gerbil-ascent-open-session
               (mixed-program [] '((0 2)))))
             (first (gerbil-ascent-session-run session)))
        (gerbil-ascent-session-append-source! session 'score '(0 2))
        (let* ((second (gerbil-ascent-session-run session))
               (fresh
                (gerbil-ascent-evaluate-program
                 (mixed-program '((0 2)) '((0 2))))))
          (for-each
           (lambda (name)
             (check-equal? ((.ref second 'rows-of) name)
                           ((.ref fresh 'rows-of) name)))
           '(score copy))
          (check-equal? (eq? second (gerbil-ascent-session-run session)) #t)
          (gerbil-ascent-session-append-source! session 'score '(0 1))
          (gerbil-ascent-session-append-source! session 'improve '(0 1))
          (let* ((third (gerbil-ascent-session-run session))
                 (fresh-third
                  (gerbil-ascent-evaluate-program
                   (mixed-program '((0 2) (0 1))
                                  '((0 2) (0 1))))))
            (for-each
             (lambda (name)
               (check-equal? ((.ref third 'rows-of) name)
                             ((.ref fresh-third 'rows-of) name)))
             '(score copy))
            (check-equal? ((.ref first 'rows-of) 'score) '((0 2)))
            (check-equal? ((.ref second 'rows-of) 'score)
                          '((0 2)))))))
    (poo-flow-test-case
      "source replacement retracts lattice and derived contributions"
      (let* ((session
              (gerbil-ascent-open-session
               (mixed-program '((0 1)) '((0 2)))))
             (first (gerbil-ascent-session-run session)))
        (gerbil-ascent-session-replace-source!
         session 'score '((0 4)))
        (let (second (gerbil-ascent-session-run session))
          (check-equal? ((.ref second 'rows-of) 'score) '((0 2)))
          (check-exception
           (gerbil-ascent-session-replace-source!
            session 'score '((0 "bad")))
           true)
          (check-equal? (eq? second (gerbil-ascent-session-run session))
                        #t)
          (gerbil-ascent-session-replace-source! session 'improve [])
          (let (third (gerbil-ascent-session-run session))
            (check-equal? ((.ref third 'rows-of) 'score) '((0 4)))
            (check-equal? ((.ref third 'rows-of) 'copy) '((0 4)))
            (check-equal? ((.ref first 'rows-of) 'score) '((0 1)))
            (check-equal? ((.ref second 'rows-of) 'score)
                          '((0 2)))))))
    (poo-flow-test-case
      "lattice refinement updates a later negative stratum"
      (let* ((edges '((0 1 4) (2 1 1)))
             (session
              (gerbil-ascent-open-session
               (ascent-lattice-negation-program edges)))
             (first (gerbil-ascent-session-run session))
             (first-rows (.ref first 'rows-of)))
        (check-equal? (not (not (member '(1) (first-rows 'not-cheap)))) #t)
        (gerbil-ascent-session-append-source! session 'edge '(0 2 1))
        (let* ((second (gerbil-ascent-session-run session))
               (second-rows (.ref second 'rows-of)))
          (check-equal? (not (not (member '(1 2) (second-rows 'score)))) #t)
          (check-equal? (not (not (member '(1) (second-rows 'cheap)))) #t)
          (check-equal? (second-rows 'not-cheap) '((3)))
          (gerbil-ascent-session-replace-source! session 'edge edges)
          (let ((third-rows
                 (.ref (gerbil-ascent-session-run session) 'rows-of)))
            (for-each
             (lambda (name)
               (check-equal? (third-rows name) (first-rows name)))
             '(score cheap not-cheap))
            (check-equal? (second-rows 'not-cheap) '((3)))))))))
