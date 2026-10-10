;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/encoding/json
        (only-in :clan/poo/object .ref)
        :gerbil-ascent/applications/scoped-witness
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session
                 gerbil-ascent-session-run gerbil-ascent-session-replace-source!))
(export ascent-scoped-witness-test)
(def (bit id place) (= (modulo (quotient id place) 2) 1))
(def (subset rows mask)
  (filter-map (lambda (row index) (and (bit mask (expt 2 index)) row)) rows (iota (length rows))))
(def (query result name)
  (check-equal? (.ref result 'finished) #t)
  ((.ref result 'rows-of) name))
(def (check-rows actual expected)
  (check-equal? (length actual) (length expected))
  (for-each (lambda (row) (check-equal? (and (member row actual) #t) #t)) expected))
(def ascent-scoped-witness-test
  (test-suite "Scoped witness execution before projection"
    (test-case "all 256 foreign input states agree on witnesses and answers"
      (let ((corpus (call-with-input-file "t/qualification/fixtures/scoped-witness/conformance.json" read-json))
            (sessions (make-hash-table-eqv)))
        (check-equal? (length corpus) 256)
        (for-each
         (lambda (vector id)
           (check-equal? (length vector) 3)
           (check-equal? (car vector) id)
           (let* ((edge-mask (modulo id 16))
                  (session (or (hash-get sessions edge-mask)
                               (let (owner (gerbil-ascent-open-session
                                            (gerbil-ascent-scoped-witness-program
                                             (subset '((0 1) (1 3) (0 2) (2 3)) edge-mask)
                                             '((0)) '((3)) [] [])))
                                 (hash-put! sessions edge-mask owner) owner))))
             ;; Initial states have both masks empty. Run each new owner once
             ;; before using the Session's established replacement protocol.
             (when (>= id 16)
               (gerbil-ascent-session-replace-source! session 'scope_blocked
                 (subset '((1) (2) (3)) (modulo (quotient id 16) 8)))
               ;; Each retained owner crosses the direct-branch cut once.
               (when (< 127 id 144)
                 (gerbil-ascent-session-replace-source! session 'scope_direct '((0 3)))))
             (let (result (gerbil-ascent-session-run session))
               (check-rows (query result 'scope_witness)
                           (subset '((0 1 3) (0 2 3)) (cadr vector)))
               (check-rows (query result 'scope_answer) (if (= (caddr vector) 1) '((0 3)) []))))
           (when (zero? (modulo (+ id 1) 64))
             (displayln "SCOPED-WITNESS " (+ id 1) "/256") (force-output)))
         corpus (iota 256))))
    (test-case "ScopedWitness/anyBlocked preserves the other witness"
      (let (result (gerbil-ascent-evaluate-program
                    (gerbil-ascent-scoped-witness-program
                     '((0 1) (1 3) (0 2) (2 3)) '((0)) '((3)) '((1)) [])))
        (check-rows (query result 'scope_witness) '((0 2 3)))
        (check-rows (query result 'scope_answer) '((0 3)))))
    (test-case "ScopedWitness/global preserves direct support"
      (let (result (gerbil-ascent-evaluate-program
                    (gerbil-ascent-scoped-witness-program
                     '((0 1) (1 3)) '((0)) '((3)) '((1) (3)) '((0 3)))))
        (check-rows (query result 'scope_witness) [])
        (check-rows (query result 'scope_answer) '((0 3)))))
    (test-case "ScopedWitness/late excludes the middle before projection"
      (let (result (gerbil-ascent-evaluate-program
                    (gerbil-ascent-scoped-witness-program
                     '((0 1) (1 3)) '((0)) '((3)) '((1)) [])))
        (check-rows (query result 'scope_witness) [])
        (check-rows (query result 'scope_answer) [])))
    (test-case "ScopedWitness/forget retains evidence even when the answer is right"
      (let (result (gerbil-ascent-evaluate-program
                    (gerbil-ascent-scoped-witness-program
                     '((0 1) (1 3)) '((0)) '((3)) [] [])))
        (check-rows (query result 'scope_answer) '((0 3)))
        (check-rows (query result 'scope_witness) '((0 1 3)))))
    (test-case "selected start and target scope constrain both branches"
      (let (result (gerbil-ascent-evaluate-program
                    (gerbil-ascent-scoped-witness-program
                     '((other middle) (start middle) (middle target) (middle outside))
                     '((start)) '((target)) [] '((other target) (start outside)))))
        (check-rows (query result 'scope_witness) '((start middle target)))
        (check-rows (query result 'scope_answer) '((start target)))))
    (test-case "source replacement preserves previously published witness rows"
      (let* ((session (gerbil-ascent-open-session
                      (gerbil-ascent-scoped-witness-program
                       '((0 1) (1 3) (0 2) (2 3)) '((0)) '((3)) [] [])))
             (held (gerbil-ascent-session-run session)))
        (gerbil-ascent-session-replace-source! session 'scope_blocked '((1)))
        (check-rows (query (gerbil-ascent-session-run session) 'scope_witness) '((0 2 3)))
        (gerbil-ascent-session-replace-source! session 'scope_edge '((0 1) (1 3)))
        (check-rows (query (gerbil-ascent-session-run session) 'scope_answer) [])
        (check-rows (query held 'scope_witness) '((0 1 3) (0 2 3)))
        (check-rows (query held 'scope_answer) '((0 3)))))))
