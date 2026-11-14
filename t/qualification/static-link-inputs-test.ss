;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/error Error? Error-message)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :gerbil/runtime/loader load-path)
        (only-in "../../build.ss" call-with-static-link-inputs))
(export static-link-inputs-test)

(def static-link-inputs-test
  (test-suite "Package ABI borrowed static input ownership"
    (test-case "native selection, source guards and cleanup share the Core extent"
      (call-with-temporary-directory "ascent-static-link-"
        (lambda (root)
          (def (put name text)
            (call-with-output-file (list path: (path-expand name root) truncate: #t)
              (lambda (port) (display text port))))
          (put "gerbil.pkg" "(package: ascent-static-fixture)\n")
          (put "entry.ss"
            "(import :clan/poo/object) (error \"metadata discovery executed runtime\")\n")
          (put "unselected.ss" "(import :missing/unselected)\n")
          (def paths (load-path))
          (def staged #f)
          (def cause (list 'link-refusal))
          (def (input!)
            (set! staged
              (path-expand "static/clan__poo__support__base.scm" (car (load-path))))
            (check-equal? (file-exists? staged) #t))
          (def (run action)
            (call-with-static-link-inputs root '("entry.ss")
              '(ascent-static-fixture/entry) action))
          (check-equal? (run (lambda () (input!) 'linked)) 'linked)
          (check-equal? (eq? paths (load-path)) #t)
          (check-equal? (file-exists? staged) #f)
          (check-equal?
            (eq? cause (with-catch values (lambda ()
              (run (lambda () (input!) (raise cause)))))) #t)
          (check-equal? (eq? paths (load-path)) #t)
          (check-equal? (file-exists? staged) #f)
          ;; Derived C/objects are writable; changing the borrowed Scheme is not.
          (check-exception
            (run (lambda ()
              (input!)
              (call-with-output-file (list path: staged truncate: #t)
                (lambda (port) (display "changed compiler input" port)))))
            (lambda (failure)
              (and (Error? failure)
                   (equal? (Error-message failure) "staged native compiler input changed"))))
          (check-equal? (eq? paths (load-path)) #t)
          (check-equal? (file-exists? staged) #f))))))
