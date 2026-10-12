;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; A storage Provider changes which facts a relation exposes. Evaluation-local
;;; state belongs to the relation run, not the shared Provider declaration.
;;; Stateful Providers must reject failures before mutating their private state;
;;; the evaluator preflights returned batches before committing its own rows.
(import (only-in :gerbil-ascent/core/relation-view gerbil-ascent-row-count)
        (only-in :gerbil/runtime/gambit fx-)
        (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop .defgeneric define-type validate)
        (only-in :core/types
                 PooFlowNativeObjectContract.
                 poo-flow-predicate-contract)
        (only-in :gerbil-ascent/table/eqrel gerbil-ascent-eqrel-state
                 gerbil-ascent-eqrel-extension gerbil-ascent-eqrel-state?
                 gerbil-ascent-eqrel-insert! gerbil-ascent-eqrel-freeze
                 gerbil-ascent-eqrel-publish!)
        (only-in :gerbil-ascent/table/trrel gerbil-ascent-trrel-state
                 gerbil-ascent-trrel-extension)
        (only-in :gerbil-ascent/table/trrel-uf gerbil-ascent-trrel-uf-state
                 gerbil-ascent-trrel-uf-extension
                 gerbil-ascent-trrel-uf-insert! gerbil-ascent-trrel-uf-freeze gerbil-ascent-trrel-uf-count-insert!))

(export gerbil-ascent-storage-initialize-uf! gerbil-ascent-canonical-view-storage-provider? gerbil-ascent-storage-eqrel-state?
        gerbil-ascent-storage-publish-view! gerbil-ascent-canonical-uf-storage-provider?
        gerbil-ascent-storage-view-extension! gerbil-ascent-storage-freeze-view
        GerbilAscentStorageProviderContract
        gerbil-ascent-set-storage-provider
        gerbil-ascent-canonical-set-storage-provider?
        gerbil-ascent-eqrel-storage-provider
        gerbil-ascent-trrel-storage-provider
        gerbil-ascent-trrel-uf-storage-provider
        gerbil-ascent-storage-make-state
        gerbil-ascent-storage-extension gerbil-ascent-storage-engine-extension
        gerbil-ascent-storage-engine-state gerbil-ascent-storage-owned-states
        gerbil-ascent-storage-check-state! gerbil-ascent-storage-admit-state!
        make-storage-readiness gerbil-ascent-storage-check-readiness!
        gerbil-ascent-storage-admit-readiness!
        gerbil-ascent-set-batch-admit!
        gerbil-ascent-storage-extend)

(def +make-state+
  (poo-flow-predicate-contract 'ascent/storage-make-state procedure?
                               (lambda (_value _context) [])))
(def +extend+
  (poo-flow-predicate-contract 'ascent/storage-extend procedure?
                               (lambda (_value _context) [])))

;;; Every storage provider owns a fresh state per evaluation. The shared POO
;;; declaration contains only constructor and extension behavior.
(define-type (GerbilAscentStorageProviderContract
              @ PooFlowNativeObjectContract.)
  identity: 'ascent/storage-provider
  proto: (.o)
  responsibilities: (.o .make-state: +make-state+
                      .extend-rows: +extend+))

(def StorageProvider. (.ref GerbilAscentStorageProviderContract 'proto))

;; : (-> StorageProvider StorageState)
(def (gerbil-ascent-storage-make-state provider)
  ((.ref provider '.make-state)))

;;; Admit a newest-first source-log prefix against Set membership. On an
;;; empty Set, a unique whole log is already the correct row spine and can be
;;; shared without copying. The fallback walks source order, so duplicates
;;; preserve the first accepted row's position. The returned table owns all
;;; accepted rows, including when the input table was empty and resized.
;; gerbil-ascent-set-batch-admit!
;;   : (-> SourceLog Nat SetMembership Boolean (Values Rows SetMembership))
;;   | doc m%
;;       Admit a staged Set batch in source order and return the accepted rows
;;       with their membership index. An empty Set can share a unique source
;;       log without copying its list spine.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-set-batch-admit! '((1 2)) 1 (make-hash-table) #t)
;;       ;; => the accepted row list and its membership table
;;       ```
;;     %
(def (gerbil-ascent-set-batch-admit! source-log count seen share-source?)
  (def (admit present)
    (let (source-order
          (let collect ((cursor source-log) (left count) (ordered []))
            (if (= left 0) ordered
              (collect (cdr cursor) (fx- left 1)
                       (cons (car cursor) ordered)))))
      (let deduplicate ((remaining source-order) (accepted []))
        (if (null? remaining)
          (values accepted present)
          (let (row (car remaining))
            (if (hash-get present row)
              (deduplicate (cdr remaining) accepted)
              (begin
                (hash-put! present row #t)
                (deduplicate (cdr remaining) (cons row accepted)))))))))
  (if (and share-source? (= (hash-length seen) 0))
    (let (present (make-hash-table size: count))
      ;; Clear the private uniqueness table before source-order admission:
      ;; its newest-row keys must not replace first-accepted row identities.
      (let scan ((cursor source-log) (left count) (next-size 1))
        (if (= left 0)
          (if (null? cursor)
            (values source-log present)
            (begin (hash-clear! present) (admit present)))
          (begin
            ;; One insertion and its cardinality reveal a duplicate without
            ;; hashing every unique row a second time for a membership probe.
            (hash-put! present (car cursor) #t)
            (if (= (hash-length present) next-size)
              (scan (cdr cursor) (fx- left 1) (fx+ next-size 1))
              (begin (hash-clear! present) (admit present)))))))
    (admit seen)))

;;; Extension must return a bounded batch before the evaluator commits rows;
;;; stateful providers preflight failures before changing their own state.
;; : (-> StorageProvider StorageState Rows Rows Row Nat Rows)
(.defgeneric (gerbil-ascent-storage-extend provider state all pending row budget)
  slot: .extend-rows)

(def +canonical-set-storage-provider+
  (validate GerbilAscentStorageProviderContract
            (.o (:: @ StorageProvider.)
                (.make-state (lambda () #f))
                (.extend-rows
                 (lambda (_state _all _pending row _budget) (list row))))))

(def gerbil-ascent-set-storage-provider +canonical-set-storage-provider+)

;;; Keep trusted representation identity independent of the exported default.
;; gerbil-ascent-canonical-set-storage-provider?
;;   : (-> StorageProviderCandidate Boolean)
;;   | doc m%
;;       Recognize the privately retained Set receiver validated at module load.
;;       Derived/custom receivers retain their normal checked dispatch.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-canonical-set-storage-provider? gerbil-ascent-set-storage-provider)
;;       ;; => #t for the original exported default
;;       ```
;;     %
(def (gerbil-ascent-canonical-set-storage-provider? value)
  (eq? value +canonical-set-storage-provider+))

(def gerbil-ascent-eqrel-storage-provider
  (validate GerbilAscentStorageProviderContract
            (.o (:: @ gerbil-ascent-set-storage-provider)
                (.make-state gerbil-ascent-eqrel-state)
                (.extend-rows gerbil-ascent-eqrel-extension))))

(def gerbil-ascent-trrel-storage-provider
  (validate GerbilAscentStorageProviderContract
            (.o (:: @ gerbil-ascent-set-storage-provider)
                (.make-state gerbil-ascent-trrel-state)
                (.extend-rows gerbil-ascent-trrel-extension))))

(def gerbil-ascent-trrel-uf-storage-provider
  (validate GerbilAscentStorageProviderContract
            (.o (:: @ gerbil-ascent-set-storage-provider)
                (.make-state gerbil-ascent-trrel-uf-state)
                (.extend-rows gerbil-ascent-trrel-uf-extension))))

;;; Retain native receiver identities privately. Rebinding public declarations
;;; or deriving a receiver does not grant borrowed engine row access.
(def +native-storage-providers+
  (list +canonical-set-storage-provider+ gerbil-ascent-eqrel-storage-provider
        gerbil-ascent-trrel-storage-provider gerbil-ascent-trrel-uf-storage-provider))

;;; Stateful engine storage remains tentative until the evaluator commits the complete
;;; source batch or rule round. Private mutations cannot be rolled back in
;;; general; an interrupted owner requires source replay into a fresh engine.
(defstruct storage-readiness-state (unready pending) final: #t)
(defstruct storage-state-owner (value phase readiness) final: #t)

;; : (-> StorageReadiness)
(def (make-storage-readiness) (make-storage-readiness-state 0 []))

;; One phase transition owns both local readiness and the engine's summary.
;; : (-> StorageOwner Symbol Void)
(def (storage-state-transition! (state :- storage-state-owner) phase)
  (unless (eq? state.phase phase)
    (when state.readiness
      (using (ready state.readiness :- storage-readiness-state)
        (cond
         ((eq? state.phase 'ready)
          (set! ready.unready (+ ready.unready 1))
          (set! ready.pending (cons state ready.pending)))
         ((eq? phase 'ready)
          (set! ready.unready (- ready.unready 1))
          (when (= ready.unready 0) (set! ready.pending []))))))
    (set! state.phase phase)))

;; : (-> StorageReadiness Void)
(def (gerbil-ascent-storage-check-readiness! (ready :- storage-readiness-state))
  (unless (= ready.unready 0) (error "ASCENT storage state requires source replay")))

;; Only the complete source/round publisher may restore touched owners.
;; : (-> StorageReadiness Void)
(def (gerbil-ascent-storage-admit-readiness! (ready :- storage-readiness-state))
  (for-each gerbil-ascent-storage-admit-state! ready.pending))

(def (gerbil-ascent-storage-engine-state provider (readiness #f))
  (let (state (gerbil-ascent-storage-make-state provider))
    (if (gerbil-ascent-canonical-set-storage-provider? provider) state
      (make-storage-state-owner state 'ready readiness))))

(def (gerbil-ascent-storage-owned-states states)
  (filter storage-state-owner? (vector->list states)))

(def (gerbil-ascent-storage-check-state! state)
  (when (and (storage-state-owner? state)
             (not (eq? (storage-state-owner-phase state) 'ready)))
    (error "ASCENT storage state requires source replay")))

(def (gerbil-ascent-storage-admit-state! state)
  (when (storage-state-owner? state)
    (storage-state-transition! state 'ready)))

(def (owned-storage-rows rows)
  (map (lambda (row) (map values row)) rows))

;;; One readiness protocol for mutable native and custom state. Native kernels
;;; still receive their raw state and borrowed rows; custom dispatch owns spines.
(def (call-with-storage-state state invoke)
  (when (storage-state-owner? state)
    (when (eq? (storage-state-owner-phase state) 'failed)
      (error "ASCENT storage state requires source replay"))
    (storage-state-transition! state 'pending))
  (with-catch
   (lambda (failure)
     (when (storage-state-owner? state)
       (storage-state-transition! state 'failed))
     (raise failure))
   (lambda ()
     (invoke (if (storage-state-owner? state)
               (storage-state-owner-value state) state)))))

;;; Public algorithm dispatch keeps native procedure identity. Custom receivers
;;; own argument and result spines; field values remain shared.
;; gerbil-ascent-storage-extension
;; : (-> StorageProvider Nat StorageExtension)
;; | doc m%
;;     Select native dispatch or an owned custom row-spine boundary once.
;;     Custom callbacks borrow raw private state and share field values, while
;;     their input and returned list spines cannot alias engine row buffers.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-storage-extension gerbil-ascent-set-storage-provider 2)
;;     ;; => the canonical native extension procedure
;;     ```
;;   %
(def (gerbil-ascent-storage-extension provider width)
  (let (extend (.ref provider '.extend-rows))
    (if (memq provider +native-storage-providers+)
      extend
      (lambda (state all pending row budget)
        (call-with-storage-state
         state
         (lambda (raw-state)
           (let* ((owned-all (owned-storage-rows all))
                  (owned-pending (if (eq? all pending) owned-all
                                   (owned-storage-rows pending)))
                  (expanded (extend raw-state owned-all owned-pending
                                    (map values row) budget)))
             (unless (list? expanded)
               (error "ASCENT storage provider returned non-list rows"))
             ;; Bound row shape traversal before copying or field callbacks.
             (for-each
              (lambda (stored)
                (let loop ((remaining stored) (left width))
                  (if (= left 0)
                    (unless (null? remaining)
                      (error "invalid ASCENT storage provider row"))
                    (if (pair? remaining)
                      (loop (cdr remaining) (- left 1))
                      (error "invalid ASCENT storage provider row")))))
              expanded)
             (owned-storage-rows expanded))))))))

;;; The schema selects engine dispatch separately from the raw graph API.
;;; Canonical Set has no mutable storage state. Other native kernels borrow
;;; admitted rows without copying, but their readiness lasts through publication.
;; : (-> StorageProvider Nat StorageExtension)
(def (gerbil-ascent-storage-engine-extension provider width)
  (if (and (memq provider +native-storage-providers+)
           (not (gerbil-ascent-canonical-set-storage-provider? provider)))
    (let (extend (.ref provider '.extend-rows))
      (lambda (state all pending row budget)
        (call-with-storage-state state
          (lambda (raw-state) (extend raw-state all pending row budget)))))
    (gerbil-ascent-storage-extension provider width)))

(def (gerbil-ascent-canonical-view-storage-provider? provider)
  (or (eq? provider +canonical-eqrel-storage-provider+)
      (gerbil-ascent-canonical-uf-storage-provider? provider)))
(def (gerbil-ascent-storage-eqrel-state? state)
  (and (storage-state-owner? state)
       (gerbil-ascent-eqrel-state? (storage-state-owner-value state))))
(def +canonical-eqrel-storage-provider+ gerbil-ascent-eqrel-storage-provider)
(def +canonical-uf-storage-provider+ gerbil-ascent-trrel-uf-storage-provider)
;; : (-> StorageProvider Boolean)
(def (gerbil-ascent-canonical-uf-storage-provider? provider)
  (eq? provider +canonical-uf-storage-provider+))
;; : (-> StorageOwner Row Natural FrozenView)
(def (gerbil-ascent-storage-view-extension! state row budget)
  (call-with-storage-state state
    (lambda (raw) (if (gerbil-ascent-eqrel-state? raw)
                    (gerbil-ascent-eqrel-insert! raw row budget)
                    (gerbil-ascent-trrel-uf-insert! raw row budget)))))
;; : (-> StorageOwner FrozenView)
(def (gerbil-ascent-storage-freeze-view state (indexed? #t))
  (when (eq? (storage-state-owner-phase state) 'failed)
    (error "ASCENT storage state requires source replay"))
  (let (raw (storage-state-owner-value state))
    (if (gerbil-ascent-eqrel-state? raw)
      (gerbil-ascent-eqrel-freeze raw indexed?)
      (gerbil-ascent-trrel-uf-freeze raw indexed?))))
(def (gerbil-ascent-storage-publish-view! state frontier count indexed?)
  (when (eq? (storage-state-owner-phase state) 'failed)
    (error "ASCENT storage state requires source replay"))
  (if (gerbil-ascent-storage-eqrel-state? state)
    (gerbil-ascent-eqrel-publish! (storage-state-owner-value state)
                                count indexed?)
    (begin
      (unless (= count (gerbil-ascent-row-count frontier)) (error "ASCENT UF frontier count mismatch"))
      (values (gerbil-ascent-storage-freeze-view state indexed?) frontier))))


;; gerbil-ascent-storage-initialize-uf!
;; : (-> StorageOwner Rows SourceAdmission Natural Natural Natural)
;; | requires: Fresh canonical UF owner, no external field callbacks.
;; | doc m%
;;     Admit an initial UF source batch under one private failure boundary.
;;     Source checks precede each injection; its remaining output budget is
;;     checked by the native kernel before commit. Count publication declines
;;     concrete frontiers. The caller admits readiness after the complete batch.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-storage-initialize-uf! owner '((0 1)) check-source! 0 8)
;;     ;; => 3 materialized rows, with the private owner awaiting admission
;;     ```
;;   %
(def (gerbil-ascent-storage-initialize-uf! state rows check-source! count output-limit)
  (call-with-storage-state state
    (lambda (raw)
      (def previous #f)
      (for-each (lambda (row)
        (check-source! row)
        ;; A duplicate immediately follows its successful admission, with the
        ;; same monotone owner and a nonnegative remaining budget. Source
        ;; occurrence checks still execute; its empty frontier changes no count.
        (unless (equal? previous row)
          (set! count (+ count (gerbil-ascent-trrel-uf-count-insert! raw row (- output-limit count))))
          (set! previous row))) rows)
      count)))
