;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil-ascent/program/objects gerbil-ascent-program)
        (only-in :clan/poo/object .ref))
(export ascent-rule-module rule-module? rule-module-program
        rule-module-explain rule-module-bindings
        make-declared-program recorded-rule-explanation)

(defstruct rule-module (program explain bindings) final: #t)
(def (ascent-rule-module program (explain #f) (bindings []))
  (unless (or (not explain) (procedure? explain))
    (error "Evidence explanation must be a native procedure"))
  (unless (and (list? bindings) (andmap (lambda (b) (and (pair? b) (symbol? (car b)) (symbol? (cdr b)))) bindings))
    (error "Evidence bindings must pair public labels with native relation handles"))
  (make-rule-module program explain bindings))

(def (recorded-rule-explanation program result query scope)
  (hash ("status" "recorded-only") ("query" query) ("scope" scope)
        ("dependencies" (.ref program 'rules))
        ("gap" "Declaration dependencies and current source rows are not per-row proof or execution authority")))

;; Public labels are metadata, not a projection or an execution restriction.
;; Preserve the complete upstream Program, including opaque fields and callbacks.
(def (make-declared-program program sources outputs explain)
  (def (bindings values)
    (unless (and (list? values)
                 (andmap (lambda (value)
                           (and (pair? value) (symbol? (car value)) (symbol? (cdr value)))) values))
      (error "invalid Evidence relation bindings"))
    (let ((labels (make-hash-table-eq)) (handles (make-hash-table-eq)))
      (for-each (lambda (value)
        (when (or (hash-get labels (car value)) (hash-get handles (cdr value)))
          (error "duplicate Evidence relation binding" value))
        (hash-put! labels (car value) #t) (hash-put! handles (cdr value) #t)) values))
    values)
  (let* ((sources (bindings sources)) (outputs (bindings outputs))
         (names (map (cut .ref <> 'name) (.ref program 'relations)))
         (combined sources))
    (for-each (lambda (binding)
      (unless (memq (cdr binding) names)
        (error "Evidence binding does not name a declared relation" binding))
      (unless (member binding combined)
        (when (or (assq (car binding) combined)
                  (find (lambda (prior) (eq? (cdr prior) (cdr binding))) combined))
          (error "conflicting Evidence public relation binding" binding))
        (set! combined (append combined (list binding))))) outputs)
    (ascent-rule-module
      (gerbil-ascent-program (.ref program 'relations) (.ref program 'rules)
        (.ref program 'max-input-facts) (.ref program 'max-derived-facts)
        (.ref program 'max-output-facts) (map cdr sources))
      explain combined)))

