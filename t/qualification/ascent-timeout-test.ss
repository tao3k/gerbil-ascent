;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite)
        (only-in :clan/poo/object .ref)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-eqrel-storage-provider
                 gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program
                 gerbil-ascent-open-session
                 gerbil-ascent-session-run
                 gerbil-ascent-session-run-timeout
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-replace-source!
                 gerbil-ascent-session-replace-sources!)
        (only-in :gerbil-ascent/program/syntax ascent))

(export ascent-timeout-test)

(def (path-program)
  (ascent
   (relation edge (from to) '((0 1) (1 2) (2 3) (3 4) (4 5)))
   (relation path (from to))
   ((path x y) <-- (edge x y))
   ((path x z) <-- (path x y) (edge y z))
   (bounds 6 42 50)))

(def ascent-timeout-test
  (test-suite "ASCENT retained timeout"
    (poo-flow-test-case "zero budget commits rounds and resumes"
      (let* ((program (path-program))
             (session (gerbil-ascent-open-session program))
             (first (gerbil-ascent-session-run-timeout session 0))
             (first-rows ((.ref first 'rows-of) 'path)))
        (check-equal? (.ref first 'finished) #f)
        (check-equal? (length first-rows) 5)
        (check-equal? (not (not (member '(0 1) first-rows))) #t)
        (let* ((second (gerbil-ascent-session-run-timeout session 0))
               (second-rows ((.ref second 'rows-of) 'path))
               (complete (gerbil-ascent-session-run session))
               (expected (gerbil-ascent-evaluate-program program)))
          (check-equal? (.ref second 'finished) #f)
          (check-equal? (> (length second-rows) (length first-rows)) #t)
          (check-equal? ((.ref first 'rows-of) 'path) first-rows)
          (check-equal? (.ref complete 'finished) #t)
          (check-equal? (length ((.ref complete 'rows-of) 'path)) 15)
          (check-equal? ((.ref complete 'rows-of) 'path)
                        ((.ref expected 'rows-of) 'path))
          (check-equal? (eq? complete (gerbil-ascent-session-run session))
                        #t))))
    (poo-flow-test-case "source changes wait for partial fixed point"
      (let (session (gerbil-ascent-open-session (path-program)))
        (gerbil-ascent-session-run-timeout session 0)
        (check-exception
         (gerbil-ascent-session-append-source! session 'edge '(5 6)) true)
        (gerbil-ascent-session-run session)
        (gerbil-ascent-session-append-source! session 'edge '(5 6))
        (check-equal?
         (not (not (member '(0 6)
                           ((.ref (gerbil-ascent-session-run session)
                                  'rows-of) 'path))))
         #t)))
    (poo-flow-test-case "resumed recursion feeds a later negation stratum"
      (let* ((program
              (ascent
               (relation edge (from to) '((0 1) (1 2) (2 3)))
               (relation blocked (node) '((2)))
               (relation path (from to))
               (relation allowed (from to))
               ((path x y) <-- (edge x y))
               ((path x z) <-- (path x y) (edge y z))
               ((allowed x y) <-- (path x y) (not (blocked y)))
               (bounds 4 32 40)))
             (session (gerbil-ascent-open-session program))
             (partial (gerbil-ascent-session-run-timeout session 0)))
        (check-equal? (.ref partial 'finished) #f)
        (check-equal? ((.ref partial 'rows-of) 'allowed) [])
        (let* ((complete (gerbil-ascent-session-run session))
               (fresh (gerbil-ascent-evaluate-program program)))
          (check-equal? (.ref complete 'finished) #t)
          (check-equal? ((.ref complete 'rows-of) 'allowed)
                        ((.ref fresh 'rows-of) 'allowed)))))
    (poo-flow-test-case "lattice joins survive a partial round boundary"
      (let* ((program
              (ascent
               (relation edge (from to weight)
                         '((0 1 5) (0 2 20) (1 2 3) (2 3 4)))
               (lattice shortest (from to distance) [] min)
               ((shortest x y weight) <-- (edge x y weight))
               ((shortest x z distance) <--
                (shortest x y first) (edge y z second)
                (let distance (first second) (+ first second)))
               (bounds 4 64 68)))
             (session (gerbil-ascent-open-session program))
             (partial (gerbil-ascent-session-run-timeout session 0))
             (full (gerbil-ascent-session-run session))
             (fresh (gerbil-ascent-evaluate-program program)))
        (check-equal? (.ref partial 'finished) #f)
        (check-equal? (.ref full 'finished) #t)
        (check-equal? ((.ref full 'rows-of) 'shortest)
                      ((.ref fresh 'rows-of) 'shortest))
        (check-equal?
         (not (not (member '(0 2 8) ((.ref full 'rows-of) 'shortest))))
         #t)))
    (poo-flow-test-case "BYODS closure and downstream copy resume together"
      (let* ((program
              (ascent
               (relation seed (from to) '((1 2) (2 3)))
               (relation eq (from to) []
                         (index gerbil-ascent-hash-index-provider)
                         (storage gerbil-ascent-eqrel-storage-provider))
               (relation output (from to))
               ((eq x y) <-- (seed x y))
               ((output x y) <-- (eq x y))
               (bounds 8 64 72)))
             (session (gerbil-ascent-open-session program))
             (partial (gerbil-ascent-session-run-timeout session 0))
             (complete (gerbil-ascent-session-run session))
             (fresh (gerbil-ascent-evaluate-program program)))
        (check-equal? (.ref partial 'finished) #f)
        (check-equal? (length ((.ref partial 'rows-of) 'eq)) 9)
        (check-equal? ((.ref complete 'rows-of) 'output)
                      ((.ref fresh 'rows-of) 'output))))
    (poo-flow-test-case "replacement runs honor a zero timeout"
      (let* ((program
              (ascent
               (relation edge (from to) '((0 1)))
               (relation blocked (node))
               (relation path (from to))
               (relation safe (from to))
               ((path x y) <-- (edge x y))
               ((path x z) <-- (path x y) (edge y z))
               ((safe x y) <-- (path x y) (not (blocked y)))
               (bounds 8 64 72)))
             (session (gerbil-ascent-open-session program)))
        (gerbil-ascent-session-run session)
        (gerbil-ascent-session-replace-source!
         session 'edge '((0 1) (1 2) (2 3) (3 4)))
        (let* ((partial (gerbil-ascent-session-run-timeout session 0))
               (resumed (gerbil-ascent-session-run-timeout session 0))
               (complete (gerbil-ascent-session-run session)))
          (check-equal? (.ref partial 'finished) #f)
          (check-equal? (length ((.ref partial 'rows-of) 'path)) 4)
          (check-equal? (.ref resumed 'finished) #f)
          (check-equal? (length ((.ref resumed 'rows-of) 'path)) 7)
          (check-equal? (.ref complete 'finished) #t)
          (check-equal? (length ((.ref complete 'rows-of) 'path)) 10)
          (check-equal? ((.ref partial 'rows-of) 'path)
                        '((0 1) (1 2) (2 3) (3 4)))
          (gerbil-ascent-session-append-source! session 'edge '(4 5))
          (let (extended (gerbil-ascent-session-run session))
            (check-equal? (length ((.ref extended 'rows-of) 'path)) 15)
            (check-equal? (length ((.ref complete 'rows-of) 'path)) 10)))))
    (poo-flow-test-case "negated source appends honor a zero timeout"
      (let* ((program
              (ascent
               (relation edge (from to) '((0 1) (1 2)))
               (relation blocked (node))
               (relation path (from to))
               (relation safe (from to))
               ((path x y) <-- (edge x y))
               ((path x z) <-- (path x y) (edge y z))
               ((safe x y) <-- (path x y) (not (blocked y)))
               (bounds 4 16 20)))
             (session (gerbil-ascent-open-session program)))
        (gerbil-ascent-session-run session)
        (gerbil-ascent-session-append-source! session 'blocked '(2))
        (let* ((partial (gerbil-ascent-session-run-timeout session 0))
               (complete (gerbil-ascent-session-run session)))
          (check-equal? (.ref partial 'finished) #f)
          (check-equal? ((.ref partial 'rows-of) 'safe) [])
          (check-equal? ((.ref complete 'rows-of) 'safe) '((0 1))))))
    (poo-flow-test-case "lattice source appends honor a zero timeout"
      (let* ((program
              (ascent
               (relation edge (from to weight) '((0 1 4) (1 2 6)))
               (lattice shortest (from to distance) [] min)
               ((shortest x y weight) <-- (edge x y weight))
               ((shortest x z distance) <--
                (shortest x y first) (edge y z second)
                (let distance (first second) (+ first second)))
               (bounds 4 16 20)))
             (session (gerbil-ascent-open-session program)))
        (gerbil-ascent-session-run session)
        (gerbil-ascent-session-append-source! session 'shortest '(0 2 3))
        (let* ((partial (gerbil-ascent-session-run-timeout session 0))
               (complete (gerbil-ascent-session-run session)))
          (check-equal? (.ref partial 'finished) #f)
          (check-equal? (.ref complete 'finished) #t)
          (check-equal?
           (not (not (member '(0 2 3)
                             ((.ref complete 'rows-of) 'shortest))))
           #t))))
    (poo-flow-test-case "timeout duration validation leaves session usable"
      (let (session (gerbil-ascent-open-session (path-program)))
        (check-exception (gerbil-ascent-session-run-timeout session -1) true)
        (check-exception (gerbil-ascent-session-run-timeout session 1.5) true)
        (check-equal? (.ref (gerbil-ascent-session-run session) 'finished)
                      #t)))
    (poo-flow-test-case "pending provider recovery retains timed round boundaries"
      (let* ((program
              (ascent
               (relation eq (from to) '((0 1))
                         (index gerbil-ascent-hash-index-provider)
                         (storage gerbil-ascent-eqrel-storage-provider))
               (relation output (from to))
               ((output x y) <-- (eq x y))
               (bounds 4 32 64)))
             (session (gerbil-ascent-open-session program)))
        (gerbil-ascent-session-run session)
        (gerbil-ascent-session-replace-source! session 'eq '((0 1) (1 2)))
        (check-exception
         (gerbil-ascent-session-append-source! session 'eq '(3)) true)
        (let (partial (gerbil-ascent-session-run-timeout session 0))
          (check-equal? (.ref partial 'finished) #f)
          (check-equal? (length ((.ref partial 'rows-of) 'output)) 9))
        (check-equal? (.ref (gerbil-ascent-session-run session) 'finished) #t)))
    (poo-flow-test-case "provisional replacement failure restores source and result together"
      (let* ((program
              (ascent
               (relation edge (from to) '((0 1)))
               (relation path (from to))
               ((path x y) <-- (edge x y))
               ((path x z) <-- (path x y) (edge y z))
               (bounds 5 6 11)))
             (session (gerbil-ascent-open-session program))
             (committed (gerbil-ascent-session-run session)))
        (gerbil-ascent-session-replace-source! session 'edge '((0 1) (1 2)))
        (for-each
         (lambda (edge)
           (gerbil-ascent-session-append-source! session 'edge edge))
         '((2 3) (3 4) (4 5)))
        (let (partial (gerbil-ascent-session-run-timeout session 0))
          (check-equal? (.ref partial 'finished) #f)
          (check-exception (gerbil-ascent-session-run session) true)
          (check-equal? (eq? committed (gerbil-ascent-session-run session)) #t)
          (check-equal? ((.ref committed 'rows-of) 'path) '((0 1))))
        (gerbil-ascent-session-replace-sources! session '((edge (7 8))))
        (check-equal? ((.ref (gerbil-ascent-session-run session) 'rows-of) 'path)
                      '((7 8)))))
    (poo-flow-test-case "failed resume restores the accepted source snapshot"
      (let* ((program
              (ascent
               (relation edge (from to))
               (relation path (from to))
               ((path x y) <-- (edge x y))
               ((path x z) <-- (path x y) (edge y z))
               (bounds 5 6 11)))
             (session (gerbil-ascent-open-session program)))
        (check-equal? ((.ref (gerbil-ascent-session-run session) 'rows-of)
                       'path)
                      [])
        (for-each
         (lambda (edge)
           (gerbil-ascent-session-append-source! session 'edge edge))
         '((0 1) (1 2) (2 3) (3 4) (4 5)))
        (let* ((partial (gerbil-ascent-session-run-timeout session 0))
               (saved ((.ref partial 'rows-of) 'path)))
          (check-equal? (.ref partial 'finished) #f)
          (check-exception (gerbil-ascent-session-run session) true)
          (check-equal? ((.ref partial 'rows-of) 'path) saved)
          (gerbil-ascent-session-replace-source! session 'edge '((7 8)))
          (check-equal? ((.ref (gerbil-ascent-session-run session) 'rows-of)
                         'path)
                        '((7 8)))
          ;; Recovery must publish a completed result before the next batch
          ;; update can use the native completed-closure reuse path.
          (gerbil-ascent-session-replace-sources!
           session '((edge (8 9))))
          (check-equal? ((.ref (gerbil-ascent-session-run session) 'rows-of)
                         'path)
                        '((8 9))))))))
