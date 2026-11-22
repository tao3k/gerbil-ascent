;;; -*- Gerbil -*-
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in "actor-million-test.ss" ten-million-query)
        (only-in :gerbil-ascent/interface/engine-api
                 ascent-engine-session-copy-integer-relation!))
(export actor-ten-million-chains-128-list-test actor-ten-million-chains-128-buffer-test
        actor-ten-million-chains-512-list-test actor-ten-million-chains-512-buffer-test)

(def actor-ten-million-chains-128-list-test
  (test-suite "Complete mutable lists for 1,240 chains of width 128"
    (test-case "independently verify all 10,078,720 result rows per request"
      (ten-million-query 128))))

(def actor-ten-million-chains-128-buffer-test
  (test-suite "Caller buffers for 1,240 chains of width 128"
    (test-case "independently verify all 10,078,720 result rows per request"
      (ten-million-query 128 ascent-engine-session-copy-integer-relation!))))

(def actor-ten-million-chains-512-list-test
  (test-suite "Complete mutable lists for 77 chains of width 512"
    (test-case "independently verify all 10,072,832 result rows per request"
      (ten-million-query 512))))

(def actor-ten-million-chains-512-buffer-test
  (test-suite "Caller buffers for 77 chains of width 512"
    (test-case "independently verify all 10,072,832 result rows per request"
      (ten-million-query 512 ascent-engine-session-copy-integer-relation!))))
