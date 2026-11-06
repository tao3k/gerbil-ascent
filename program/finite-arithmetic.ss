;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Exact natural arithmetic truncated at a caller-owned budget, not a
;;; semantic bound. Zero caps and 0^0 are intentional parts of the contract.
(export relational-capped-product relational-capped-power)

;; : (forall (a) (-> a Boolean))
(def (natural? value) (and (exact-integer? value) (>= value 0)))

;; : (-> Natural Natural Natural Natural)
(def (relational-capped-product cap left right)
  (unless (and (natural? cap) (natural? left) (natural? right))
    (error "capped arithmetic requires natural numbers"))
  (min cap (* (min cap left) (min cap right))))

;; relational-capped-power
;; : (-> Natural Natural Natural Natural)
;; | doc m%
;;     Compute truncated exponentiation by squaring, including capped 0^0.
;;
;;     # Examples
;;
;;     ```scheme
;;     (relational-capped-power 10 3 2)
;;     ;; => 9
;;     ```
;;   %
(def (relational-capped-power cap base exponent)
  (unless (and (natural? cap) (natural? base) (natural? exponent))
    (error "capped arithmetic requires natural numbers"))
  (def (power remaining)
    (cond ((zero? remaining) (min cap 1))
          ((zero? base) 0)
          ((= base 1) (min cap 1))
          (else
           (let* ((half (power (quotient remaining 2)))
                  (square (min cap (* half half))))
             (if (odd? remaining) (min cap (* square (min cap base))) square)))))
  (cond ((zero? cap) 0)
        ((zero? exponent) (min cap 1))
        ((zero? base) 0)
        ((= base 1) (min cap 1))
        ;; For base >= 2, this bit bound proves saturation before recursion.
        ;; Huge exponent representations therefore cannot create deep stacks.
        ((>= exponent (integer-length cap)) cap)
        (else (power exponent))))
