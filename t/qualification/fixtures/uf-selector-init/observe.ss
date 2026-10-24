;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; A downstream oracle supplies cases; the original public Scheme API owns
;;; admission, routing and publication. Official file import, no private loader.
(import :std/encoding/json :std/list/list-builder "../../../../core/relation-view.ss")
(export main)
(def (observe blocks columns key)
  (let* ((rectangles (map (lambda (block)
                          (make-rectangle (car block) (cadr block) (caddr block))) blocks))
         (count (foldl (lambda (block count)
                        (+ count (* (length (cadr block)) (length (caddr block))))) 0 blocks))
         (view (gerbil-ascent-rectangle-view rectangles count count #t)))
    (def (checked call)
      (with-exception-catcher (lambda (_) '("rejected"))
        (lambda () (list "accepted" (call)))))
    (list
      (checked (cut gerbil-ascent-view-rows view columns key))
      (checked (lambda () (with-list-builder (emit!)
        (gerbil-ascent-for-each-row emit! (gerbil-ascent-view-select view columns key)))))
      (checked (lambda () (with-list-builder (emit!)
        (gerbil-ascent-visit-view-parts! view columns key
          (lambda (prefix left right) (emit! (append prefix (list left right)))))))))))
(def (main input)
  (let (cases (call-with-input-file input read))
    (displayln (json->string (map (lambda (case) (apply observe case)) cases)))))
