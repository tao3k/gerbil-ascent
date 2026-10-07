;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/misc/process "entry-cache.ss")
(export entry-cache-test)
(def (put path text)
  (call-with-output-file [path: path truncate: #t] (lambda (out) (display text out))))
(def entry-cache-test
  (test-suite "Native executable content admission"
    (test-case "changed binary inputs generated entry and malformed receipt cannot hit"
      (let* ((root (path-expand (string-append ".cache/ascent/tmp/cache-" (number->string (current-jiffy)))))
             (binary (path-expand "binary" root)) (receipt (path-expand "receipt.json" root))
             (inputs (hash ("source" "A") ("object" "B") ("tool" "C"))))
        (run-process/batch ["mkdir" "-p" root])
        (try
          (put binary "binary-A")
          (bind-entry! receipt binary "generated" inputs)
          (check-equal? (entry-current? receipt binary "generated" inputs) #t)
          (check-equal? (entry-current? receipt binary "generated" inputs "other-test") #f)
          (put binary "binary-B")
          (check-equal? (entry-current? receipt binary "generated" inputs) #f)
          (put binary "binary-A")
          (check-equal? (entry-current? receipt binary "changed" inputs) #f)
          (for-each (lambda (key)
            (let (changed (hash-copy inputs))
              (hash-put! changed key "changed")
              (check-equal? (entry-current? receipt binary "generated" changed) #f)))
            '("source" "object" "tool"))
          (let (added (hash-copy inputs))
            (hash-put! added "new-object" "X")
            (check-equal? (entry-current? receipt binary "generated" added) #f))
          (put receipt "not JSON")
          (check-equal? (entry-current? receipt binary "generated" inputs) #f)
          (delete-file receipt)
          (check-equal? (entry-current? receipt binary "generated" inputs) #f)
          (finally (run-process/batch ["rm" "-rf" root])))))))
