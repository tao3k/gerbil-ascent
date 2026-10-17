;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander)
(export assert-native-library!)
;; Verify the actual gxtest process before the scenario starts timing.
;; : (-> Void)
(def (assert-native-library!)
  (let (library (getenv "ASCENT_TEST_LIBRARY" #f))
    (when library
      (for-each
       (lambda (name)
         (let* ((id (string->symbol (string-append ":gerbil-ascent/" name)))
                ;; Resolve before Cases without importing unrelated production
                ;; modules and constructing their process-local contract state.
                (resolved (gx#core-resolve-library-module-path id))
                (expected (path-expand (string-append "gerbil-ascent/" name ".ssi")
                                       library)))
           (unless (equal? resolved expected)
             (error "performance process loaded unqualified module" id resolved expected))))
       (call-with-input-file (getenv "ASCENT_PERFORMANCE_MODULES") read))
      (displayln "NATIVE-MODULES-OK") (force-output))))
