;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Translation validation at the compiler/cache boundary. The checker owns a
;;; separate symbol map; it never consumes the compiler's mutable slot table.
;;; Stream over actual descriptors and build a column view only when indexed.
;;; Host callbacks keep their separate admission protocol. This certificate
;;; covers the callback-free positive fragment.
(import (only-in "descriptor-stream.ss" gerbil-ascent-certificate-terms!
                 gerbil-ascent-certificate-keys?))
(export gerbil-ascent-positive-certificate?)

;; : (-> Heads Body PositivePlan Boolean)
(def (gerbil-ascent-positive-certificate? heads body plan)
  (let/cc reject
    (def (require condition) (unless condition (reject #f)))
    (def slots (make-hash-table-eq))
    (def count 0)
    (def (check-terms! sources actions head?)
      (let (next (gerbil-ascent-certificate-terms! sources actions slots count head?))
        (require next)
        (set! count next)))
    (require (and (vector? plan) (= (vector-length plan) 5)
                  (eq? (vector-ref plan 3) #t)
                  (exact-integer? (vector-ref plan 2))
                  (exact-integer? (vector-ref plan 4))))
    (let ((actions (vector-ref plan 1)) (outputs (vector-ref plan 0)))
      (require (and (list? actions) (= (length actions) (length body))
                    (list? outputs) (= (length outputs) (length heads))))
      (for-each
        (lambda (clause action)
          (require (and (eq? (vector-ref clause 0) 'atom)
                        (vector? action) (= (vector-length action) 5)))
          (let* ((atom (vector-ref clause 1)) (terms (vector-ref atom 1))
                 (columns (vector-ref atom 2))
                 (slotted (vector-ref action 1)) (keys (vector-ref action 2)))
            (require (eq? (vector-ref action 0) atom))
            ;; Keys observe the independent map before this atom introduces slots.
            (require (gerbil-ascent-certificate-keys? terms columns keys slots))
            (check-terms! terms slotted #f))) body actions)
      (for-each
        (lambda (head output)
          (require (and (vector? output) (= (vector-length output) 3)
                        (eq? (vector-ref output 0) head)))
          (check-terms! (vector-ref head 1) (vector-ref output 1) #t)) heads outputs)
      (require (and (= (vector-ref plan 2) count)
                    (= (vector-ref plan 4) (length body))))
      #t)))
