;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :gerbil/compiler :std/make
 (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
;;; Local executables bind a conservative superset of their source closure.
;;; Independent application/proof work cannot invalidate this owned receipt.
;;; Canonical production-library admission remains the whole-workspace gate.
(def source-prefixes
  '("candidate/" "program/" "core/" "table/"
    "t/performance/candidate-flow/" "t/performance/stratified-model/"))
(def qualification-sources
  '("t/qualification/ascent-candidate-flow-test.ss"
    "t/qualification/ascent-candidate-description-test.ss"
    "t/qualification/ascent-reasoning-library-test.ss"
    "t/qualification/ascent-positive-nonmembership-test.ss"
    "t/qualification/ascent-stratified-proof-test.ss"
    "t/native/artifact-admission.ss"))
(def (flow-sources)
  (let (owned (make-hash-table))
    (for-each
     (lambda (entry)
       (let (path (car entry))
         (when (or (member path qualification-sources)
                   (ormap (lambda (prefix)
                            (and (>= (string-length path) (string-length prefix))
                                 (string=? prefix (substring path 0 (string-length prefix)))))
                          source-prefixes))
           (hash-put! owned path (cdr entry)))))
     (hash->list (artifact-sources)))
    owned))

(def (main library binary (lane "runner"))
 (unless (member lane '("runner" "qualify")) (error "unknown Candidate flow lane" lane))
 (let* ((sources (flow-sources)) (source (string-append "t/performance/candidate-flow/" lane ".ss")))
  (add-load-path! library)
  (make (append '("program/objects" "program/interface" "candidate/program" "candidate/reasoning"
    "t/performance/candidate-flow/reference-objects" "t/performance/candidate-flow/reference-program" "t/performance/candidate-flow/reference-reasoning"
    "t/performance/candidate-flow/fixture")
    (if (equal? lane "qualify")
     '("t/qualification/ascent-candidate-flow-test"
       "t/qualification/ascent-candidate-description-test"
       "t/qualification/ascent-reasoning-library-test"
       "t/qualification/ascent-positive-nonmembership-test"
       "t/qualification/ascent-stratified-proof-test") []) (list (path-strip-extension source)))
   srcdir: (current-directory) libdir: library build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
  (compile-exe source [output-dir: library output-file: binary parallel: #t verbose: #t invoke-gsc: #t static: #t])
  (execute-pending-compile-jobs!)
  (unless (artifact-matching-sources? sources (flow-sources)) (error "Candidate flow sources changed during compilation"))))
