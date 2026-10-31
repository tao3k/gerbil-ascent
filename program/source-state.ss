;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .ref)
        (only-in :std/iter for in-range)
        (only-in "source-log.ss" gerbil-ascent-source-log-rows)
        (only-in "source-snapshot.ss" gerbil-ascent-source-snapshot
                 gerbil-ascent-prepare-source-log-snapshot))
(export source-state-originals source-state-additions source-state-overrides
        gerbil-ascent-source-state gerbil-ascent-source-state-rows
        gerbil-ascent-prepare-source-replacement gerbil-ascent-commit-source-replacement!)

;;; One retained engine owns these vector headers. Row spines may still be
;;; borrowed from raw Program declarations: root identity never proves a count
;;; or validates a callback. Prospective cuts remain separate until evaluation
;;; succeeds; failed preparation/evaluation leaves this recovery log untouched.
(defstruct source-state (originals additions overrides snapshot) final: #t)

;; : (forall (p r) (-> p [r] SourceState))
;; : (-> Program RelationList SourceState)
(def (gerbil-ascent-source-state program relations)
  (let* ((originals (list->vector
                     (map (lambda (relation) (.ref relation 'rows))
                          relations)))
         (count (vector-length originals)))
    (make-source-state originals (make-vector count []) (make-vector count #f)
                       (gerbil-ascent-source-snapshot program))))

;; : (forall (r) (-> SourceState Natural [r]))
;; : (-> SourceState Natural Rows)
(def (gerbil-ascent-source-state-rows (state :- source-state) index)
  (or (vector-ref state.overrides index)
      (gerbil-ascent-source-log-rows (vector-ref state.originals index)
                                    (vector-ref state.additions index))))

;; : (forall (r) (-> SourceState Natural [r] SourceSnapshot))
;; : (-> SourceState Natural Rows SourceSnapshot)
(def (gerbil-ascent-prepare-source-replacement (state :- source-state) index rows)
  (let (logs (make-vector (vector-length state.originals)))
    (for (position (in-range (vector-length logs)))
      (vector-set! logs position
        (cond
         ((= position index) (cons rows []))
         ((vector-ref state.overrides position) => (cut cons <> []))
         (else (cons (vector-ref state.originals position)
                     (vector-ref state.additions position))))))
    (gerbil-ascent-prepare-source-log-snapshot state.snapshot logs)))

;;; No user callbacks at commit. Evaluation and source budget admission belong
;;; to the caller and must finish before adopting a cut or retiring its log.
;; : (forall (r) (-> SourceState Natural [r] SourceSnapshot Void))
;; : (-> SourceState Natural Rows SourceSnapshot Void)
(def (gerbil-ascent-commit-source-replacement! (state :- source-state) index rows cut)
  (set! state.snapshot cut)
  (vector-set! state.overrides index rows)
  (vector-set! state.additions index []))
