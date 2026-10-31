;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (prefix-in :gerbil-ascent/t/performance/stratified-replay/reference-finite old-)
        :gerbil-ascent/candidate/stratified-proof
        :gerbil-ascent/candidate/stratified-producer
        (prefix-in :gerbil-ascent/t/performance/stratified-replay/reference-proof old-)
        (prefix-in :gerbil-ascent/t/performance/stratified-replay/reference-producer old-)
        (only-in :gerbil-ascent/candidate/checked-program reasoning-source-snapshot)
        (only-in :gerbil-ascent/candidate/finite-evidence candidate-finite-evidence finite-evidence-closure)
        (only-in :gerbil-ascent/candidate/types make-reasoning-candidate))
(export stratified-prepare stratified-consume stratified-expected)

;;; Independent arithmetic truth: each group sums 1..size; no solve result
;;; supplies the expected answer. Both consumers receive the same ordered proof.
(def (stratified-prepare old? scenario)
  (let* ((arity (if (memq scenario '(wide produce)) 32 2))
         (count (if (memq scenario '(wide produce forged)) 128 2))
         (names (map (lambda (i) (string->symbol (string-append "?v" (number->string i)))) (iota arity)))
         (rows (map (lambda (i) (cons 1 (cons (+ i 1) (make-list (- arity 2) #f)))) (iota count)))
         (snapshot (reasoning-source-snapshot 'stratified-replay 1
                     (list '(root 1 ((1))) (list 'weight arity rows))))
         (source? (eq? scenario 'source))
         (spec (make-reasoning-candidate (if source? [] '((total . 2))) []
                 (if source? []
                   (list (vector '(total ?v0 ?total)
                           (list '(root ?v0) (list 'reduce '?total '(sum ?v1) (cons 'weight names))) 7)))
                 (vector (if source? '(root ?r) '(total ?r ?n)) 0)
                 '(4096 4096 8192)))
         (expected (if source? '((1)) (list (list 1 (quotient (* count (+ count 1)) 2)))))
         (finite (candidate-finite-evidence snapshot spec 'digest 'complete expected 1000000))
         (old-finite (old-candidate-finite-evidence snapshot spec 'digest 'complete expected 1000000)))
    (unless (equal? (old-finite-evidence-closure old-finite) (finite-evidence-closure finite))
      (error "independent closures differ" scenario))
    (let-values (((status proof)
                  (old-candidate-produce-stratified-proof snapshot spec 'digest 'complete expected old-finite 1000000 1000000)))
      (unless (eq? status 'complete) (error "stratified fixture did not complete" scenario status))
      (when (eq? scenario 'forged)
        (set-car! (caddr (car (last-pair (cadr proof)))) -1))
      (vector snapshot spec expected finite proof old-finite))))

(def (stratified-consume state scenario old?)
  (with (#(snapshot spec expected new-finite proof old-finite) state)
    (let (finite (if old? old-finite new-finite))
    (if (memq scenario '(produce cold))
      (let-values (((status supplied)
                    ((if old? old-candidate-produce-stratified-proof candidate-produce-stratified-proof)
                     snapshot spec 'digest 'complete expected finite 1000000 1000000)))
        (list status supplied))
      ((if old? old-candidate-verify-stratified-proof candidate-verify-stratified-proof)
       snapshot spec 'digest 'complete expected finite 1000000 proof 1000000)))))
(def (stratified-expected state scenario)
  (cond ((memq scenario '(produce cold)) (list 'complete (vector-ref state 4)))
        ((eq? scenario 'forged) 'invalid)
        (else 'valid)))
