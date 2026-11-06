;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Inert pair-tree operations shared by admission and evidence publication.
;;; This layer has no parser, snapshot, proof or evaluator dependencies.
(import (only-in :clan/poo/support/base lambda-match))
(export reasoning-bounded-data? candidate-copy-pairs)

;;; Private return state; constructed here and never escapes admission.
;; : DatumFrame
(defstruct datum-frame (pair depth tail?) final: #t)

;; : (forall (a) (-> a Boolean))
;; : (-> Datum Boolean)
(def (candidate-datum-scalar? value)
  (or (exact-integer? value) (boolean? value)
      (symbol? value) (char? value)))

;;; One structural traversal, two numeric lanes. The fast lane admits only
;;; nonnegative fixnum budgets up to 2^20; every internal depth/count is bounded
;;; by twice that ceiling plus one. The fallback preserves arbitrary arithmetic.
;; walk-bounded-datum
;; : (-> Datum BudgetNumber BudgetNumber AddSyntax SubtractSyntax CompareSyntax CompareSyntax Boolean)
;; | doc m%
;;     Instantiate the same traversal with proven bounded or generic counters.
;;
;;     # Examples
;;
;;     ```scheme
;;     (walk-bounded-datum '(a) 16 4 + - <= >)
;;     ;; => #t
;;     ```
;;   %
(defrule (walk-bounded-datum datum max-nodes max-depth counter+ counter- counter<= counter>)
  (let (active (make-hash-table-eq))
    ;; Activate only a previously charged single-branch prefix. Its other
    ;; child has already been admitted, so each return only clears identity.
    (def (activate prefix depth count remaining frames step stride)
      (cond
       ((zero? count) (visit prefix depth remaining frames))
       ((hash-get active prefix) #f)
       (else
        (hash-put! active prefix #t)
        (activate (step prefix) (counter+ depth stride) (counter- count 1) remaining
                  (cons (make-datum-frame prefix depth #t) frames) step stride))))
    ;; Scalar spines need no active entries or frames. Their bounded scan uses
    ;; a double-speed cdr cursor to reject cycles. A nested car activates only
    ;; the already checked prefix before ordinary depth-first traversal.
    (def (scan-spine start depth remaining frames)
      (let scan ((cursor start) (fast start) (left remaining) (count 0))
        (cond
         ((counter<= left 0) #f)
         ((pair? cursor)
          (let (head (car cursor))
            (cond
             ((pair? head)
              ;; Each prefix pair has an admitted car and a pending cdr.
              ;; Revisit only these count pairs; never rescan their subtrees.
              (activate start depth count left frames cdr 0))
             ((or (counter<= left 1)
                  (not (or (null? head) (candidate-datum-scalar? head)))) #f)
             (else
              (let* ((next (cdr cursor))
                     (next-fast (and (pair? fast)
                                     (let (tail (cdr fast))
                                       (and (pair? tail) (cdr tail))))))
                (if (and (pair? next) (eq? next next-fast))
                  #f
                  (scan next next-fast (counter- left 2) (counter+ count 1))))))))
         ((or (null? cursor) (candidate-datum-scalar? cursor))
          (resume (counter- left 1) frames))
         (else #f))))
    ;; A unary car chain has the same single-branch shape, with admitted null
    ;; cdrs. Charge each null once and advance pair depth on every car edge.
    ;; A branching pair activates the prefix before the ordinary DFS resumes.
    (def (scan-nest start depth remaining frames)
      (let scan ((cursor start) (fast start) (level depth) (left remaining) (count 0))
        (cond
         ((counter<= left 0) #f)
         ((pair? cursor)
          (cond
           ((counter> level max-depth) #f)
           ((not (null? (cdr cursor)))
            (activate start depth count left frames car 1))
           ((counter<= left 1) #f)
           (else
            (let* ((next (car cursor))
                   (next-fast (and (pair? fast)
                                   (let (head (car fast))
                                     (and (pair? head) (car head))))))
              (if (and (pair? next) (eq? next next-fast))
                #f
                (scan next next-fast (counter+ level 1) (counter- left 2) (counter+ count 1)))))))
         ((or (null? cursor) (candidate-datum-scalar? cursor))
          (resume (counter- left 1) frames))
         (else #f))))
    ;; A frame owns a deferred return: input pair, original depth, and whether
    ;; its cdr is being visited. Scalar children are charged without events.
    ;; Only caller-independent frames and the active identity table mutate.
    ;; Keep the pair active through both branches; clearing it only on return
    ;; distinguishes shared acyclic input from a back edge on the active path.
    (def (visit value depth remaining frames)
      (cond
       ((counter<= remaining 0) #f)
       ((pair? value)
        (if (or (counter> depth max-depth) (hash-get active value))
          #f
          (let (head (car value))
            (if (pair? head)
              (if (null? (cdr value))
                (scan-nest value depth remaining frames)
                (begin
                (hash-put! active value #t)
                (visit head (counter+ depth 1) (counter- remaining 1)
                       (cons (make-datum-frame value depth #f) frames))))
              (scan-spine value depth remaining frames)))))
       ((or (null? value) (candidate-datum-scalar? value))
        (resume (counter- remaining 1) frames))
       (else #f)))
    (def (resume remaining frames)
      (if (null? frames)
        #t
        ;; Frames are constructed only above and never escape. As in Gerbil's
        ;; optimizer, :- permits direct slot access after ownership proves the
        ;; record type; it does not disable checks on caller-owned data.
        (using (frame (car frames) :- datum-frame)
         (let (pair frame.pair)
          (if frame.tail?
            (begin
              (hash-put! active pair #f)
              (resume remaining (cdr frames)))
            (let (tail (cdr pair))
              (cond
               ((counter<= remaining 0) #f)
               ((pair? tail)
                (set! frame.tail? #t)
                (visit tail frame.depth remaining frames))
               ((or (null? tail) (candidate-datum-scalar? tail))
                (hash-put! active pair #f)
                (resume (counter- remaining 1) (cdr frames)))
               (else #f))))))))
    (visit datum 0 max-nodes [])))

;;; Walk untrusted pair trees without recursing through caller-owned input.
;;; The active-path check rejects cycles while allowing shared, acyclic rows.
;;; Cdr steps do not increase nesting depth, so a flat finite list is bounded
;;; by node count rather than an arbitrary list-length depth limit.
;; reasoning-bounded-data?
;;   : (forall (a) (-> a Integer Integer Boolean))
;;   : (-> Datum Integer Integer Boolean)
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
  (if (and (fixnum? max-nodes) (fx<= 0 max-nodes) (fx<= max-nodes 1048576)
           (fixnum? max-depth) (fx<= 0 max-depth) (fx<= max-depth 1048576))
    (walk-bounded-datum datum max-nodes max-depth fx+ fx- fx<= fx>)
    (walk-bounded-datum datum max-nodes max-depth + - <= >)))

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
  ((lambda-match
    ([head . tail]
     (cons (candidate-copy-pairs head) (candidate-copy-pairs tail)))
    (value value)) datum))
