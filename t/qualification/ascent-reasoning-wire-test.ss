;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite test-case)
        (only-in :std/encoding/json
                 json->string string->json JSONReadOptions)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-source-snapshot reasoning-snapshot-digest)
        (only-in :gerbil-ascent/candidate/wire reasoning-wire-attempt))

(export ascent-reasoning-wire-test)

(def (request clauses)
  (json->string (hash (version 1) (candidate clauses)) sort-keys: #t))

(def (response source payload (work 100000))
  (string->json
   (reasoning-wire-attempt source payload work)
   (JSONReadOptions key-as-symbol: #f
                    array-as-vector: #f
                    object-as-hash: #t)))

(def (diagnostic-code reply)
  (hash-get (car (hash-get reply "diagnostics")) "code"))

(def (graph-proposal join (facts []) (target 3))
  (append
   (list
    (list "relation" "path" 2)
    (list "rule" (list "path" "?x" "?y")
          (list "edge" "?x" "?y"))
    (list "rule" (list "path" "?x" "?z")
          (list "path" "?x" "?y")
          (list "edge" join "?z")))
   facts
   (list (list "query" "path" 1 target)
         (list "limits" 16 32 64))))

(def ascent-reasoning-wire-test
  (test-suite "bounded JSON reasoning boundary"
    (test-case "model proposal, feedback, correction, and source generation"
      (let* ((first
              (reasoning-source-snapshot
               'graph 1 '((edge 2 ((1 2) (2 3))))))
             (bad
              (request
               '(("relation" "path" 2)
                 ("rule" ("path" "?x" "?y")
                         ("missing" "?x" "?y"))
                 ("query" "path" 1 3)
                 ("limits" 16 32 64))))
             (wrong (request (graph-proposal "?x")))
             (correct (request (graph-proposal "?y")))
             (rejected (response first bad))
             (wrong-answer (response first wrong))
             (right-answer (response first correct))
             (second
              (reasoning-source-snapshot
               'graph 2 '((edge 2 ((1 2))))))
             (withdrawn (response second correct))
             (overlay
              (response second
                        (request
                         (graph-proposal "?y"
                                         '(("fact" "edge" 2 3))))))
             (base-again (response second correct)))
        (check-equal? (hash-get rejected "status") "rejected")
        (check-equal? (diagnostic-code rejected) "unknown-relation")
        (check-equal?
         (hash-get (car (hash-get rejected "diagnostics")) "path")
         '("clause" 2 "body" 1))
        (check-equal? (hash-get wrong-answer "status") "complete")
        (check-equal? (hash-get wrong-answer "rows") '())
        (check-equal? (hash-get right-answer "rows") '((1 3)))
        (check-equal? (hash-get right-answer "rowsComplete") #t)
        (check-equal? (hash-get (hash-get right-answer "proof") "status")
                      "complete")
        (check-equal?
         (hash-get (hash-get right-answer "source") "digest")
         (reasoning-snapshot-digest first))
        (check-equal?
         (hash-get right-answer "attemptId")
         (string-append (reasoning-snapshot-digest first) ":"
                        (hash-get right-answer "candidateDigest")))
        (check-equal? (hash-get withdrawn "rows") '())
        (check-equal?
         (hash-get (hash-get withdrawn "source") "generation") 2)
        (check-equal? (hash-get overlay "rows") '((1 3)))
        (check-equal? (hash-get base-again "rows") '())
        (check-equal?
         (equal? (hash-get right-answer "attemptId")
                 (hash-get withdrawn "attemptId"))
         #f)
        (check-equal?
         (equal? (hash-get right-answer "candidateDigest")
                 (hash-get wrong-answer "candidateDigest"))
         #f)))
    (test-case "tagged characters preserve native scalar identity"
      (let* ((source
              (reasoning-source-snapshot
               'characters 1 '((letter 1 ((#\a))))))
             (datum
              (request
               (list
                (list "relation" "seen" 1)
                (list "rule" (list "seen" "?x")
                      (list "letter" "?x"))
                (list "query" "seen" (hash (char "a")))
                (list "limits" 8 8 8))))
             (reply (response source datum)))
        (check-equal? (hash-get reply "status") "complete")
        (check-equal?
         (hash-get (car (car (hash-get reply "rows"))) "char") "a")))
    (test-case "malformed, duplicate, null and deep JSON reject before solve"
      (let* ((source
              (reasoning-source-snapshot
               'graph 1 '((edge 2 ((1 2))))))
             (duplicate
              (response source
                        "{\"version\":1,\"version\":1,\"candidate\":[]}"))
             (other-version
              (response source "{\"version\":2,\"candidate\":[]}"))
             (null-value
              (response source
                        (request '(("query" "edge" 1 #!void)
                                   ("limits" 8 8 8)))))
             (deep
              (response source
                        (request
                         (let loop ((remaining 70) (value '()))
                           (if (zero? remaining)
                             (list value)
                             (loop (- remaining 1) (list value))))))))
        (check-equal? (hash-get duplicate "status") "rejected")
        (check-equal? (diagnostic-code duplicate) "malformed-json")
        (check-equal? (void? (hash-get duplicate "candidateDigest")) #t)
        (check-equal? (void? (hash-get duplicate "attemptId")) #t)
        (check-equal? (diagnostic-code other-version) "invalid-envelope")
        (check-equal? (hash-get null-value "status") "rejected")
        (check-equal? (diagnostic-code null-value) "invalid-value")
        (check-equal? (diagnostic-code deep) "invalid-json-bound")))
    (test-case "large answers are explicitly omitted from projection"
      (let* ((rows (map (lambda (value) (list value)) (iota 300)))
             (source
              (reasoning-source-snapshot
               'many 1 (list (list 'item 1 rows))))
             (reply
              (response
               source
               (request
                '(("relation" "copy" 1)
                  ("rule" ("copy" "?x") ("item" "?x"))
                  ("query" "copy" "?x")
                  ("limits" 1000 1000 1000))))))
        (check-equal? (hash-get reply "status") "complete")
        (check-equal? (hash-get reply "rowCount") 300)
        (check-equal? (hash-get reply "rowsComplete") #f)
        (check-equal? (hash-get reply "projectionStatus") "row-limit")
        (check-equal? (hash-get reply "rows") '())))
    (test-case "large scalar projection is marked incomplete"
      (let* ((value (string->symbol (make-string 1000 #\x)))
             (rows (map (lambda (index) (list value index)) (iota 100)))
             (source
              (reasoning-source-snapshot
               'large-values 1 (list (list 'item 2 rows))))
             (reply
              (response source
                        (request
                         '(("relation" "copy" 2)
                           ("rule" ("copy" "?x" "?y")
                                   ("item" "?x" "?y"))
                           ("query" "copy" "?x" "?y")
                           ("limits" 1000 1000 1000))))))
        (check-equal? (hash-get reply "status") "complete")
        (check-equal? (hash-get reply "rowCount") 100)
        (check-equal? (hash-get reply "rowsComplete") #f)
        (check-equal? (hash-get reply "projectionStatus") "size-limit")
        (check-equal? (hash-get reply "evidenceStatus") "omitted")))))
