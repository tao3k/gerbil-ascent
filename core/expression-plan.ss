;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Private admitted callback inputs lower once to frame reads. Calls remain
;;; at their original execution points; neither results nor frames are cached.
;;; Known arities avoid a transient argument list; ordered reads finish before
;;; invoking the callback. Larger arities retain the general apply path.
(import (only-in "ordered-call.ss" dispatch-ordered-call ordered-call-values))
(export gerbil-ascent-compile-frame-call gerbil-ascent-compile-frame-sequence
        gerbil-ascent-compile-input-guard gerbil-ascent-compile-checked-frame-call)

;; : (-> Procedure Slots (-> Frame Value))
(def (gerbil-ascent-compile-frame-call procedure slots)
  (dispatch-ordered-call (lambda (frame)) procedure slots
    (slot (vector-ref frame slot))))

;;; Compile an ordered callback segment backwards, without executing callbacks.
;;; Each continuation reads only its own frame. A failed guard skips its suffix;
;;; an exception is raised before any later binding or guard can execute.
;; : (-> FrameActions (-> Frame Boolean))
(def (gerbil-ascent-compile-frame-sequence actions)
  (if (null? actions)
    (lambda (_) #t)
    (let* ((action (car actions))
           (next (gerbil-ascent-compile-frame-sequence (cdr actions))))
      (case (vector-ref action 0)
        ((guard)
         (let (call (vector-ref action 1))
           (lambda (frame)
             (let (pass? (call frame))
               (unless (boolean? pass?)
                 (error "ASCENT guard must return a boolean" pass?))
               (and pass? (next frame))))))
        ((binding)
         (let ((slot (vector-ref action 1)) (call (vector-ref action 2)))
           (lambda (frame)
             (vector-set! frame slot (call frame))
             (next frame))))))))

;;; Fixed shape tests are lexical syntax, not runtime tuple adapters. The cut
;;; call sites supply a variable for current, so no caller expression repeats.
;; input-shape?
;; : (-> ShapeSyntax TupleSyntax Boolean)
;; | doc m%
;;     Specialize one/two-name guards without retaining a borrowed input spine.
;;
;;     # Examples
;;
;;     ```scheme
;;     ((cut input-shape? ('x) <>) '(x))
;;     ;; => #t
;;     ```
;;   %
(defrules input-shape? ()
  ((_ (one) current)
   (and (pair? current) (eq? (car current) one) (null? (cdr current))))
  ((_ (one two) current)
   (and (pair? current) (eq? (car current) one)
        (pair? (cdr current)) (eq? (cadr current) two)
        (null? (cddr current)))))

;; A one- or two-input call can check live names and read its frame slots
;; in the same closure. Expression payloads read the procedure before the
;; input names, just as the general evaluator does.
(def (gerbil-ascent-compile-checked-frame-call procedure names slots fallback payload)
  (defrule (checked-call (name ...) (slot ...))
    (if payload
      (lambda (frame)
        (let* ((current-procedure (vector-ref payload 1))
               (current-names (vector-ref payload 0)))
          (if (and (eq? current-procedure procedure)
                   (input-shape? (name ...) current-names))
            (ordered-call-values procedure (index (vector-ref frame index)) () (slot ...))
            (fallback current-procedure current-names frame))))
      (lambda (frame)
        (if (input-shape? (name ...) names)
          (ordered-call-values procedure (index (vector-ref frame index)) () (slot ...))
          (fallback procedure names frame)))))
  (match [names slots]
    ([[one] [first]] (checked-call (one) (first)))
    ([[one two] [first second]] (checked-call (one two) (first second)))
    (else
     (let ((fast (gerbil-ascent-compile-frame-call procedure slots))
           (stable-inputs? (gerbil-ascent-compile-input-guard names)))
       (if payload
         (lambda (frame)
           (let* ((current-procedure (vector-ref payload 1))
                  (current-names (vector-ref payload 0)))
             (if (and (eq? current-procedure procedure) (stable-inputs? current-names))
               (fast frame)
               (fallback current-procedure current-names frame))))
         (lambda (frame)
           (if (stable-inputs? names) (fast frame)
             (fallback procedure names frame))))))))

;;; Observe the current input tuple without retaining a borrowed mutable spine.
;;; Common arities use identity checks; larger shapes walk a detached vector.
;;; Element equality stays generic; every call validates the complete current shape.
;; : (-> Names (-> SchemeValue Boolean))

;; gerbil-ascent-compile-input-guard
;; : (-> Names (-> SchemeValue Boolean))
;; | doc m%
;;     Capture names, not a successful validation; each call checks the complete current tuple.
;;
;;     # Examples
;;
;;     ```scheme
;;     ((gerbil-ascent-compile-input-guard '(x)) '(x))
;;     ;; => #t
;;     ```
;;   %
(def (gerbil-ascent-compile-input-guard names)
  (match names
    ([] null?)
    ([one] (cut input-shape? (one) <>))
    ([one two] (cut input-shape? (one two) <>))
    (else
     (let (expected (list->vector names))
       (lambda (current)
         (do ((remaining current (cdr remaining)) (slot 0 (+ slot 1)))
             ((or (= slot (vector-length expected))
                  (not (pair? remaining))
                  (not (equal? (car remaining) (vector-ref expected slot))))
              (and (= slot (vector-length expected)) (null? remaining)))))))))
