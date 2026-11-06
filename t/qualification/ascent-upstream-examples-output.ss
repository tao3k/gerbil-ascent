;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-upstream-examples-fixture
                 ascent-fibonacci-example-evaluate
                 ascent-context-flow-example-evaluate))

(export main)

(def (main . args)
  (unless (null? args)
    (error "ASCENT upstream example oracle reads one tagged input"))
  (let* ((request (read))
         (kind (car request))
         (result
          (case kind
            ((fibonacci)
             (ascent-fibonacci-example-evaluate (cadr request)))
            ((context-flow)
             (ascent-context-flow-example-evaluate (cadr request)))
            (else (error "unknown ASCENT upstream example" kind))))
         (rows-of (.ref result 'rows-of)))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (display name)
          (for-each
           (lambda (value) (display #\tab) (display value))
           row)
          (newline))
        (rows-of name)))
     (if (eq? kind 'fibonacci) '(fib) '(flow res)))
    (displayln "END")
    (force-output)))
