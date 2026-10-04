;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Completed-closure reuse admission and engine-local rule activation.
(import (only-in :clan/poo/object .ref)
        (only-in "update-selection.ss" gerbil-ascent-update-selection
                 gerbil-ascent-update-active-plans))
(export gerbil-ascent-prepare-native-reuse gerbil-ascent-reuse-active-rules
        gerbil-ascent-activate-rules
        native-reuse? native-reuse-result native-reuse-affected)

;;; Only completed native snapshots may seed an update. The capsule is private
;;; to this module; checked Session owns the previous and prospective inputs.
;; native-reuse
;; : (forall (r a) (-> r a (NativeReuse r a)))
;; : (-> EvaluationResult AffectedRelations NativeReuse)
;; | doc m%
;;     Carry the admitted completed result and affected relation mask privately.
;;
;;     # Examples
;;
;;     ```scheme
;;     (make-native-reuse completed affected)
;;     ;; => an internal capsule after completed-result admission
;;     ```
;;   %
(defstruct native-reuse (result affected))

;; gerbil-ascent-prepare-native-reuse
;; : (forall (p r a c) (-> p p r a (Maybe c)))
;; : (-> SourceSnapshot Program EvaluationResult Analysis (Maybe NativeReuse))
;; | doc m%
;;     Admit a completed closure for stable source-only updates. The affected
;;     dependency closure includes positive, negative and aggregate reads.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-prepare-native-reuse previous candidate completed analysis)
;;     ;; => a private reuse capsule, or #f for unsupported callbacks/providers
;;     ```
;;   %
(def (gerbil-ascent-prepare-native-reuse previous candidate completed analysis)
  (unless (.ref completed 'finished) (error "cannot reuse a partial closure"))
  (let (affected (gerbil-ascent-update-selection previous candidate analysis))
    (and affected (make-native-reuse completed affected))))

;; gerbil-ascent-activate-rules
;; : (forall (a r) (-> a (Vector [r])))
;; : (-> Analysis ActiveRulesByStratum)
;; | doc m%
;;     Instantiate cached immutable activation metadata with engine-local frames.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-activate-rules analysis)
;;     ;; => all rules with fresh mutable frames, leaving analysis unchanged
;;     ```
;;   %
(def (gerbil-ascent-activate-rules analysis)
  (vector-map
   (lambda (rules)
     (map (lambda (rule)
            (let (plan (vector-ref rule 5))
              (vector (vector-ref rule 0) (vector-ref rule 1)
                      (vector-ref rule 2) (vector-ref rule 3)
                      (vector-ref rule 4)
                      plan
                      (and plan (make-vector (vector-ref plan 2) #f)))))
          rules))
   (vector-ref analysis 5)))

;; gerbil-ascent-reuse-active-rules
;; : (forall (r c) (-> (Vector [r]) (Maybe c) (Vector [r])))
;; : (-> ActiveRulesByStratum (Maybe NativeReuse) ActiveRulesByStratum)
;; | doc m%
;;     Select affected heads while retaining the complete activation for
;;     later source appends. Partial heads receive their own compiled frames.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-reuse-active-rules all-rules #f)
;;     ;; => all-rules, with no filtering or new frames
;;     ```
;;   %
(def (gerbil-ascent-reuse-active-rules full-active-by-stratum reuse)
  (if (not reuse)
    full-active-by-stratum
    (gerbil-ascent-update-active-plans
     full-active-by-stratum (native-reuse-affected reuse))))
