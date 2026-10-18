;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Test-only inert candidate transport over the qualified public corpus.
;;; Reference and model calls share the qualification's data and native API.
(import (only-in "./scheme-library-contract-test"
                 candidate weights support-phases contract-snapshot
                 study-cases study-repair-seed study-filter-seed)
        (only-in :gerbil-ascent/candidate/program candidate-variable? candidate-language-description)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-attempt reasoning-receipt-status reasoning-receipt-rows
                 reasoning-receipt-diagnostics reasoning-diagnostic-code
                 reasoning-diagnostic-path reasoning-verify-finite-receipt
                 reasoning-verify-stratified-receipt))
(export main)

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
               (member (car args) '("reference" "hypothetical" "initial" "evaluate"
                                    "description" "repair-seed" "filter-seed"
                                    "discriminator-reference" "discriminator-evaluate")))
    (error "unsupported support study mode"))
  (let (mode (car args))
    (cond
     ((equal? mode "description") (write (candidate-language-description)) (newline))
     ((equal? mode "repair-seed") (write study-repair-seed) (newline))
     ((equal? mode "filter-seed") (write study-filter-seed) (newline))
     (else
      (let* ((extended? (member mode '("discriminator-reference" "discriminator-evaluate")))
             (states (if extended? study-cases
                       (map (lambda (edges) (list edges '() weights '((0)))) support-phases)))
             (proposal
              (cond ((member mode '("reference" "discriminator-reference")) candidate)
                    ((equal? mode "hypothetical")
                     (cons 'candidate (cons '(fact edge 0 2) (cdr candidate))))
                    (else (read))))
             (first-source (apply contract-snapshot 0 (car states)))
             (first (reasoning-attempt first-source proposal 100000 20000)))
        (emit 0 first first-source proposal)
        (unless (equal? mode "initial")
          (for-each
           (lambda (generation state)
             (let* ((source (apply contract-snapshot generation state))
                    (receipt (reasoning-attempt source proposal 100000 20000)))
               (emit generation receipt source proposal)))
           (iota (- (length states) 1) 1) (cdr states))
          (emit 'stale first (apply contract-snapshot 1 (cadr states)) proposal))
        (displayln "END"))))))
