;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object :gerbil-ascent/program/objects
        :gerbil-ascent/t/performance/scc-execution/fixture
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine)
        (prefix-in :gerbil-ascent/t/performance/scc-execution/reference-evaluate old-)
        (prefix-in :gerbil-ascent/t/performance/scc-execution/reference-positive-components old-components-)
        (prefix-in :gerbil-ascent/t/performance/scc-execution/reference-component-worker old-worker-)
        (only-in :gerbil-ascent/program/component-worker make-component-snapshot gerbil-ascent-run-positive-component!)
        (only-in :gerbil-ascent/program/positive-components gerbil-ascent-positive-components positive-component-rules))
(export ascent-scc-execution-test)
(def (rejected? call) (with-catch (lambda (_) #t) (lambda () (call) #f)))
(def (solve maker program jobs canceled?)
  ((maker program #f #f #f #f #f #f jobs canceled?)))
(def ascent-scc-execution-test
  (test-suite "Dense SCC workspaces and terminal predecessor release"
    (test-case "six complete consumers match frozen engines and independent truth"
      (for-each
       (lambda (scenario)
         (let ((old (scc-prepare #t scenario)) (new (scc-prepare #f scenario)))
           (check-equal? (scc-consume old scenario #t) (scc-expected old scenario))
           (check-equal? (scc-consume new scenario #f) (scc-expected new scenario))))
       '(wide chain indexed cold small serial)))
    (test-case "high global slots remain correct across independent worker capacities"
      (let* ((state (scc-prepare #f 'chain)) (program (vector-ref state 0)))
        (for-each (lambda (jobs)
                    (check-equal? (scc-project (solve gerbil-ascent-make-engine program jobs (lambda () #f)))
                                  (scc-expected state 'chain))) '(1 2 4))))
    (test-case "full closure keeps exact unique derived and output budgets"
      (let* ((program (scc-program 'small))
             (accepted (gerbil-ascent-program (.ref program 'relations) (.ref program 'rules) 1 1 2))
             (rejected (gerbil-ascent-program (.ref program 'relations) (.ref program 'rules) 1 1 1)))
        (for-each
         (lambda (maker)
           (check-equal? ((.ref (solve maker accepted 2 #f) 'relation-sizes)) '((source . 1) (out0 . 1)))
           (check-equal? (rejected? (lambda () (solve maker rejected 2 #f))) #t))
         (list old-gerbil-ascent-make-engine gerbil-ascent-make-engine))))
    (test-case "cancellation rejects before admitting a complete cut"
      (let (program (scc-program 'wide))
        (for-each (lambda (maker)
                    (check-equal? (rejected? (lambda () (solve maker program 2 (lambda () #t)))) #t))
                  (list old-gerbil-ascent-make-engine gerbil-ascent-make-engine))))
    (test-case "local workspace compilation leaves original relation descriptors intact"
      (let* ((state (scc-prepare #f 'indexed)) (program (vector-ref state 0))
             (engine (gerbil-ascent-make-engine program #t))
             (components (gerbil-ascent-positive-components (.ref engine '.analysis))))
        (def (descriptors)
          (apply append
            (map (lambda (component)
              (apply append (map (lambda (rule)
                (let (plan (vector-ref rule 0))
                  (map (lambda (header) (vector->list (vector-ref header 0)))
                       (append (vector-ref plan 0) (vector-ref plan 1)))))
                (positive-component-rules component)))) components)))
        (let (before (descriptors))
          (check-equal? (scc-project (solve gerbil-ascent-make-engine program 4 #f)) (scc-expected state 'indexed))
          (check-equal? (descriptors) before))))
    (test-case "full snapshots preserve prior round commits after emission failure"
      (let* ((program (scc-program 'indexed))
             (engine (gerbil-ascent-make-engine program #t))
             (analysis (.ref engine '.analysis)) (schema (.ref engine '.schema))
             (initial (list->vector (map (lambda (r) (reverse (.ref r 'rows))) (.ref program 'relations)))))
        (def (partial old?)
          (let* ((components ((if old? old-components-gerbil-ascent-positive-components gerbil-ascent-positive-components) analysis))
                 (rules (if old? old-components-positive-component-rules positive-component-rules))
                 (component (car (filter (lambda (c) (pair? (rules c))) components)))
                 (rows (vector-copy initial)) (sizes (vector-map length rows)) (emissions 0))
            (check-equal? (rejected? (lambda ()
              ((if old? old-worker-gerbil-ascent-run-positive-component! gerbil-ascent-run-positive-component!)
               component schema ((if old? old-worker-make-component-snapshot make-component-snapshot) rows sizes)
               (lambda (atom row)
                 (check-equal? (vector-ref atom 0) 1)
                 (set! emissions (+ emissions 1))
                 (when (= emissions 33) (error "stop after an owned round commit"))) void))) #t)
            (check-equal? emissions 33)
            (check-equal? (eq? (vector-ref rows 0) (vector-ref initial 0)) #t)
            (check-equal? sizes '#(31 31))
            rows))
        (check-equal? (partial #f) (partial #t))))))
