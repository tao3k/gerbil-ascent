;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later


;;; Whole-program composition, admission diagnostics and one-shot solve state.
(import (only-in "objects.ss" gerbil-ascent-program)
        (only-in "types.ss" GerbilAscentFragmentContract)
        (only-in "scheme-snapshot.ss" relational-snapshot-program)
        (only-in "scheme-query.ss" make-relational-solution)
        (only-in "evaluate.ss" gerbil-ascent-make-engine)
        (only-in :clan/poo/object .ref)
        (only-in :clan/poo/mop validate)
        (only-in :std/error exception->string)
        (only-in :std/list/list append-map))
(export relational-compose relational-admit relational-admit/report relational-solve
        relational-admission-report? relational-admission-report-admission
        relational-admission-report-diagnostic relational-diagnostic?
        relational-diagnostic-code relational-diagnostic-path relational-diagnostic-detail)

(defstruct relational-admission (run))
(defstruct relational-diagnostic (code path detail))
(defstruct relational-admission-report (admission diagnostic))

;;; Composition is inert. Admission checks the assembled schema and rules
;;; later, after every fragment has contributed to the whole program.
;; relational-compose
;;   : (-> Fragments FactBudget FactBudget FactBudget Program)
;;   | doc m%
;;       Combine fragment declarations in order; planning and source admission follow later.
;;
;;       # Examples
;;
;;       ```scheme
;;       (relational-compose fragments 64 128 256)
;;       ;; => an assembled, unadmitted program
;;       ```
;;     %
(def (relational-compose fragments input-limit derived-limit output-limit)
  (for-each
   (lambda (fragment)
     (validate GerbilAscentFragmentContract fragment))
   fragments)
  (gerbil-ascent-program
   (append-map (lambda (fragment) (.ref fragment 'relations)) fragments)
   (append-map (lambda (fragment) (.ref fragment 'rules)) fragments)
   input-limit derived-limit output-limit
   (append-map (lambda (fragment) (.ref fragment 'source-handles))
               fragments)))

;;; Direct admission raises on invalid input, as do the low-level program
;;; constructors. A report caller may observe a planner path without
;;; duplicating the planner's binding and stratification rules.
;; relational-admit
;;   : (-> Program (Maybe PlanErrorObserver) Admission)
;;   | doc m%
;;       Snapshot and plan the checked program. The optional observer receives planner failures; no rules execute at this boundary.
;;
;;       # Examples
;;
;;       ```scheme
;;       (relational-admit program)
;;       ;; => a prepared one-shot admission, or a raised validation error
;;       ```
;;     %
(def (relational-admit program (on-plan-error #f))
  (let (snapshot (relational-snapshot-program program))
    (let ((run (gerbil-ascent-make-engine
                snapshot #f #f #f #f on-plan-error))
          (status 'ready)
          (complete-result #f))
      (make-relational-admission
       (lambda ()
         (case status
           ((complete) complete-result)
           ((failed) (error "relational solve previously failed"))
           ((running) (error "reentrant relational solve"))
           (else
            (set! status 'running)
            (with-catch
             (lambda (failure)
               (set! status 'failed)
               (raise failure))
             (lambda ()
               (let (result (run))
                 (unless (.ref result 'finished)
                   (error "relational solve did not complete"))
                 (set! complete-result result)
                 (set! status 'complete)
                 result))))))))))

;;; One typed result covers both admitted and rejected programs. The path is
;;; zero-based: (rule N body M), (rule N head M), or (program) when a failure
;;; occurs before rule planning. Detail is explanatory, never parsed as data.
;; relational-admit/report
;;   : (-> Program AdmissionReport)
;;   | doc m%
;;       Return either an admission or a typed diagnostic with the original zero-based planner path. A rejected report never contains runnable state.
;;
;;       # Examples
;;
;;       ```scheme
;;       (relational-admit/report program)
;;       ;; => an admission report with exactly one admission or diagnostic
;;       ```
;;     %
(def (relational-admit/report program)
  (let (path '(program))
    (with-catch
     (lambda (failure)
       (make-relational-admission-report
        #f
        (make-relational-diagnostic
         (cond
          ((and (pair? path) (eq? (car path) 'rule))
           (if (eq? (caddr path) 'body)
             'invalid-body 'invalid-head))
          ((equal? path '(program dependencies))
           'invalid-dependencies)
          (else 'invalid-program))
         path (exception->string failure))))
     (lambda ()
       (make-relational-admission-report
        (relational-admit
         program (lambda (location _failure) (set! path location)))
        #f)))))

;;; The prepared engine runs once. Successful repeats reuse its completed
;;; result; a failed run cannot expose or retry partially changed state.
;; relational-solve
;;   : (-> Admission Solution)
;;   | doc m%
;;       Complete a prepared admission. Successful repeats reuse its result; failed and reentrant execution remain rejected.
;;
;;       # Examples
;;
;;       ```scheme
;;       (relational-solve admission)
;;       ;; => a completed solution, or a raised execution error
;;       ```
;;     %
(def (relational-solve admission)
  (unless (relational-admission? admission)
    (error "relational solve requires admission" admission))
  (make-relational-solution
   ((relational-admission-run admission))))
