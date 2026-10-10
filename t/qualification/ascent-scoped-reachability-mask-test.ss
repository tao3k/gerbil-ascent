;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/encoding/json (only-in :std/list/list delete-duplicates/hash) (only-in :clan/poo/object .ref)
        :gerbil-ascent/applications/scoped-reachability-mask
        :gerbil-ascent/applications/scoped-composition
        :gerbil-ascent/applications/taint-paths
        (only-in :gerbil-ascent/program/objects gerbil-ascent-program)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session
                 gerbil-ascent-session-run gerbil-ascent-session-replace-source!))
(export ascent-scoped-reachability-mask-test)
(def (bit id n) (= (modulo (quotient id (expt 2 n)) 2) 1))
(def (subset rows mask)
  (filter-map (lambda (row index) (and (bit mask index) row)) rows (iota (length rows))))
(def (query result name) (check-equal? (.ref result 'finished) #t) ((.ref result 'rows-of) name))
(def (check-rows actual expected)
  (check-equal? (length actual) (length expected))
  (for-each (lambda (row) (check-equal? (and (member row actual) #t) #t)) expected))
(def branches (apply append (map (lambda (scope) (map (lambda (t) (list scope 0 t)) (iota 3))) '(alpha beta))))
(def blocked-rows (apply append (map (lambda (scope) (map (lambda (z) (list scope z)) (iota 3))) '(alpha beta))))
(def witnesses (apply append (map (lambda (scope)
  (apply append (map (lambda (z) (map (lambda (t) (list scope 0 z t)) (iota 3))) (iota 3)))) '(alpha beta))))
(def pairs (apply append (map (lambda (s) (map (lambda (t) (list s t)) (iota 3))) (iota 3))))
(def (base edges blocked (vertices '((0) (1) (2))) (targets '((alpha 0) (alpha 1) (alpha 2) (beta 0) (beta 1) (beta 2))))
  (gerbil-ascent-scoped-reachability-mask-program vertices edges '((alpha 0) (beta 0)) targets blocked))
(def (composed edges blocked)
  (gerbil-ascent-compose-scoped-program (base edges blocked)
    '((red) (blue)) '((red alpha) (blue beta)) '((0 0) (0 1) (0 2))))
(def ascent-scoped-reachability-mask-test
  (test-suite "Scoped structural reachability mask"
    (test-case "512 foreign inputs check actual closure exclusion witnesses branches and composed answers"
      (let ((corpus (call-with-input-file "t/qualification/fixtures/scoped-reachability-mask/conformance.json" read-json))
            (sessions (make-hash-table-eqv)))
        (check-equal? (length corpus) 512)
        (for-each (lambda (vector id)
          (check-equal? (length vector) 5) (check-equal? (car vector) id)
          (let* ((edges (modulo id 8))
                 (session (or (hash-get sessions edges)
                   (let (owner (gerbil-ascent-open-session (composed (subset '((0 1) (1 2) (2 0)) edges) [])))
                     (hash-put! sessions edges owner) owner))))
            (when (>= id 8) (gerbil-ascent-session-replace-source! session 'mask_blocked
                             (subset blocked-rows (quotient id 8))))
            (let* ((result (gerbil-ascent-session-run session))
                   (expected-branches (subset branches (list-ref vector 3)))
                   (expected-witnesses (subset witnesses (caddr vector)))
                   (rejected (delete-duplicates/hash (map (lambda (w) (list (car w) (cadr w) (cadddr w))) expected-witnesses))))
              (check-rows (query result 'mask_reach) (subset pairs (cadr vector)))
              (check-rows (query result 'mask_witness) expected-witnesses)
              (check-rows (query result 'mask_rejected) rejected)
              (check-rows (query result 'branch_answer) expected-branches)
              (check-rows (query result 'group_witness)
                (map (lambda (b) (cons (if (eq? (car b) 'alpha) 'red 'blue) b)) expected-branches))
              (check-rows (query result 'group_answer) (subset '((0 0) (0 1) (0 2)) (list-ref vector 4)))))
          (when (zero? (modulo (+ id 1) 64)) (displayln "SCOPED-REACHABILITY-MASK " (+ id 1) "/512") (force-output)))
          corpus (iota 512))))
    (test-case "cleanAlternative clean diamond path survives but structural pair is excluded"
      (let* ((edges '((0 1) (1 3) (0 2) (2 3)))
             (masked (gerbil-ascent-evaluate-program
                       (base edges '((alpha 1)) '((0) (1) (2) (3)) '((alpha 3) (beta 3)))))
             (clean (gerbil-ascent-evaluate-program
                      (gerbil-ascent-taint-path-program edges '((0)) '((3)) '((1))))))
        (check-rows (query masked 'mask_witness) '((alpha 0 1 3)))
        (check-rows (query masked 'branch_answer) '((beta 0 3)))
        (check-rows (query clean 'taint_alert) '((0 3)))))
    (test-case "global and late controls preserve beta while rejecting alpha through intermediate node"
      (let (result (gerbil-ascent-evaluate-program (base '((0 1) (1 2)) '((alpha 1)))))
        (check-rows (query result 'branch_answer) '((alpha 0 0) (beta 0 0) (beta 0 1) (beta 0 2)))
        (check-rows (query result 'mask_witness) '((alpha 0 1 1) (alpha 0 1 2)))))
    (test-case "cyclic witnesses reject all pairs in affected scope including zero-hop start"
      (let (result (gerbil-ascent-evaluate-program (base '((0 1) (1 2) (2 0)) '((alpha 2)))))
        (check-rows (query result 'branch_answer) '((beta 0 0) (beta 0 1) (beta 0 2)))
        (check-rows (query result 'mask_witness) '((alpha 0 2 0) (alpha 0 2 1) (alpha 0 2 2)))))
    (test-case "recursive closure admits a three-hop chain and scope endpoint exclusion"
      (let (result (gerbil-ascent-evaluate-program
                    (base '((0 1) (1 2) (2 3)) '((alpha 3)) '((0) (1) (2) (3)) '((alpha 3) (beta 3)))))
        (check-rows (query result 'branch_answer) '((beta 0 3)))
        (check-rows (query result 'mask_witness) '((alpha 0 3 3)))))
    (test-case "mask withdrawal restores composed answer and held rejected evidence stays frozen"
      (let* ((session (gerbil-ascent-open-session (composed '((0 1) (1 2)) '((alpha 1)))))
             (held (gerbil-ascent-session-run session)))
        (check-rows (query held 'group_answer) '((0 0)))
        (gerbil-ascent-session-replace-source! session 'mask_blocked [])
        (let (next (gerbil-ascent-session-run session))
          (check-rows (query next 'mask_witness) [])
          (check-rows (query next 'group_answer) '((0 0) (0 1) (0 2))))
        (check-rows (query held 'mask_witness) '((alpha 0 1 1) (alpha 0 1 2)))
        (check-rows (query held 'group_answer) '((0 0)))))
    (test-case "closure remains inside declared vertices and selected endpoints"
      (let (result (gerbil-ascent-evaluate-program
                    (base '((0 9) (9 2)) '((alpha 9)) '((0) (2)) '((alpha 2) (beta 2)))))
        (check-rows (query result 'mask_reach) '((0 0) (2 2)))
        (check-rows (query result 'mask_witness) [])
        (check-rows (query result 'branch_answer) [])))
    (test-case "generic composition preserves producer budgets and source handles"
      (let* ((producer (gerbil-ascent-scoped-reachability-mask-program '((0)) [] '((alpha 0)) '((alpha 0)) [] 17 23 31))
             (producer (gerbil-ascent-program (.ref producer 'relations) (.ref producer 'rules)
                         17 23 31 '(mask_blocked)))
             (program (gerbil-ascent-compose-scoped-program producer [] [] '((0 0)))))
        (for-each (lambda (slot) (check-equal? (.ref program slot) (.ref producer slot)))
          '(max-input-facts max-derived-facts max-output-facts source-handles))
        (check-rows (query (gerbil-ascent-evaluate-program program) 'group_answer) '((0 0)))))))
