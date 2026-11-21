;;; -*- Gerbil -*-
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :gerbil-ascent/candidate/types make-reasoning-candidate)
        (only-in :gerbil-ascent/candidate/checked-program reasoning-source-snapshot)
        (only-in :gerbil-ascent/candidate/provenance-graph
          candidate-positive-provenance candidate-open-provenance-maintenance
          candidate-provenance-withdraw! provenance-maintenance-rows)
        (only-in "../performance/provenance-maintenance/work-accounting.ss" expected-work)
        (rename-in (only-in :gerbil-ascent/t/performance/provenance-maintenance/reference
          candidate-positive-provenance candidate-open-provenance-maintenance
          candidate-provenance-withdraw!)
          (candidate-positive-provenance old-graph)
          (candidate-open-provenance-maintenance old-open)
          (candidate-provenance-withdraw! old-withdraw!)))
(export ascent-provenance-work-accounting-test)

(def (audit scenario)
  (let* ((small? (eq? scenario 'small)) (duplicates? (eq? scenario 'duplicates))
         (count (if small? 1 256))
         (rows (map (lambda (i) (list (if duplicates? 1 i))) (iota count)))
         (initial (if duplicates? '((1)) rows))
         (snapshot (reasoning-source-snapshot 'maintenance-benchmark 1
                     (list (list 's 1 rows))))
         (spec (make-reasoning-candidate '((p . 1)) []
                 (list (vector '(p ?x) '((s ?x)) 10)
                       (vector '(p ?x) '((p ?x)) 11))
                 (vector '(p ?x) 12) '(4096 4096 8192)))
         (graph (candidate-positive-provenance snapshot spec 'program 'complete
                  initial 100000 4096))
         (prior (old-graph snapshot spec 'program 'complete initial 100000 4096))
         (selectors (map (lambda (i) (list 's (+ i 1)))
                       (iota (if (or small? duplicates?) count 128))))
         (expected (expected-work graph selectors)))
    (def (prepare) (candidate-open-provenance-maintenance snapshot spec 'program
                     'complete initial graph 100000 4096))
    (let-values (((old-rows _)
                  (old-withdraw! (old-open snapshot spec 'program 'complete
                                   initial prior 100000 4096) selectors 100000))
                 ((new-rows new-work)
                  (candidate-provenance-withdraw! (prepare) selectors 100000)))
      (check-equal? new-rows old-rows)
      (check-equal? new-work expected))
    (let* ((state (prepare)) (before (provenance-maintenance-rows state))
           (failure (with-exception-catcher error-message
                      (lambda () (candidate-provenance-withdraw! state selectors (- expected 1)) #f))))
      (check-equal? failure "provenance withdrawal budget exceeded")
      (check-equal? (provenance-maintenance-rows state) before)
      (let-values (((after work) (candidate-provenance-withdraw! state selectors expected)))
        (check-equal? work expected)))
    (let (state (prepare))
      (check-equal? (with-exception-catcher error-message
                     (lambda ()
                       (candidate-provenance-withdraw! state '((s 99999)) 1) #f))
                    "unknown provenance source occurrence"))))

(def ascent-provenance-work-accounting-test
  (test-suite "Independent provenance work accounting audit"
    (test-case "duplicate source occurrences keep exact accounting and rollback" (audit 'duplicates))
    (test-case "wide distinct sources keep exact accounting and rollback" (audit 'wide))
    (test-case "small sources keep exact accounting and rollback" (audit 'small))))
