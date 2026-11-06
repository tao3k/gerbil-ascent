;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Private admitted callback inputs lower once to frame reads. Calls remain
;;; at their original execution points; neither results nor frames are cached.
;;; Known arities avoid a transient argument list; ordered reads finish before
;;; invoking the callback. Larger arities retain the general apply path.
(export gerbil-ascent-compile-frame-call gerbil-ascent-compile-frame-sequence
        gerbil-ascent-compile-input-guard)

;; : (-> Procedure Slots (-> Frame Value))
(def (gerbil-ascent-compile-frame-call procedure slots)
  (match slots
    ([] (lambda (_) (procedure)))
    ([one] (lambda (frame) (procedure (vector-ref frame one))))
    ([one two]
     (lambda (frame)
       (let* ((left (vector-ref frame one))
              (right (vector-ref frame two)))
         (procedure left right))))
    ([one two three]
     (lambda (frame)
       (let* ((first (vector-ref frame one))
              (second (vector-ref frame two))
              (third (vector-ref frame three)))
         (procedure first second third))))
    ([one two three four]
     (lambda (frame)
       (let* ((first (vector-ref frame one))
              (second (vector-ref frame two))
              (third (vector-ref frame three))
              (fourth (vector-ref frame four)))
         (procedure first second third fourth))))
    (else
     (lambda (frame)
       (apply procedure (map (lambda (slot) (vector-ref frame slot)) slots))))))

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

;;; Observe the current input tuple without retaining a borrowed mutable spine.
;;; Common arities use identity checks; larger shapes walk a detached vector.
;;; Element equality stays generic; every call validates the complete current shape.
;; : (-> Names (-> Any Boolean))
(def (gerbil-ascent-compile-input-guard names)
  (match names
    ([] null?)
    ([one]
     (lambda (current)
       (and (pair? current) (eq? (car current) one) (null? (cdr current)))))
    ([one two]
     (lambda (current)
       (and (pair? current) (eq? (car current) one)
            (pair? (cdr current)) (eq? (cadr current) two)
            (null? (cddr current)))))
    (else
     (let (expected (list->vector names))
       (lambda (current)
         (let compare ((remaining current) (slot 0))
           (if (= slot (vector-length expected)) (null? remaining)
             (and (pair? remaining)
                  (equal? (car remaining) (vector-ref expected slot))
                  (compare (cdr remaining) (+ slot 1))))))))))
