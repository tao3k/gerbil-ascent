;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil/runtime/init __scheme-source))
(export ascent-with-generated-resources)

;; Gerbil metadata emits __noexpand wrappers while its loader reads generated
;; Gambit files. Unwrap metadata first: an outer raw-source parameter alone
;; otherwise returns the wrapper as an ill-formed Gambit procedure call.
(def (ascent-with-generated-resources thunk)
  (let (previous ##expand-source)
    (dynamic-wind
      (lambda ()
        (##expand-source-set!
         (lambda (source)
           (if (and (##source? source)
                    (pair? (##source-code source))
                    (eq? (car (##source-code source)) __noexpand:))
             (cdr (##source-code source))
             source))))
      (lambda () (parameterize ((__scheme-source 'ascent-generated-resources)) (thunk)))
      (lambda () (##expand-source-set! previous)))))
