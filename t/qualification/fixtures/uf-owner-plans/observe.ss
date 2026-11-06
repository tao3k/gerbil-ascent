;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/encoding/json :std/list/list-builder "../../../../core/relation-view.ss")
(export main)
(def (observe axes owners columns key indexed?)
  (let* ((blocks (map (lambda (owner ordinal)
                  (let (axis (list-ref axes owner)) (make-rectangle (list ordinal) axis axis)))
                  owners (iota (length owners))))
         (count (foldl (lambda (owner n) (+ n (expt (length (list-ref axes owner)) 2))) 0 owners))
         (view (gerbil-ascent-rectangle-view blocks count count indexed?)))
    (def (checked call)
      (with-exception-catcher (lambda (_) '("rejected"))
        (lambda () (list "accepted" (call)))))
    (list
      (checked (cut gerbil-ascent-view-rows view columns key))
      (checked (lambda () (with-list-builder (emit!)
        (gerbil-ascent-for-each-row emit! (gerbil-ascent-view-select view columns key)))))
      (checked (lambda () (with-list-builder (emit!)
        (gerbil-ascent-visit-view-parts! view columns key
          (lambda (prefix left right)
            ;; Nested readers must never mutate a shared owner or cursor.
            (unless (= (length (gerbil-ascent-view-rows view)) count)
              (error "nested owner read changed the frozen cut"))
            (emit! (append prefix (list left right)))))))))))
(def (main input)
  (displayln (json->string (map (lambda (case) (apply observe case))
                           (call-with-input-file input read)))))
