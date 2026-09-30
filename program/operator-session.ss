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
                 relational-session-replace-source!
                 relational-session-run relational-query))

(export relational-op-open-retained
        relational-op-retained? relational-op-retained-rows
        relational-op-retained-append! relational-op-retained-replace!)

(defstruct relational-op-retained
  (session fragment input-label output-label latest))

(def (row-difference left right)
  (filter (lambda (row) (not (member row right))) left))

(def (relational-op-retained-rows retained)
  (unless (relational-op-retained? retained)
    (error "expected a retained relational operator" retained))
  ;; relational-query returns copied row spines from a completed solution.
  (relational-query
   (relational-op-retained-latest retained)
   (relational-op-retained-fragment retained)
   (relational-op-retained-output-label retained)))

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
         (session (relational-open-session program))
         (first (relational-session-run session)))
    (make-relational-op-retained
     session fragment input-label output-label first)))

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
            (relational-query
             next (relational-op-retained-fragment retained)
             (relational-op-retained-output-label retained))))
      (set! (relational-op-retained-latest retained) next)
      (values before after (row-difference after before)))))

;;; Replacement may withdraw rows, so the native Session recomputes from
;;; its accepted source snapshot. Return both directions of the set change.
(def (relational-op-retained-replace! retained rows)
  (let (before (relational-op-retained-rows retained))
    (relational-session-replace-source!
     (relational-op-retained-session retained)
     (relational-op-retained-fragment retained)
     (relational-op-retained-input-label retained) rows)
    (let* ((next
            (relational-session-run
             (relational-op-retained-session retained)))
           (after
            (relational-query
             next (relational-op-retained-fragment retained)
             (relational-op-retained-output-label retained))))
      (set! (relational-op-retained-latest retained) next)
      (values before after
              (row-difference after before)
              (row-difference before after)))))
