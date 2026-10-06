;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; A first-class relation transformer admitted once into the retained
;;; native Session. The input is the only source this facade may change;
;;; other sources captured by the transformer remain fixed here.
(import (only-in "operator.ss"
                 relational-op-source relational-op-apply
                 relational-op-fragment relational-transform?
                 relational-transform-input-arity)
        (only-in "scheme-admission.ss"
                 relational-compose relational-open-session
                 relational-session-append-source!
                 relational-session-replace-sources!
                 relational-session-run relational-prepare-query))

(export relational-op-open-retained
        relational-op-retained? relational-op-retained-rows
        relational-op-retained-input-label
        relational-op-retained-append! relational-op-retained-replace!
        relational-op-retained-replace-sources!)

(defstruct relational-op-retained
  (session fragment input-label output-label read-output latest))

(def (row-difference left right)
  (filter (lambda (row) (not (member row right))) left))

(def (relational-op-retained-rows retained)
  (unless (relational-op-retained? retained)
    (error "expected a retained relational operator" retained))
  ;; The prepared reader returns copied row spines from this completed solution.
  ((relational-op-retained-read-output retained)
   (relational-op-retained-latest retained)))

;; relational-op-open-retained
;;   : (-> RelationalTransform Rows Nat Nat Nat RelationalOpRetained)
;;   | doc m%
;;       Build and admit one transformer instance against a checked source.
;;       The initial solve completes before a source update is accepted.
;;       Its private source and output labels cannot collide with captured
;;       sources or another transformer instance.
;;
;;       # Examples
;;
;;       ```scheme
;;       (def retained
;;         (relational-op-open-retained closure '((1 2)) 16 64 128))
;;       (relational-op-retained-rows retained)
;;       ;; => ((1 2)) for a transitive closure transformer
;;       ```
;;     %
(def (relational-op-open-retained transformer rows
                                  input-limit derived-limit output-limit)
  (unless (relational-transform? transformer)
    (error "expected a relation transformer" transformer))
  (let* ((input-label (gensym 'input))
         (output-label (gensym 'result))
         (input
          (relational-op-source
           input-label (relational-transform-input-arity transformer) rows))
         (fragment
          (relational-op-fragment
           (relational-op-apply transformer input) output-label))
         (program
          (relational-compose (list fragment)
                              input-limit derived-limit output-limit))
         (read-output (relational-prepare-query fragment output-label))
         (session (relational-open-session program))
         (first (relational-session-run session)))
    (make-relational-op-retained
     session fragment input-label output-label read-output first)))

;;; An append publishes only a completed result. If admission or the run
;;; fails, the underlying Session restores its last committed input; the
;;; facade still points at its last completed solution. A duplicate row
;;; may consume input budget but produces an empty output delta.
(def (relational-op-retained-append! retained row)
  (let (before (relational-op-retained-rows retained))
    (relational-session-append-source!
     (relational-op-retained-session retained)
     (relational-op-retained-fragment retained)
     (relational-op-retained-input-label retained) row)
    (let* ((next
            (relational-session-run
             (relational-op-retained-session retained)))
           (after
            ((relational-op-retained-read-output retained) next)))
      (set! (relational-op-retained-latest retained) next)
      (values before after (row-difference after before)))))

;;; Replace any subset of exported graph sources in one completed solve.
;;; Each entry is (source-label . checked-rows). The Session commits the
;;; entire prospective snapshot only after its native run succeeds.
(def (relational-op-retained-replace-sources! retained replacements)
  (unless (relational-op-retained? retained)
    (error "expected a retained relational operator" retained))
  (let (before (relational-op-retained-rows retained))
    (let (next
          (relational-session-replace-sources!
           (relational-op-retained-session retained)
           (relational-op-retained-fragment retained)
           replacements))
      (let (after
            ((relational-op-retained-read-output retained) next))
        (set! (relational-op-retained-latest retained) next)
        (values before after
                (row-difference after before)
                (row-difference before after))))))

;;; The single-input replacement is the one-source form of the same
;;; transaction, including withdrawal and failure recovery.
(def (relational-op-retained-replace! retained rows)
  (relational-op-retained-replace-sources!
   retained
   (list (cons (relational-op-retained-input-label retained) rows))))
