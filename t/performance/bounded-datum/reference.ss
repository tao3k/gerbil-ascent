;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Inert pair-tree operations shared by admission and evidence publication.
;;; This layer has no parser, snapshot, proof or evaluator dependencies.
(export reasoning-bounded-data? candidate-copy-pairs)

;; : (forall (a) (-> a Boolean))
;; : (-> Datum Boolean)
(def (candidate-datum-scalar? value)
  (or (exact-integer? value) (boolean? value)
      (symbol? value) (char? value)))

;;; Walk untrusted pair trees without recursing through caller-owned input.
;;; The active-path check rejects cycles while allowing shared, acyclic rows.
;;; Cdr steps do not increase nesting depth, so a flat finite list is bounded
;;; by node count rather than an arbitrary list-length depth limit.
;; reasoning-bounded-data?
;;   : (forall (a) (-> a Nat Nat Boolean))
;;   : (-> Datum Nat Nat Boolean)
;;   | doc m%
;;       Check an inert scalar/pair tree before any list traversal or digest.
;;       The result is false for cycles, executable leaves or work exhaustion.
;;       Sharing between finite branches is allowed.
;;
;;       # Examples
;;
;;       ```scheme
;;       (reasoning-bounded-data? '(edge 1 2) 16 8)
;;       ;; => #t
;;       ```
;;     %
(def (reasoning-bounded-data? datum max-nodes max-depth)
  (let (active (make-hash-table-eq))
    (let loop ((pending (list (vector 'enter datum 0)))
               (remaining max-nodes))
      (if (null? pending)
        #t
        (let* ((item (car pending))
               (rest (cdr pending))
               (kind (vector-ref item 0))
               (value (vector-ref item 1))
               (depth (vector-ref item 2)))
          (if (eq? kind 'exit)
            (begin (hash-put! active value #f)
                   (loop rest remaining))
            (cond
             ((<= remaining 0) #f)
             ((pair? value)
              (if (or (> depth max-depth) (hash-get active value))
                #f
                (begin
                  (hash-put! active value #t)
                  (loop
                   (cons (vector 'enter (car value) (+ depth 1))
                         (cons (vector 'enter (cdr value) depth)
                               (cons (vector 'exit value depth) rest)))
                   (- remaining 1)))))
             ((or (null? value) (candidate-datum-scalar? value))
              (loop rest (- remaining 1)))
             (else #f))))))))

;;; Copy every pair, including nested cars and improper tails. Leaves retain
;;; identity. Callers establish finite inert data before copying; this operation
;;; neither validates nor admits input and intentionally does not preserve pair
;;; sharing. No caller-owned pair may escape into a published description or receipt.
;; candidate-copy-pairs
;;   : (forall (a) (-> a a))
;;   : (-> FiniteInertDatum DetachedDatum)
;;   | doc m%
;;       Detach all pairs in an already finite datum, preserving leaf values.
;;       Caller validation precedes this operation; cyclic input is unsupported.
;;
;;       # Examples
;;
;;       ```scheme
;;       (candidate-copy-pairs '((1 . 2) #f))
;;       ;; => '((1 . 2) #f), with fresh pairs
;;       ```
;;     %
(def (candidate-copy-pairs datum)
  (match datum
    ([head . tail]
     (cons (candidate-copy-pairs head) (candidate-copy-pairs tail)))
    (else datum)))
