;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import "objects.ss" "scheme-checked.ss"
        (only-in "types.ss" GerbilAscentFragmentContract
                 GerbilAscentProgramContract)
        (only-in "evaluate.ss" gerbil-ascent-make-engine)
        (only-in "session.ss" gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-replace-source!
                 gerbil-ascent-session-replace-sources!
                 gerbil-ascent-session-run)
        (only-in :clan/poo/object .ref)
        (only-in :clan/poo/mop validate)
        (only-in :std/error exception->string)
        (only-in :std/list/list append-map find))

(export relational-export relational-compose relational-admit
        relational-admit/report
        relational-admission-report? relational-admission-report-admission
        relational-admission-report-diagnostic
        relational-diagnostic? relational-diagnostic-code
        relational-diagnostic-path relational-diagnostic-detail
        relational-solve relational-query relational-query-name
        relational-open-session relational-session-append-source!
        relational-session-replace-source!
        relational-session-replace-sources!
        relational-session-run relational-open-program-session
        relational-program-append-source!
        relational-program-replace-source!
        relational-program-session-run relational-program-query)

(defstruct relational-admission (run))
(defstruct relational-diagnostic (code path detail))
(defstruct relational-admission-report (admission diagnostic))
(defstruct relational-solution (result))
(defstruct relational-session (engine source-arities))
(defstruct relational-program-session (engine source-arities))
(defstruct relational-program-solution (result))

;;; Completed results own their relation snapshots. Public queries copy the
;;; row spines so a caller cannot mutate a later query through an old answer.
(def (relational-result-rows result name)
  (unless (.ref result 'finished)
    (error "relational query requires a completed result"))
  (map (lambda (row) (map identity row))
       ((.ref result 'rows-of) name)))

;;; A public label is scoped to its fragment instance, rather than to the
;;; process or composed program. Only declared labels can reveal a handle.
(def (relational-export fragment label)
  (validate GerbilAscentFragmentContract fragment)
  ((.ref fragment 'exports) label))

;;; A query observes only a completed result and a handle exported by the
;;; supplied fragment. Copy returned rows so callers cannot edit the snapshot.
(def (relational-query solution fragment label)
  (unless (relational-solution? solution)
    (error "relational query requires a solved value" solution))
  (let (result (relational-solution-result solution))
    (relational-result-rows result (relational-export fragment label))))

;;; Named one-shot programs may contain private derived relations, so they
;;; cannot use the retained session API, which requires every relation to be
;;; source-capable. Query the completed admitted result directly.
(def (relational-query-name solution name)
  (unless (and (relational-solution? solution) (symbol? name))
    (error "relational named query requires a solved value" name))
  (let (result (relational-solution-result solution))
    (relational-result-rows result name)))

(def (relational-program-query solution name)
  (unless (and (relational-program-solution? solution) (symbol? name))
    (error "relational program query requires a named solution" name))
  (let (result (relational-program-solution-result solution))
    (relational-result-rows result name)))

;;; Composition is inert. Admission checks the assembled schema and rules
;;; later, after every fragment has contributed to the whole program.
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

;;; Admission rebuilds only the checked positive grammar. This removes
;;; caller-owned row/rule lists before planning and rejects old host callbacks.
(def (relational-copy-term term)
  (case (.ref term 'kind)
    ((variable) (gerbil-ascent-variable (.ref term 'value)))
    ((wildcard) (gerbil-ascent-wildcard))
    ((literal)
     (let (value (.ref term 'value))
       (unless (relational-scalar? value)
         (error "non-scalar relational literal" value))
       (gerbil-ascent-literal value)))
    (else (error "unsupported relational term" (.ref term 'kind)))))

(def (relational-copy-atom atom)
  (unless (eq? (.ref atom 'ascent-clause-kind) 'atom)
    (error "unsupported relational clause"))
  (gerbil-ascent-atom
   (.ref atom 'relation)
   (map relational-copy-term (.ref atom 'terms))))

;;; Rebuild from the descriptor, never from the callback stored for the old
;;; evaluator. An unmarked guard or binding cannot cross admission.
(def (relational-copy-clause clause)
  (case (.ref clause 'ascent-clause-kind)
    ((atom) (relational-copy-atom clause))
    ((negation)
     (gerbil-ascent-negation
      (.ref clause 'relation)
      (map relational-copy-term (.ref clause 'terms))))
    ((aggregate)
     (let ((descriptor (.ref clause 'checked-operator))
           (terms (.ref clause 'terms)))
       (unless (and (vector? descriptor)
                    (= (vector-length descriptor) 6)
                    (eq? (vector-ref descriptor 0) 'reduce)
                    (eq? (vector-ref descriptor 2)
                         (.ref clause 'variable))
                    (eq? (vector-ref descriptor 3)
                         (.ref clause 'relation))
                    (equal? (vector-ref descriptor 4)
                            (.ref clause 'variables))
                    (equal? (vector-ref descriptor 5)
                            (relational-term-fingerprint terms))
                    (not (.ref clause 'output-pattern)))
         (error "untrusted relational reduction"))
       (relational-reducer
        (vector-ref descriptor 2) (vector-ref descriptor 1)
        (vector-ref descriptor 4) (vector-ref descriptor 3)
        (map relational-copy-term terms))))
    ((guard)
     (let (descriptor (.ref clause 'checked-operator))
       (unless (and (vector? descriptor)
                    (= (vector-length descriptor) 3)
                    (eq? (vector-ref descriptor 0) 'where)
                    (equal? (vector-ref descriptor 2)
                            (.ref clause 'variables)))
         (error "untrusted relational filter"))
       (relational-where (vector-ref descriptor 1)
                         (vector-ref descriptor 2))))
    ((binding)
     (let (descriptor (.ref clause 'checked-operator))
       (unless (and (vector? descriptor)
                    (= (vector-length descriptor) 4)
                    (eq? (vector-ref descriptor 0) 'compute)
                    (equal? (vector-ref descriptor 2)
                            (.ref clause 'variables))
                    (eq? (vector-ref descriptor 3)
                         (.ref clause 'variable)))
         (error "untrusted relational projection"))
       (relational-compute (vector-ref descriptor 3)
                            (vector-ref descriptor 1)
                            (vector-ref descriptor 2))))
    (else (error "unsupported relational clause"
                 (.ref clause 'ascent-clause-kind)))))

(def (relational-copy-rule rule)
  (gerbil-ascent-rule
   (map relational-copy-atom (.ref rule 'heads))
   (map relational-copy-clause (.ref rule 'body))))

;;; The engine constructor checks relation names, arities, rule bindings,
;;; dependencies and budgets before the admission value becomes observable.
(def (relational-snapshot-program program)
  (validate GerbilAscentProgramContract program)
  (gerbil-ascent-program
   (map (lambda (relation)
          (case (.ref relation 'storage-kind)
            ((relation)
             (relational-source
              (.ref relation 'name)
              (.ref relation 'arity)
              (relational-copy-rows
               (.ref relation 'rows) (.ref relation 'arity))))
            ((lattice)
             (let (descriptor (.ref relation 'checked-operator))
               (unless (and (vector? descriptor)
                            (= (vector-length descriptor) 2)
                            (eq? (vector-ref descriptor 0) 'lattice))
                 (error "untrusted relational lattice"))
               (relational-checked-lattice
                (.ref relation 'name)
                (.ref relation 'arity)
                (.ref relation 'rows)
                (vector-ref descriptor 1))))
            (else (error "unsupported relational storage kind"))))
        (.ref program 'relations))
   (map relational-copy-rule (.ref program 'rules))
   (.ref program 'max-input-facts)
   (.ref program 'max-derived-facts)
   (.ref program 'max-output-facts)
   (.ref program 'source-handles)))

;;; Direct admission raises on invalid input, as do the low-level program
;;; constructors. A report caller may observe a planner path without
;;; duplicating the planner's binding and stratification rules.
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
(def (relational-solve admission)
  (unless (relational-admission? admission)
    (error "relational solve requires admission" admission))
  (make-relational-solution
   ((relational-admission-run admission))))

;;; Retained sessions accept replacements only through exported source
;;; handles. The old session owns rollback after an update or solve fails.
(def (relational-source-arities snapshot)
  (let (sources (.ref snapshot 'source-handles))
    (map (lambda (name)
           (let (relation
                 (find (lambda (candidate)
                         (eq? (.ref candidate 'name) name))
                       (.ref snapshot 'relations)))
             (unless relation
               (error "relational source has no declaration" name))
             (cons name (.ref relation 'arity))))
         sources)))

(def (relational-open-session program)
  (let* ((snapshot (relational-snapshot-program program))
         (arities (relational-source-arities snapshot)))
    (make-relational-session
     (gerbil-ascent-open-session snapshot)
     arities)))

(def (relational-open-program-session program)
  (let* ((snapshot (relational-snapshot-program program))
         (relations (.ref snapshot 'relations))
         (arities (relational-source-arities snapshot)))
    (unless (= (length relations) (length arities))
      (error "named program session requires source-capable relations"))
    (make-relational-program-session
     (gerbil-ascent-open-session snapshot)
     arities)))

(def (relational-replace-source/checked! engine arities name rows)
  (let (arity (and (symbol? name) (assq name arities)))
    (unless arity
      (error "relation is not a source in this session" name))
    (let (copied (relational-copy-rows rows (cdr arity)))
      (relational-source name (cdr arity) copied)
      (gerbil-ascent-session-replace-source! engine name copied)
      (void))))

;;; Insert one checked source row into the retained positive session. The
;;; underlying session decides whether its admitted plan can reuse deltas;
;;; a caller still observes results only after a completed run.
(def (relational-append-source/checked! engine arities name row)
  (let (arity (and (symbol? name) (assq name arities)))
    (unless arity
      (error "relation is not a source in this session" name))
    (let (copied (car (relational-copy-rows (list row) (cdr arity))))
      (relational-source name (cdr arity) (list copied))
      (gerbil-ascent-session-append-source! engine name copied)
      (void))))

(def (relational-session-append-source! session fragment label row)
  (unless (relational-session? session)
    (error "relational source append requires a session" session))
  (validate GerbilAscentFragmentContract fragment)
  (let* ((name (relational-export fragment label))
         (arity (assq name (relational-session-source-arities session))))
    (unless (and (memq name (.ref fragment 'source-handles)) arity)
      (error "relational export is not a source in this session" label))
    (relational-append-source/checked!
     (relational-session-engine session)
     (relational-session-source-arities session) name row)))

(def (relational-session-replace-source! session fragment label rows)
  (unless (relational-session? session)
    (error "relational source replacement requires a session" session))
  (validate GerbilAscentFragmentContract fragment)
  (let* ((name (relational-export fragment label))
         (arity (assq name (relational-session-source-arities session))))
    (unless (and (memq name (.ref fragment 'source-handles)) arity)
      (error "relational export is not a source in this session" label))
    (relational-replace-source/checked!
     (relational-session-engine session)
     (relational-session-source-arities session) name rows)))

;;; Check every exported source and copy every row before entering the
;;; Session's atomic batch solve. Replacements are (label . rows) pairs.
;;; The returned solution is complete, or the earlier session remains live.
(def (relational-session-replace-sources! session fragment replacements)
  (unless (relational-session? session)
    (error "relational batch replacement requires a session" session))
  (validate GerbilAscentFragmentContract fragment)
  (unless (list? replacements)
    (error "relational batch replacements must be a list" replacements))
  (let ((seen (make-hash-table-eq))
        (arities (relational-session-source-arities session)))
    (let (checked
          (map
           (lambda (replacement)
             (unless (and (pair? replacement)
                          (symbol? (car replacement)))
               (error "invalid relational source replacement" replacement))
             (let* ((label (car replacement))
                    (name (relational-export fragment label))
                    (arity (assq name arities)))
               (unless (and (memq name (.ref fragment 'source-handles))
                            arity)
                 (error "relational export is not a source in this session"
                        label))
               (when (hash-get seen name)
                 (error "duplicate relational batch source" label))
               (hash-put! seen name #t)
               (let (rows (relational-copy-rows
                           (cdr replacement) (cdr arity)))
                 (relational-source name (cdr arity) rows)
                 (cons name rows))))
           replacements))
      (make-relational-solution
       (gerbil-ascent-session-replace-sources!
        (relational-session-engine session) checked)))))

(def (relational-program-replace-source! session name rows)
  (unless (relational-program-session? session)
    (error "named source replacement requires a program session" session))
  (relational-replace-source/checked!
   (relational-program-session-engine session)
   (relational-program-session-source-arities session) name rows))

(def (relational-program-append-source! session name row)
  (unless (relational-program-session? session)
    (error "named source append requires a program session" session))
  (relational-append-source/checked!
   (relational-program-session-engine session)
   (relational-program-session-source-arities session) name row))

(def (relational-session-result engine)
  (let (result (gerbil-ascent-session-run engine))
    (unless (.ref result 'finished)
      (error "relational session did not complete"))
    result))

(def (relational-session-run session)
  (unless (relational-session? session)
    (error "relational run requires a session" session))
  (make-relational-solution
   (relational-session-result (relational-session-engine session))))

(def (relational-program-session-run session)
  (unless (relational-program-session? session)
    (error "named run requires a program session" session))
  (make-relational-program-solution
   (relational-session-result
    (relational-program-session-engine session))))
