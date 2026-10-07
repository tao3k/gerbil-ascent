;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; The same expression is quoted for source export and compiled for execution.
;;; Private expected data is never included in a model input.
(import :std/test :std/encoding/json
        :gerbil-ascent/program/higher-order :gerbil-ascent/program/scheme-language
        :gerbil-ascent/program/session :gerbil-ascent/candidate/reasoning
        :gerbil-ascent/candidate/program :gerbil-ascent/candidate/finite-evidence
        :gerbil-ascent/candidate/stratified-provenance
        (only-in :clan/poo/object .ref)
        (only-in :std/list/list find take)
        (only-in :std/test/base TestCase test-case-add!))
(import (only-in "../model/response-projection" read-prediction project-prediction))
(export scheme-model-closure-test model-closure-compute model-closure-score)
(defsyntax (study-case stx)
  (syntax-case stx ()
    ((_ family variant expression expected)
     (syntax (list 'family 'variant 'expression expected (lambda () expression))))))
(def (datum-text value) (call-with-output-string "" (lambda (port) (write value port))))
(def (case-id record) (string-append (symbol->string (car record)) "-" (symbol->string (cadr record))))
(def (case-value record) ((list-ref record 4)))
(def (case-imports record)
  (cond
   ((memq (car record) '(higher-input higher-return higher-instances finite-mapping finite-fix domain-runtime))
    '(:gerbil-ascent/program/higher-order :gerbil-ascent/program/scheme-language))
   ((memq (car record) '(retained-delete retained-negation retained-reduction retained-lattice))
    '(:gerbil-ascent/program/scheme-language :gerbil-ascent/program/session :clan/poo/object))
   (else '(:gerbil-ascent/candidate/reasoning :gerbil-ascent/candidate/program
           :gerbil-ascent/candidate/finite-evidence :gerbil-ascent/candidate/stratified-provenance))))
(def cases
  (list
    (study-case higher-input initial
      (let* ((r (relational-relation-type 1 '(0 1 2 3 4)))
             (apply-function (relational-typed-function (relational-arrow-type r r)
               (lambda (f) (relational-typed-function r (lambda (x) (relational-typed-apply f x))))))
             (f (relational-typed-function r
                  (lambda (x) (relational-typed-flatmap x r '(((0) (1)))))))
             (input (relational-typed-source 'input r '((0))))
             (solve (lambda (term)
             (let-values (((program output) (relational-typed-compile term 32 256 512)))
               (relational-query-name (relational-solve (relational-admit program)) output)))) (bits (lambda (rows) (foldl (lambda (row mask) (+ mask (expt 2 (car row)))) 0 rows))))
        (bits (solve (relational-typed-apply (relational-typed-apply apply-function f) input))))
      2)
    (study-case higher-return initial
      (let* ((r (relational-relation-type 1 '(0 1 2 3 4)))
             (builder (relational-typed-function r
               (lambda (seed) (relational-typed-function r (lambda (input) (relational-typed-union seed input))))))
             (function (relational-typed-apply builder (relational-typed-source 'seed r '((0)))))
             (argument (relational-typed-source 'argument r '((1))))
             (solve (lambda (term)
             (let-values (((program output) (relational-typed-compile term 32 256 512)))
               (relational-query-name (relational-solve (relational-admit program)) output)))) (bits (lambda (rows) (foldl (lambda (row mask) (+ mask (expt 2 (car row)))) 0 rows))))
        (bits (solve (relational-typed-apply function argument))))
      3)
    (study-case higher-instances initial
      (let* ((r (relational-relation-type 1 '(0 1 2 3 4)))
             (builder (relational-typed-function r
               (lambda (seed) (relational-typed-function r (lambda (input) (relational-typed-union seed input))))))
             (function (relational-typed-apply builder (relational-typed-source 'seed r '((0)))))
             (a (relational-typed-source 'a r '((1)))) (b (relational-typed-source 'b r '((2))))
             (solve (lambda (term)
             (let-values (((program output) (relational-typed-compile term 32 256 512)))
               (relational-query-name (relational-solve (relational-admit program)) output)))) (bits (lambda (rows) (foldl (lambda (row mask) (+ mask (expt 2 (car row)))) 0 rows))))
        (list (bits (solve (relational-typed-apply function a)))
              (bits (solve (relational-typed-apply function b)))))
      '(3 5))
    (study-case finite-mapping initial
      (let* ((r (relational-relation-type 1 '(0 1 2 3 4)))
             (source (relational-typed-source 'input r '((0))))
             (mapped (relational-typed-flatmap source r '(((0) (1)) ((0) (2)))))
             (solve (lambda (term)
             (let-values (((program output) (relational-typed-compile term 32 256 512)))
               (relational-query-name (relational-solve (relational-admit program)) output)))) (bits (lambda (rows) (foldl (lambda (row mask) (+ mask (expt 2 (car row)))) 0 rows))))
        (bits (solve mapped)))
      6)
    (study-case finite-fix initial
      (let* ((r (relational-relation-type 1 '(0 1)))
             (seed (relational-typed-source 'seed r '((0))))
             (function (relational-typed-function (relational-arrow-type r r)
               (lambda (self) (relational-typed-function r
                 (lambda (input) (relational-typed-union input
                   (relational-typed-apply self
                     (relational-typed-flatmap input r '(((0) (1)) ((1) (0)))))))))))
             (solve (lambda (term)
             (let-values (((program output) (relational-typed-compile term 32 256 512)))
               (relational-query-name (relational-solve (relational-admit program)) output)))))
        (foldl (lambda (row mask) (+ mask (expt 2 (car row)))) 0
               (solve (relational-typed-apply (relational-typed-fix function) seed))))
      3)
    (study-case domain-runtime initial
      (let-values (((program output) (relational-typed-compile
                      (relational-typed-source 'input (relational-relation-type 1 '(0 1)) '((0))) 32 256 512)))
        (let (session (relational-open-program-session program))
          (relational-program-session-run session)
          (with-catch (lambda (_error) 1)
            (lambda () (relational-program-append-source! session 'input '(2)) 0))))
      1)
    (study-case retained-delete initial
      (let* ((program (relational-program
                        (relation edge (from to) '((0 1) (1 2))) (relation path (from to) '())
                        (relation cold (n) '((7))) (relation seen (n) '())
                        (rule (path ?x ?y) (edge ?x ?y))
                        (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
                        (rule (seen ?n) (cold ?n)) (limits 32 256 512)))
             (session (gerbil-ascent-open-session program)))
        (gerbil-ascent-session-run session)
        (let (result (gerbil-ascent-session-replace-sources! session (list (cons 'edge '((0 1))))))
          (list (length ((.ref result 'rows-of) 'path)) (.ref result 'active-rule-count)
                (length (.ref result 'reused-relations)))))
      '(1 2 2))
    (study-case retained-negation initial
      (let* ((program (relational-program
                        (relation item (n) '((1) (2))) (relation blocked (n) '((1)))
                        (relation allowed (n) '())
                        (rule (allowed ?n) (item ?n) (not (blocked ?n))) (limits 32 256 512)))
             (session (gerbil-ascent-open-session program))
             (old (gerbil-ascent-session-run session)))
        (gerbil-ascent-session-replace-source! session 'blocked '())
        (let (new (gerbil-ascent-session-run session))
          (list (length ((.ref old 'rows-of) 'allowed)) (length ((.ref new 'rows-of) 'allowed)))))
      '(1 2))
    (study-case retained-reduction initial
      (let* ((program (relational-program
                        (relation weight (key value) '((1 2) (1 5))) (relation root (key) '((1)))
                        (relation total (key value) '())
                        (rule (total ?k ?n) (root ?k) (reduce ?n (sum ?v) (weight ?k ?v)))
                        (limits 32 256 512)))
             (session (gerbil-ascent-open-session program))
             (old (gerbil-ascent-session-run session)))
        (gerbil-ascent-session-replace-source! session 'weight '((1 2)))
        (let (new (gerbil-ascent-session-run session))
          (list (cadar ((.ref old 'rows-of) 'total)) (cadar ((.ref new 'rows-of) 'total)))))
      '(7 2))
    (study-case retained-lattice initial
      (let* ((program (relational-program
                        (relation input (key value) '((1 2) (1 5))) (lattice best (key value) '() max)
                        (rule (best ?k ?v) (input ?k ?v)) (limits 32 256 512)))
             (session (gerbil-ascent-open-session program))
             (old (gerbil-ascent-session-run session)))
        (gerbil-ascent-session-replace-source! session 'input '((1 2)))
        (let (new (gerbil-ascent-session-run session))
          (list (cadar ((.ref old 'rows-of) 'best)) (cadar ((.ref new 'rows-of) 'best)))))
      '(5 2))
    (study-case recursive-provenance initial
      (let* ((snapshot (reasoning-source-snapshot 'recursive 1 '((s 1 ((1) (1))))))
             (datum '(candidate (relation p 1) (rule (p ?x) (s ?x)) (rule (p ?x) (p ?x))
                                (query p ?x) (limits 16 64 128)))
             (receipt (reasoning-attempt snapshot datum)) (spec (candidate-inspect snapshot datum))
             (digest (reasoning-receipt-candidate-digest receipt)) (rows (reasoning-receipt-rows receipt))
             (certificate (candidate-finite-evidence snapshot spec digest 'complete rows 20000))
             (graph (candidate-stratified-provenance snapshot spec digest 'complete rows certificate 20000 20000 4096)))
        (list (length (stratified-provenance-nodes graph)) (length (stratified-provenance-edges graph))
              (length (stratified-provenance-roots graph))))
      '(2 4 1))
    (study-case stratified-provenance initial
      (let* ((snapshot (reasoning-source-snapshot 'stratified 1
                         '((weight 2 ((1 2) (1 5))) (root 1 ((1))) (blocked 2 ((1 5))))))
             (datum '(candidate (relation allowed 2) (relation total 2)
                      (rule (allowed ?k ?v) (weight ?k ?v) (not (blocked ?k ?v)))
                      (rule (total ?k ?n) (root ?k) (reduce ?n (sum ?v) (allowed ?k ?v)))
                      (query total ?k ?n) (limits 16 64 128)))
             (receipt (reasoning-attempt snapshot datum)) (spec (candidate-inspect snapshot datum))
             (digest (reasoning-receipt-candidate-digest receipt)) (rows (reasoning-receipt-rows receipt))
             (certificate (candidate-finite-evidence snapshot spec digest 'complete rows 20000))
             (graph (candidate-stratified-provenance snapshot spec digest 'complete rows certificate 20000 20000 4096)))
        (list (cadar rows) (length (stratified-provenance-edges graph))
              (length (filter (lambda (edge) (ormap (lambda (witness) (eq? (car witness) 'not)) (list-ref edge 3)))
                              (stratified-provenance-edges graph)))))
      '(2 6 1))
    (study-case higher-input transfer
      (let* ((r (relational-relation-type 1 '(0 1 2 3 4)))
             (apply-function (relational-typed-function (relational-arrow-type r r)
               (lambda (f) (relational-typed-function r (lambda (x) (relational-typed-apply f x))))))
             (f (relational-typed-function r
                  (lambda (x) (relational-typed-flatmap x r '(((1) (2)))))))
             (input (relational-typed-source 'input r '((1))))
             (solve (lambda (term)
             (let-values (((program output) (relational-typed-compile term 32 256 512)))
               (relational-query-name (relational-solve (relational-admit program)) output)))) (bits (lambda (rows) (foldl (lambda (row mask) (+ mask (expt 2 (car row)))) 0 rows))))
        (bits (solve (relational-typed-apply (relational-typed-apply apply-function f) input))))
      4)
    (study-case higher-return transfer
      (let* ((r (relational-relation-type 1 '(0 1 2 3 4)))
             (builder (relational-typed-function r
               (lambda (seed) (relational-typed-function r (lambda (input) (relational-typed-union seed input))))))
             (function (relational-typed-apply builder (relational-typed-source 'seed r '((1)))))
             (argument (relational-typed-source 'argument r '((2))))
             (solve (lambda (term)
             (let-values (((program output) (relational-typed-compile term 32 256 512)))
               (relational-query-name (relational-solve (relational-admit program)) output)))) (bits (lambda (rows) (foldl (lambda (row mask) (+ mask (expt 2 (car row)))) 0 rows))))
        (bits (solve (relational-typed-apply function argument))))
      6)
    (study-case higher-instances transfer
      (let* ((r (relational-relation-type 1 '(0 1 2 3 4)))
             (builder (relational-typed-function r
               (lambda (seed) (relational-typed-function r (lambda (input) (relational-typed-union seed input))))))
             (function (relational-typed-apply builder (relational-typed-source 'seed r '((1)))))
             (a (relational-typed-source 'a r '((2)))) (b (relational-typed-source 'b r '((3))))
             (solve (lambda (term)
             (let-values (((program output) (relational-typed-compile term 32 256 512)))
               (relational-query-name (relational-solve (relational-admit program)) output)))) (bits (lambda (rows) (foldl (lambda (row mask) (+ mask (expt 2 (car row)))) 0 rows))))
        (list (bits (solve (relational-typed-apply function a)))
              (bits (solve (relational-typed-apply function b)))))
      '(6 10))
    (study-case finite-mapping transfer
      (let* ((r (relational-relation-type 1 '(0 1 2 3 4)))
             (source (relational-typed-source 'input r '((2))))
             (mapped (relational-typed-flatmap source r '(((2) (3)) ((2) (4)))))
             (solve (lambda (term)
             (let-values (((program output) (relational-typed-compile term 32 256 512)))
               (relational-query-name (relational-solve (relational-admit program)) output)))) (bits (lambda (rows) (foldl (lambda (row mask) (+ mask (expt 2 (car row)))) 0 rows))))
        (bits (solve mapped)))
      24)
    (study-case finite-fix transfer
      (let* ((r (relational-relation-type 1 '(0 1)))
             (seed (relational-typed-source 'seed r '((0))))
             (function (relational-typed-function (relational-arrow-type r r)
               (lambda (self) (relational-typed-function r
                 (lambda (input) (relational-typed-union input
                   (relational-typed-apply self
                     (relational-typed-flatmap input r '(((1) (0)))))))))))
             (solve (lambda (term)
             (let-values (((program output) (relational-typed-compile term 32 256 512)))
               (relational-query-name (relational-solve (relational-admit program)) output)))))
        (foldl (lambda (row mask) (+ mask (expt 2 (car row)))) 0
               (solve (relational-typed-apply (relational-typed-fix function) seed))))
      1)
    (study-case domain-runtime transfer
      (let-values (((program output) (relational-typed-compile
                      (relational-typed-source 'input (relational-relation-type 1 '(0 1)) '((0))) 32 256 512)))
        (let (session (relational-open-program-session program))
          (relational-program-session-run session)
          (with-catch (lambda (_error) 1)
            (lambda () (relational-program-append-source! session 'input '(1)) 0))))
      0)
    (study-case retained-delete transfer
      (let* ((program (relational-program
                        (relation edge (from to) '((0 1) (1 2))) (relation path (from to) '())
                        (relation cold (n) '((7))) (relation seen (n) '())
                        (rule (path ?x ?y) (edge ?x ?y))
                        (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
                        (rule (seen ?n) (cold ?n)) (limits 32 256 512)))
             (session (gerbil-ascent-open-session program)))
        (gerbil-ascent-session-run session)
        (let (result (gerbil-ascent-session-replace-sources! session (list (cons 'edge '()))))
          (list (length ((.ref result 'rows-of) 'path)) (.ref result 'active-rule-count)
                (length (.ref result 'reused-relations)))))
      '(0 2 2))
    (study-case retained-negation transfer
      (let* ((program (relational-program
                        (relation item (n) '((1) (2))) (relation blocked (n) '())
                        (relation allowed (n) '())
                        (rule (allowed ?n) (item ?n) (not (blocked ?n))) (limits 32 256 512)))
             (session (gerbil-ascent-open-session program))
             (old (gerbil-ascent-session-run session)))
        (gerbil-ascent-session-replace-source! session 'blocked '((2)))
        (let (new (gerbil-ascent-session-run session))
          (list (length ((.ref old 'rows-of) 'allowed)) (length ((.ref new 'rows-of) 'allowed)))))
      '(2 1))
    (study-case retained-reduction transfer
      (let* ((program (relational-program
                        (relation weight (key value) '((1 2) (1 5))) (relation root (key) '((1)))
                        (relation total (key value) '())
                        (rule (total ?k ?n) (root ?k) (reduce ?n (sum ?v) (weight ?k ?v)))
                        (limits 32 256 512)))
             (session (gerbil-ascent-open-session program))
             (old (gerbil-ascent-session-run session)))
        (gerbil-ascent-session-replace-source! session 'weight '((1 5)))
        (let (new (gerbil-ascent-session-run session))
          (list (cadar ((.ref old 'rows-of) 'total)) (cadar ((.ref new 'rows-of) 'total)))))
      '(7 5))
    (study-case retained-lattice transfer
      (let* ((program (relational-program
                        (relation input (key value) '((1 2) (1 5))) (lattice best (key value) '() max)
                        (rule (best ?k ?v) (input ?k ?v)) (limits 32 256 512)))
             (session (gerbil-ascent-open-session program))
             (old (gerbil-ascent-session-run session)))
        (gerbil-ascent-session-replace-source! session 'input '((1 5) (1 9)))
        (let (new (gerbil-ascent-session-run session))
          (list (cadar ((.ref old 'rows-of) 'best)) (cadar ((.ref new 'rows-of) 'best)))))
      '(5 9))
    (study-case recursive-provenance transfer
      (let* ((snapshot (reasoning-source-snapshot 'recursive 2 '((s 1 ((1) (1) (1))))))
             (datum '(candidate (relation p 1) (rule (p ?x) (s ?x)) (rule (p ?x) (p ?x))
                                (query p ?x) (limits 16 64 128)))
             (receipt (reasoning-attempt snapshot datum)) (spec (candidate-inspect snapshot datum))
             (digest (reasoning-receipt-candidate-digest receipt)) (rows (reasoning-receipt-rows receipt))
             (certificate (candidate-finite-evidence snapshot spec digest 'complete rows 20000))
             (graph (candidate-stratified-provenance snapshot spec digest 'complete rows certificate 20000 20000 4096)))
        (list (length (stratified-provenance-nodes graph)) (length (stratified-provenance-edges graph))
              (length (stratified-provenance-roots graph))))
      '(2 5 1))
    (study-case stratified-provenance transfer
      (let* ((snapshot (reasoning-source-snapshot 'stratified 2
                         '((weight 2 ((1 2) (1 5))) (root 1 ((1))) (blocked 2 ()))))
             (datum '(candidate (relation allowed 2) (relation total 2)
                      (rule (allowed ?k ?v) (weight ?k ?v) (not (blocked ?k ?v)))
                      (rule (total ?k ?n) (root ?k) (reduce ?n (sum ?v) (allowed ?k ?v)))
                      (query total ?k ?n) (limits 16 64 128)))
             (receipt (reasoning-attempt snapshot datum)) (spec (candidate-inspect snapshot datum))
             (digest (reasoning-receipt-candidate-digest receipt)) (rows (reasoning-receipt-rows receipt))
             (certificate (candidate-finite-evidence snapshot spec digest 'complete rows 20000))
             (graph (candidate-stratified-provenance snapshot spec digest 'complete rows certificate 20000 20000 4096)))
        (list (cadar rows) (length (stratified-provenance-edges graph))
              (length (filter (lambda (edge) (ormap (lambda (witness) (eq? (car witness) 'not)) (list-ref edge 3)))
                              (stratified-provenance-edges graph)))))
      '(7 6 2))
))

(def scheme-model-closure-test
  (test-suite "Native preflight for source-only model closure tasks"
    (test-case "native response literals and assertions remain inert"
      (for-each (lambda (text) (check-equal? (project-prediction text) text))
                '("2" "'2" "(check-equal? result 2)" "(check-equal? result '(1 2 2))"))
      (check-equal? (project-prediction "(check-equal? result (+ 1 2))") #f)
      (check-equal? (project-prediction "(check-equal? result '?)") #f))
    (test-case "native response projection rejects conflicting explicit data"
      (check-equal? (project-prediction "(check-equal? result '2)\n```scheme\n'3\n```") #f)
      (check-equal? (project-prediction "(check-equal? result '2)\n```scheme\n'2\n```") "(check-equal? result '2)"))
    (test-case "native response projection enforces byte and nesting limits"
      (check-equal? (project-prediction (make-string 65537 #\x)) #f)
      (check-equal? (project-prediction (string-append (make-string 65 #\() "2" (make-string 65 #\)))) #f))
    (for-each (lambda (record)
      (test-case-add! (TestCase (case-id record) (lambda ()
        (let (actual (case-value record))
          (check-equal? actual (list-ref record 3))
          (displayln "STUDY-CASE "
            (json->string (hash ("id" (case-id record))
                                ("family" (symbol->string (car record)))
                                ("variant" (symbol->string (cadr record)))
                                ("imports" (map symbol->string (case-imports record)))
                                ("expression" (datum-text (caddr record)))
                                ("nativeDatum" (datum-text actual))
                                ("independentDatum" (datum-text (list-ref record 3))))))
          (force-output)))))) cases)))
(def (find-case id)
  (or (find (lambda (record) (string=? id (case-id record))) cases)
      (error "unknown frozen model case" id)))
(def (model-closure-compute id)
  (displayln "MODULE-OK Scheme model compute") (force-output)
  (displayln "NATIVE-DATUM " (datum-text (case-value (find-case id))))
  (displayln "HARNESS-OK Scheme model compute") (displayln "OK") (force-output))

(def (model-closure-score id path)
  (displayln "MODULE-OK Scheme model score") (force-output)
  (let* ((actual (case-value (find-case id))) (prediction (read-prediction path))
         (readable (vector-ref prediction 0))
         (correct (and readable (equal? actual (vector-ref prediction 1)))))
    (displayln "NATIVE-SCORE " (json->string (hash ("readable" readable) ("correct" correct)
                                                   ("nativeDatum" (datum-text actual)))))
    (displayln "HARNESS-OK Scheme model score") (displayln "OK") (force-output)))
