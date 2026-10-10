;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Exact natural arithmetic truncated at a caller-owned budget, not a
;;; semantic bound. Zero caps and 0^0 are intentional parts of the contract.
(export relational-capped-product relational-capped-power)

(def (natural? value) (and (exact-integer? value) (>= value 0)))

(def (relational-capped-product cap left right)
  (unless (and (natural? cap) (natural? left) (natural? right))
    (error "capped arithmetic requires natural numbers"))
  (min cap (* (min cap left) (min cap right))))

(def (relational-capped-power cap base exponent)
  (unless (and (natural? cap) (natural? base) (natural? exponent))
    (error "capped arithmetic requires natural numbers"))
  (let (factor (min cap base))
    (let loop ((remaining exponent) (accumulator (min cap 1)))
      (cond ((zero? remaining) accumulator)
            ((zero? factor) 0)
            ((= factor 1) accumulator)
            ((>= accumulator cap) cap)
            (else (loop (- remaining 1)
                        (min cap (* accumulator factor))))))))
