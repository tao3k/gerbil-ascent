;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Test-only inert candidate transport over the qualified public corpus.
;;; Reference and model calls share the qualification's data and native API.
(import (only-in "./scheme-library-contract-test"
                 candidate weights support-phases contract-snapshot)
        (only-in :gerbil-ascent/candidate/program candidate-variable?)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-attempt reasoning-receipt-status reasoning-receipt-rows
                 reasoning-receipt-diagnostics reasoning-diagnostic-code
                 reasoning-diagnostic-path reasoning-verify-finite-receipt
                 reasoning-verify-stratified-receipt))
(export main)

(def (snapshot generation edges)
  (contract-snapshot generation edges '() weights '((0))))

(def (task-shape proposal)
  (if (and (list? proposal) (pair? proposal) (eq? (car proposal) 'candidate)
           (member '(limits 16 64 128) (cdr proposal))
           (not (ormap (lambda (clause)
                         (and (pair? clause) (eq? (car clause) 'fact)))
                       (cdr proposal))))
    (if (ormap (lambda (clause)
                 (and (list? clause) (= (length clause) 4)
                      (eq? (car clause) 'query) (eq? (cadr clause) 'summary)
                      (candidate-variable? (caddr clause))
                      (candidate-variable? (cadddr clause))))
               (cdr proposal))
      'task-shape 'outside-task-shape)
    'outside-task-shape))

(def (emit generation receipt source proposal)
  (let (fields
        (list generation (reasoning-receipt-status receipt)
              (reasoning-receipt-rows receipt)
              (reasoning-verify-finite-receipt receipt source proposal 20000)
              (reasoning-verify-stratified-receipt receipt source proposal 20000)
              (task-shape proposal)
              (map (lambda (diagnostic)
                     (list (reasoning-diagnostic-code diagnostic)
                           (reasoning-diagnostic-path diagnostic)))
                   (reasoning-receipt-diagnostics receipt))))
    (write (car fields))
    (for-each (lambda (field) (display #\tab) (write field)) (cdr fields))
    (newline)))

(def (main . args)
  (unless (and (= (length args) 1)
               (member (car args) '("reference" "hypothetical" "initial" "evaluate")))
    (error "support study requires reference, hypothetical, initial or evaluate mode"))
  (let* ((mode (car args))
         (proposal
          (cond ((equal? mode "reference") candidate)
                ((equal? mode "hypothetical")
                 (cons 'candidate (cons '(fact edge 0 2) (cdr candidate))))
                (else (read))))
         (first-source (snapshot 0 (car support-phases)))
         (first (reasoning-attempt first-source proposal 100000 20000)))
    (emit 0 first first-source proposal)
    (unless (equal? mode "initial")
      (for-each
       (lambda (generation edges)
         (let* ((source (snapshot generation edges))
                (receipt (reasoning-attempt source proposal 100000 20000)))
           (emit generation receipt source proposal)))
       '(1 2 3) (cdr support-phases))
      (emit 'stale first (snapshot 1 (cadr support-phases)) proposal))
    (displayln "END")))
