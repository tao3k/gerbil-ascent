;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/encoding/json
        (only-in :clan/poo/object .ref)
        :gerbil-ascent/applications/scoped-witness
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session
                 gerbil-ascent-session-run gerbil-ascent-session-replace-source!))
(export ascent-branch-scoped-witness-test)
(def (bit id place) (= (modulo (quotient id place) 2) 1))
(def (subset rows mask)
  (filter-map (lambda (row index) (and (bit mask (expt 2 index)) row)) rows (iota (length rows))))
(def (query result name)
  (check-equal? (.ref result 'finished) #t)
  ((.ref result 'rows-of) name))
(def (check-rows actual expected)
  (check-equal? (length actual) (length expected))
  (for-each (lambda (row) (check-equal? (and (member row actual) #t) #t)) expected))
(def witnesses '((alpha 0 1 3) (alpha 0 2 3) (beta 0 1 3) (beta 0 2 3)))
(def answers '((alpha 0 3) (beta 0 3)))
(def (program blocked (direct []) (edges '((0 1) (1 3) (0 2) (2 3))))
  (gerbil-ascent-branch-scoped-witness-program
   edges '((alpha 0) (beta 0)) '((alpha 3) (beta 3)) blocked direct))
(def ascent-branch-scoped-witness-test
  (test-suite "Branch scoped witness execution and union"
    (test-case "all 1024 foreign states retain exact scope witnesses branches and union"
      (let ((corpus (call-with-input-file "t/qualification/fixtures/branch-scoped-witness/conformance.json" read-json))
            (sessions (make-hash-table-eqv)))
        (check-equal? (length corpus) 1024)
        (for-each
         (lambda (vector id)
           (check-equal? (length vector) 4)
           (check-equal? (car vector) id)
           (let* ((edge-mask (modulo id 16))
                  (session (or (hash-get sessions edge-mask)
                               (let (owner (gerbil-ascent-open-session
                                            (program [] [] (subset '((0 1) (1 3) (0 2) (2 3)) edge-mask))))
                                 (hash-put! sessions edge-mask owner) owner))))
             ;; First run each new owner before replacement, as Session requires.
             (when (>= id 16)
               (gerbil-ascent-session-replace-source! session 'branch_blocked
                 (subset '((alpha 1) (alpha 2) (beta 1) (beta 2))
                         (modulo (quotient id 16) 16)))
               ;; Each direct mask changes once per retained edge owner.
               (when (and (>= id 256) (< (modulo id 256) 16))
                 (gerbil-ascent-session-replace-source! session 'branch_direct
                   (subset answers (quotient id 256)))))
             (let (result (gerbil-ascent-session-run session))
               (check-rows (query result 'branch_witness) (subset witnesses (cadr vector)))
               (check-rows (query result 'branch_answer) (subset answers (caddr vector)))
               (check-rows (query result 'branch_union) (if (= (cadddr vector) 1) '((0 3)) []))))
           (when (zero? (modulo (+ id 1) 128))
             (displayln "BRANCH-SCOPED-WITNESS " (+ id 1) "/1024") (force-output)))
         corpus (iota 1024))))
    (test-case "BranchScopedWitness/crossMask keeps the other branch despite complete local exclusion"
      (let (result (gerbil-ascent-evaluate-program (program '((alpha 1) (alpha 2)))))
        (check-rows (query result 'branch_witness) '((beta 0 1 3) (beta 0 2 3)))
        (check-rows (query result 'branch_answer) '((beta 0 3)))
        (check-rows (query result 'branch_union) '((0 3)))))
    (test-case "BranchScopedWitness/switchMask attaches each exclusion to its named branch"
      (let (result (gerbil-ascent-evaluate-program (program '((alpha 1) (beta 2)))))
        (check-rows (query result 'branch_witness) '((alpha 0 2 3) (beta 0 1 3)))
        (check-rows (query result 'branch_answer) answers)))
    (test-case "BranchScopedWitness/forgetScope publishes both identities even for equal projected answers"
      (let (result (gerbil-ascent-evaluate-program (program [])))
        (check-rows (query result 'branch_witness) witnesses)
        (check-rows (query result 'branch_answer) answers)
        (check-rows (query result 'branch_union) '((0 3)))))
    (test-case "BranchScopedWitness/collapseBranch preserves the direct branch identity"
      (let (result (gerbil-ascent-evaluate-program (program [] '((beta 0 3)) [])))
        (check-rows (query result 'branch_witness) [])
        (check-rows (query result 'branch_answer) '((beta 0 3)))
        (check-rows (query result 'branch_union) '((0 3)))))
    (test-case "starts targets and unselected direct support never join across scope identities"
      (let (result (gerbil-ascent-evaluate-program
                    (gerbil-ascent-branch-scoped-witness-program
                     '((start middle) (middle target)) '((left start)) '((right target))
                     [] '((left start target) (ghost start target)))))
        (check-rows (query result 'branch_witness) [])
        (check-rows (query result 'branch_answer) [])
        (check-rows (query result 'branch_union) [])))
    (test-case "local replacements preserve other scopes and held publication generations"
      (let* ((session (gerbil-ascent-open-session (program [])))
             (held (gerbil-ascent-session-run session)))
        (gerbil-ascent-session-replace-source! session 'branch_blocked '((alpha 1) (alpha 2)))
        (let (next (gerbil-ascent-session-run session))
          (check-rows (query next 'branch_witness) '((beta 0 1 3) (beta 0 2 3)))
          (check-rows (query next 'branch_answer) '((beta 0 3)))
          (check-rows (query next 'branch_union) '((0 3))))
        (gerbil-ascent-session-replace-source! session 'branch_blocked '((alpha 1) (alpha 2) (beta 1) (beta 2)))
        (check-rows (query (gerbil-ascent-session-run session) 'branch_union) [])
        (check-rows (query held 'branch_witness) witnesses)
        (check-rows (query held 'branch_answer) answers)
        (check-rows (query held 'branch_union) '((0 3)))))))
