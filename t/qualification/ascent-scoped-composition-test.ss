;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/encoding/json (only-in :clan/poo/object .ref)
        :gerbil-ascent/applications/scoped-composition
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session
                 gerbil-ascent-session-run gerbil-ascent-session-replace-source!))
(export ascent-scoped-composition-test)
(def (bit id place) (= (modulo (quotient id place) 2) 1))
(def (subset rows mask)
  (filter-map (lambda (row index) (and (bit mask (expt 2 index)) row)) rows (iota (length rows))))
(def (query result name) (check-equal? (.ref result 'finished) #t) ((.ref result 'rows-of) name))
(def (check-rows actual expected)
  (check-equal? (length actual) (length expected))
  (for-each (lambda (row) (check-equal? (and (member row actual) #t) #t)) expected))
(def memberships '((red alpha) (red beta) (blue alpha) (blue beta)))
(def branch-rows '((alpha 0 3) (beta 0 3)))
(def group-rows '((red 0 3) (blue 0 3)))
(def witness-rows '((red alpha 0 3) (red beta 0 3) (blue alpha 0 3) (blue beta 0 3)))
(def (program required members direct (candidates '((0 3))) (blocked []) (edges []))
  (gerbil-ascent-scoped-composition-program edges '((alpha 0) (beta 0))
    '((alpha 3) (beta 3)) blocked direct required members candidates))
(def ascent-scoped-composition-test
  (test-suite "Scoped group composition with evidence"
    (test-case "all 512 foreign states match real branch inputs coverage missing groups and answers"
      (let ((corpus (call-with-input-file "t/qualification/fixtures/scoped-composition/conformance.json" read-json))
            (sessions (make-hash-table-eqv)))
        (check-equal? (length corpus) 512)
        (for-each
         (lambda (vector id)
           (check-equal? (length vector) 5) (check-equal? (car vector) id)
           (let* ((branch-mask (modulo id 4))
                  (session (or (hash-get sessions branch-mask)
                               (let (owner (gerbil-ascent-open-session
                                            (program [] [] (subset branch-rows branch-mask) [])))
                                 (hash-put! sessions branch-mask owner) owner))))
             (when (>= id 4)
               (gerbil-ascent-session-replace-source! session 'group_member
                 (subset memberships (modulo (quotient id 4) 16)))
               (when (< (modulo id 64) 4)
                 (gerbil-ascent-session-replace-source! session 'group_required
                   (subset '((red) (blue)) (modulo (quotient id 64) 4))))
               (when (< 255 id 260)
                 (gerbil-ascent-session-replace-source! session 'group_candidate '((0 3)))))
             (let (result (gerbil-ascent-session-run session))
               ;; Validate the abstract branch premise with native output first.
               (check-rows (query result 'branch_answer) (subset branch-rows branch-mask))
               (check-rows (query result 'branch_witness) [])
               (check-rows (query result 'group_witness) (subset witness-rows (cadr vector)))
               (check-rows (query result 'group_support) (subset group-rows (caddr vector)))
               (check-rows (query result 'group_missing) (subset group-rows (cadddr vector)))
               (check-rows (query result 'group_answer) (if (= (list-ref vector 4) 1) '((0 3)) []))))
           (when (zero? (modulo (+ id 1) 64))
             (displayln "SCOPED-COMPOSITION " (+ id 1) "/512") (force-output)))
         corpus (iota 512))))
    (test-case "ScopedComposition/union requires every group not any supported group"
      (let (result (gerbil-ascent-evaluate-program
                    (program '((red) (blue)) '((red alpha) (blue beta)) '((alpha 0 3)))))
        (check-rows (query result 'group_support) '((red 0 3)))
        (check-rows (query result 'group_missing) '((blue 0 3)))
        (check-rows (query result 'group_answer) [])))
    (test-case "ScopedComposition/allBranches accepts one supported member within a group"
      (let (result (gerbil-ascent-evaluate-program
                    (program '((red)) '((red alpha) (red beta)) '((alpha 0 3)))))
        (check-rows (query result 'group_witness) '((red alpha 0 3)))
        (check-rows (query result 'group_answer) '((0 3)))))
    (test-case "ScopedComposition/emptyGroup rejects a required group without members"
      (let (result (gerbil-ascent-evaluate-program (program '((red)) [] branch-rows)))
        (check-rows (query result 'group_missing) '((red 0 3)))
        (check-rows (query result 'group_answer) [])))
    (test-case "ScopedComposition/forgetWitness retains group and scope evidence"
      (let (result (gerbil-ascent-evaluate-program (program '((red) (blue)) memberships branch-rows)))
        (check-rows (query result 'group_witness) witness-rows)
        (check-rows (query result 'group_answer) '((0 3)))))
    (test-case "zero required groups selects only the explicit finite candidate universe"
      (let (result (gerbil-ascent-evaluate-program (program [] [] branch-rows '((other target)))))
        (check-rows (query result 'group_answer) '((other target)))
        (check-rows (query result 'group_witness) [])
        (check-rows (query result 'group_missing) [])))
    (test-case "groups cannot combine supports for different endpoint pairs"
      (let (result (gerbil-ascent-evaluate-program
                    (gerbil-ascent-scoped-composition-program [] '((alpha 0) (beta 0))
                     '((alpha 3) (beta 4)) [] '((alpha 0 3) (beta 0 4))
                     '((red) (blue)) '((red alpha) (blue beta)) '((0 3) (0 4)))))
        (check-rows (query result 'group_missing) '((blue 0 3) (red 0 4)))
        (check-rows (query result 'group_answer) [])))
    (test-case "changing a nonmember scope mask leaves the required composition unchanged"
      (let* ((session (gerbil-ascent-open-session
                       (program '((red)) '((red alpha)) [] '((0 3)) [] '((0 1) (1 3)))))
             (initial (gerbil-ascent-session-run session)))
        (check-rows (query initial 'branch_answer) branch-rows)
        (gerbil-ascent-session-replace-source! session 'branch_blocked '((beta 1)))
        (let (next (gerbil-ascent-session-run session))
          (check-rows (query next 'branch_answer) '((alpha 0 3)))
          (check-rows (query next 'group_witness) '((red alpha 0 3)))
          (check-rows (query next 'group_answer) '((0 3))))))
    (test-case "scoped exclusion withdraws one group while held evidence remains frozen"
      (let* ((session (gerbil-ascent-open-session
                       (program '((red) (blue)) '((red alpha) (blue beta)) [] '((0 3))
                                [] '((0 1) (1 3)))))
             (held (gerbil-ascent-session-run session)))
        (check-rows (query held 'group_answer) '((0 3)))
        (gerbil-ascent-session-replace-source! session 'branch_blocked '((alpha 1)))
        (let (next (gerbil-ascent-session-run session))
          (check-rows (query next 'group_support) '((blue 0 3)))
          (check-rows (query next 'group_missing) '((red 0 3)))
          (check-rows (query next 'group_answer) []))
        (check-rows (query held 'group_witness) '((red alpha 0 3) (blue beta 0 3)))
        (check-rows (query held 'group_answer) '((0 3)))))))
