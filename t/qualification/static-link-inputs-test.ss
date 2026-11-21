;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/error Error? Error-message)
        (only-in :gerbil/runtime/loader load-path)
        (only-in :clan/poo/object .call .get)
        (only-in "../../build.ss" gerbil-ascent-build-projection))
(export static-link-inputs-test)

(def static-link-inputs-test
  (test-suite "Package ABI borrowed static input ownership"
    (test-case "native selection, source guards and cleanup share the Core extent"
      (let (projection (gerbil-ascent-build-projection))
        (check-equal? (pair? (.get projection static-inputs)) #t)
        (def paths (load-path))
        (def staged #f)
        (def cause (list 'link-refusal))
        (def (input!)
          (set! staged
            (path-expand "static/clan__poo__support__base.scm" (car (load-path))))
          (check-equal? (file-exists? staged) #t))
        (def (run action)
          (.call projection .with-static-inputs action))
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
        (check-equal? (file-exists? staged) #f)))))
