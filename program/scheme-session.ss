;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later


;;; Checked retained updates and transaction admission. The native Session owns rollback.
(import (only-in "scheme-snapshot.ss" relational-snapshot-program)
        (only-in "scheme-query.ss" relational-export
                 make-relational-solution make-relational-program-solution)
        (only-in "scheme-checked.ss" relational-copy-row relational-copy-rows)
        (only-in "session.ss" gerbil-ascent-open-session
                 gerbil-ascent-session-append-source! gerbil-ascent-session-replace-source!
                 gerbil-ascent-session-replace-sources! gerbil-ascent-session-run)
        (only-in "types.ss" GerbilAscentFragmentContract)
        (only-in :clan/poo/object .ref)
        (only-in :clan/poo/mop validate)
        (only-in :std/list/list find))
(export relational-open-session relational-open-program-session
        relational-session-append-source! relational-session-replace-source!
        relational-session-replace-sources! relational-session-transaction! relational-session-run
        relational-program-append-source! relational-program-replace-source!
        relational-program-transaction! relational-program-session-run)

(defstruct relational-session (engine source-arities))
(defstruct relational-program-session (engine source-arities))

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
         (arities (relational-source-arities snapshot)))
    ;; Compiled programs may contain derived relations. Their query handles
    ;; are not update authority: every checked mutation uses this immutable
    ;; source-only arity list, shared with fragment Sessions below.
    (make-relational-program-session
     (gerbil-ascent-open-session snapshot)
     arities)))

(def (relational-replace-source/checked! engine arities name rows)
  (let (arity (and (symbol? name) (assq name arities)))
    (unless arity
      (error "relation is not a source in this session" name))
    (let (copied (relational-copy-rows rows (cdr arity)))
      ;; The checked copy already validates every row and owns its list spine.
      (gerbil-ascent-session-replace-source! engine name copied)
      (void))))

;;; Insert one checked source row into the retained positive session. The
;;; underlying session decides whether its admitted plan can reuse deltas;
;;; a caller still observes results only after a completed run.
(def (relational-append-source/checked! engine arities name row)
  (let (arity (and (symbol? name) (assq name arities)))
    (unless arity
      (error "relation is not a source in this session" name))
    (let (copied (relational-copy-row row (cdr arity)))
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

;;; Both named programs and composed fragments share one checked source
;;; replacement boundary. Nothing enters the Session before all rows have
;;; been copied and every source name has passed arity and uniqueness checks.
(def (relational-checked-replacements arities entries)
  (unless (and (list? entries) (pair? entries))
    (error "relational transaction requires source updates" entries))
  (let (seen (make-hash-table-eq))
    (map
     (lambda (entry)
       (unless (and (pair? entry) (symbol? (car entry)))
         (error "invalid relational source update" entry))
       (let* ((name (car entry))
              (arity (assq name arities)))
         (unless arity
           (error "relation is not a source in this session" name))
         (when (hash-get seen name)
           (error "duplicate relational transaction source" name))
         (hash-put! seen name #t)
         (let (rows (relational-copy-rows (cdr entry) (cdr arity)))
           (cons name rows))))
     entries)))

;;; Updates are (fragment label rows) triples. Each handle must be an
;;; exported source in this composed session. The returned solution is
;;; complete, or the previous completed snapshot remains current.
(def (relational-session-transaction! session updates)
  (unless (relational-session? session)
    (error "relational transaction requires a session" session))
  (unless (and (list? updates) (pair? updates))
    (error "relational transaction requires source updates" updates))
  (let (entries
        (map
         (lambda (update)
           (unless (and (list? update) (= (length update) 3)
                        (symbol? (cadr update)))
             (error "invalid relational transaction update" update))
           (let* ((fragment (car update))
                  (label (cadr update)))
             (let (name (relational-export fragment label))
               (unless (memq name (.ref fragment 'source-handles))
                 (error "relational export is not a source in this session"
                        label))
               (cons name (caddr update)))))
         updates))
    (make-relational-solution
     (gerbil-ascent-session-replace-sources!
      (relational-session-engine session)
      (relational-checked-replacements
       (relational-session-source-arities session) entries)))))

;;; Single-fragment batches use the same cross-fragment transaction owner.
(def (relational-session-replace-sources! session fragment replacements)
  (unless (list? replacements)
    (error "relational batch replacements must be a list" replacements))
  (relational-session-transaction!
   session
   (map
    (lambda (replacement)
      (unless (and (pair? replacement) (symbol? (car replacement)))
        (error "invalid relational source replacement" replacement))
      (list fragment (car replacement) (cdr replacement)))
    replacements)))

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

;;; The direct named program uses the same atomic Session transaction and
;;; row checks. Its result retains the distinct named-solution query type.
(def (relational-program-transaction! session replacements)
  (unless (relational-program-session? session)
    (error "named transaction requires a program session" session))
  (make-relational-program-solution
   (gerbil-ascent-session-replace-sources!
    (relational-program-session-engine session)
    (relational-checked-replacements
     (relational-program-session-source-arities session)
     replacements))))

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
