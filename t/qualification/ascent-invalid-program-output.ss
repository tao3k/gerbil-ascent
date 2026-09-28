;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil/runtime/gambit
                 call-with-output-string display-exception
                 with-exception-catcher)
        (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-count gerbil-ascent-evaluate-program))

(export main category)

(def (invalid-program name)
  (case name
    ((negative-self)
     (ascent
      (relation node (value) '((1)))
      (relation looped (value))
      ((looped x) <-- (node x) (not (looped x)))
      (bounds 8 8 16)))
    ((mutual-negation)
     (ascent
      (relation node (value) '((1)))
      (relation left (value))
      (relation right (value))
      ((left x) <-- (node x) (not (right x)))
      ((right x) <-- (node x) (not (left x)))
      (bounds 8 8 16)))
    ((negative-feedback)
     (ascent
      (relation node (value) '((1)))
      (relation left (value))
      (relation right (value))
      ((left x) <-- (node x) (not (right x)))
      ((right x) <-- (left x))
      (bounds 8 8 16)))
    ((aggregate-self)
     (ascent
      (relation number (value) '((1)))
      ((number total) <--
       (aggregate total gerbil-ascent-count () (number x)))
      (bounds 8 8 16)))
    ((negative-with-unrelated-aggregate)
     (ascent
      (relation node (value) '((1)))
      (relation left (value))
      (relation total (value))
      ((left x) <-- (node x) (not (left x)))
      ((total n) <--
       (aggregate n gerbil-ascent-count () (node x)))
      (bounds 8 8 16)))
    ((unsafe-negation)
     (ascent
      (relation node (value) '((1)))
      (relation block (value))
      (relation out (value))
      ((out x) <-- (node x) (not (block y)))
      (bounds 8 8 16)))
    (else (error "unknown ASCENT invalid-program case" name))))

(def (problem name)
  (with-exception-catcher
   (lambda (failure)
     (call-with-output-string
      (lambda (port) (display-exception failure port))))
   (lambda ()
     (gerbil-ascent-evaluate-program (invalid-program name))
     #f)))

(def (category name)
  (let (message (problem name))
    (cond
     ((and (string? message)
           (string-contains message
                            "unstratifiable ASCENT negation cycle"))
      'negation-cycle)
     ((and (string? message)
           (string-contains message
                            "unstratifiable ASCENT aggregate cycle"))
      'aggregate-cycle)
     ((and (string? message)
           (string-contains message
                            "unsafe ASCENT negation variable"))
      'unsafe-negation)
     (else (error "unexpected ASCENT invalid-program diagnostic"
                  name message)))))

(def (main . args)
  (unless (null? args)
    (error "ASCENT invalid-program corpus reads case names from stdin"))
  (for-each
   (lambda (name)
     (display name) (display #\tab) (display (category name))
     (newline))
   (read))
  (display "END\n")
  (force-output))
