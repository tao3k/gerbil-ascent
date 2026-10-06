;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/misc/process)
(export make-native-receipt native-receipt-line! native-receipt-ok? run-test-child)

;; The coordinator launches the frozen native carrier directly. Receipt
;; admission retains the shell adapter's verdict gates without spawning a
;; recipe interpreter, shell and text-filter pipeline for each assigned task.
(defstruct child-receipt (module cases module-ok? harness-ok? native-ok? ok? failed?))
(def (make-native-receipt path)
  (make-child-receipt
   (path-expand (string-append "gerbil-ascent/" (path-strip-extension path) ".ssi")
                (getenv "ASCENT_TEST_LIBRARY"))
   0 #f #f #f #f #f))

(def (native-receipt-line! receipt line)
  (cond
   ((string-prefix? "MODULE " line) (set! (child-receipt-cases receipt) 0))
   ((string-prefix? "CASE " line)
    (set! (child-receipt-cases receipt) (+ 1 (child-receipt-cases receipt))))
   ((string-prefix? "MODULE-OK " line)
    (if (and (> (child-receipt-cases receipt) 0)
             (equal? line (string-append "MODULE-OK " (child-receipt-module receipt))))
      (set! (child-receipt-module-ok? receipt) #t)
      (set! (child-receipt-failed? receipt) #t)))
   ((string-prefix? "HARNESS-OK " line) (set! (child-receipt-harness-ok? receipt) #t))
   ((equal? line "NATIVE-MODULES-OK") (set! (child-receipt-native-ok? receipt) #t))
   ((equal? line "OK") (set! (child-receipt-ok? receipt) #t)))
  (when (ormap (lambda (marker) (string-contains line marker))
               '("ERROR CHECK" "ERROR CASE" "ERROR HARNESS" "ERROR MODULE"
                 "Heap overflow" "Stack overflow"))
    (set! (child-receipt-failed? receipt) #t)))

(def (native-receipt-ok? receipt status)
  (and (zero? status) (not (child-receipt-failed? receipt))
       (child-receipt-module-ok? receipt) (child-receipt-harness-ok? receipt)
       (child-receipt-native-ok? receipt) (child-receipt-ok? receipt)))

(def (run-test-child path emit)
  (let ((status 70) (receipt (make-native-receipt path)))
    (emit (string-append "[ascent-test] START " path))
    (run-process ["python3" "-m" "ascent_test_support.supervision"
                  "--startup-seconds" "5" "--idle-seconds" "5"
                  "--" "timeout" (getenv "ASCENT_GXTEST_TIMEOUT" "120s")
                  (getenv "ASCENT_NATIVE_TEST_ENTRY") "-:max-heap=1G,debug=q" path]
      stderr-redirection: #t
      check-status: (lambda (raw settings)
                      (set! status (if (zero? (bitwise-and raw #xff))
                                    (quotient raw 256) (+ 128 (bitwise-and raw #xff)))))
      coprocess: (lambda (process)
                   (let loop ()
                     (let (line (read-line process))
                       (unless (eof-object? line)
                         (native-receipt-line! receipt line) (emit line) (loop))))))
    (cond
     ((native-receipt-ok? receipt status)
      (emit (string-append "[ascent-test] PASS " path)) 0)
     ((zero? status)
      (emit (string-append "[ascent-test] FAIL incomplete native receipt " path)) 70)
     (else status))))
