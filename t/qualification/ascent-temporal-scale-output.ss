;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Matched star topology, same candidate, sources and evidence budgets.
(import (only-in :gerbil-ascent/temporal/lens
                 temporal-lens temporal-source temporal-solve temporal-status
                 temporal-rows)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-source-snapshot reasoning-attempt
                 reasoning-receipt-rows reasoning-verify-finite-receipt
                 reasoning-verify-stratified-receipt))
(export main)
(def candidate
  '(candidate (relation reach 2)
     (rule (reach ?x ?y) (root ?x) (parent ?x ?y))
     (rule (reach ?x ?z) (reach ?x ?y) (parent ?y ?z))
     (query reach ?x ?y) (limits 1024 4096 4096)))
(def (now) (time->seconds (current-time)))
(def (same-set? a b)
  (and (= (length a) (length b)) (andmap (lambda (x) (if (member x b) #t #f)) a)))
(def (main . args)
  (unless (null? args) (error "temporal scale takes no arguments"))
  (for-each
   (lambda (size)
     (let* ((nodes (map (lambda (i) (string->symbol (string-append "n" (number->string i)))) (iota size)))
            (root (car nodes))
            (events (map (lambda (id i) (list id i 0)) nodes (iota size)))
            (edges (map (lambda (id) (list root id)) (cdr nodes)))
            (lens (temporal-lens 0 'positions 0 size 0 'cut nodes 1 #t))
            (source (temporal-source 'scale 0 'positions events edges)))
       (def (plain)
         (let* ((snapshot (reasoning-source-snapshot 'scale 0
                            (list (list 'parent 2 edges) (list 'root 1 (list (list root))))))
                (receipt (reasoning-attempt snapshot candidate 100000 100000)))
           (unless (and (same-set? (reasoning-receipt-rows receipt) edges)
                        (eq? (reasoning-verify-finite-receipt receipt snapshot candidate 100000) 'valid)
                        (eq? (reasoning-verify-stratified-receipt receipt snapshot candidate 100000) 'valid))
             (error "plain matched scale failed" size))))
       (def (temporal)
         (let (answer (temporal-solve lens source root))
           (unless (and (eq? (temporal-status answer) 'complete)
                        (same-set? (temporal-rows answer) edges))
             (error "temporal matched scale failed" size))))
       (plain) (temporal)
       (for-each
        (lambda (rep)
          (let ((plain-time 0) (temporal-time 0))
            (def (run f)
              (let (start (now)) (f) (* 1000 (- (now) start))))
            (if (even? rep)
              (begin (set! plain-time (run plain)) (set! temporal-time (run temporal)))
              (begin (set! temporal-time (run temporal)) (set! plain-time (run plain))))
            (displayln "TEMPORAL-SCALE " size " " rep " " plain-time " " temporal-time)
            (force-output)))
        (iota 5))))
   '(8 32 128))
  (displayln "END") (force-output))
