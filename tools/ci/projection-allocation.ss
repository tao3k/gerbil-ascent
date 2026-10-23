;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Scoped Scheme allocation diagnosis only; not a performance admission rule.
(import (only-in :gerbil-ascent/interface/engine-api ascent-engine-call)
        (only-in :std/misc/ports read-file-string))
(def owner
  (hash-ref (ascent-engine-call
    (hash ("operation" "module-source-open") ("trusted" #t)
          ("source" (read-file-string "t/qualification/evidence-api-module.ss")))) "owner"))
(def handle
  (hash-ref (ascent-engine-call
    (hash ("operation" "owner-program") ("owner" owner)
          ("constructor" "make-aggregate") ("arguments" '((1 2 4))))) "handle"))
(def (project)
  (let (value (ascent-engine-call (hash ("operation" "source-projection") ("handle" handle))))
    (unless (equal? (hash-ref value "status") "supported") (error "projection unsupported"))
    (let (relations (hash-ref (hash-ref value "program") "relations"))
      (unless (and (= (length relations) 2)
                   (equal? (hash-ref (car relations) "rows") '((1) (2) (4))))
        (error "projection rows changed")))))
(project)
(displayln "PROJECTION-ALLOCATION iterations=256 diagnostic_only=true")
(def allocation (make-f64vector 2))
(##get-bytes-allocated! allocation 0)
(def stats (##exec-stats
  (lambda () (let loop ((left 256)) (unless (= left 0) (project) (loop (- left 1)))))))
(##get-bytes-allocated! allocation 1)
(def (stat key) (cdr (assq key stats)))
(def reported (stat 'bytes-allocated))
(def raw-start (inexact->exact (f64vector-ref allocation 0)))
(def raw-end (inexact->exact (f64vector-ref allocation 1)))
(unless (and (exact-integer? reported) (<= 0 reported)
             (<= 0 raw-start raw-end) (< raw-end (expt 2 53))
             (<= reported (- raw-end raw-start)))
  (error "invalid scoped allocation counter" reported raw-start raw-end))
;;; Normal-return, nonnested Scheme scope. The raw snapshots expose SDK counter
;;; anomalies; they are not an independently proven allocator implementation.
(write (list 'projection-work-v1 256 (stat 'bytes-allocated) (stat 'nb-gcs)
             (stat 'user-time) (stat 'sys-time) (stat 'gc-real-time)
             raw-start raw-end))
(newline)
