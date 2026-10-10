;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil-ascent/candidate/datum reasoning-bounded-data?)
        (only-in :gerbil-ascent/candidate/program scalar?)
        (only-in :gerbil-ascent/candidate/types reasoning-snapshot-valid?
                 reasoning-snapshot-relations reasoning-snapshot-identity
                 reasoning-snapshot-generation make-candidate-rejection
                 make-reasoning-diagnostic)
        (only-in :gerbil-ascent/candidate/reasoning reasoning-source-snapshot))
(export reasoning-withhold-source-snapshot)

;;; BRINK section 3.2 finite transfer. A grounding is (head-atom body-atoms).
;;; Validate the whole batch before copying a new snapshot. Every selected
;;; head and body atom must be an observed source fact, and no selected head
;;; may occur in ANY selected body. Groundings are caller claims: this checks
;;; removal/preservation, not rule validity, confidence or real-world truth.
;;; All duplicates of selected heads are removed; source row order is retained.
(def (reasoning-withhold-source-snapshot source generation groundings)
  (def (reject code path detail)
    (raise (make-candidate-rejection (make-reasoning-diagnostic code path detail))))
  (unless (reasoning-snapshot-valid? source)
    (reject 'invalid-snapshot '(snapshot) #f))
  (unless (and (exact-integer? generation)
               (> generation (reasoning-snapshot-generation source)))
    (reject 'invalid-generation '(generation) generation))
  (unless (and (reasoning-bounded-data? groundings 16384 128)
               (list? groundings) (<= (length groundings) 64))
    (reject 'invalid-groundings '(groundings) #f))
  (let ((schema (make-hash-table-eq)) (facts (make-hash-table))
        (heads (make-hash-table)) (protected (make-hash-table)))
    (for-each (lambda (entry)
                (hash-put! schema (car entry) (cadr entry))
                (for-each (lambda (row) (hash-put! facts (cons (car entry) row) #t))
                          (caddr entry)))
              (reasoning-snapshot-relations source))
    (def (check-atom atom path)
      (unless (and (list? atom) (pair? atom) (symbol? (car atom))
                   (hash-get schema (car atom))
                   (= (length (cdr atom)) (hash-ref schema (car atom)))
                   (andmap scalar? (cdr atom)))
        (reject 'invalid-ground-atom path atom))
      (unless (hash-get facts atom) (reject 'unobserved-ground-atom path atom)))
    (for-each
     (lambda (grounding index)
       (unless (and (list? grounding) (= (length grounding) 2)
                    (list? (cadr grounding)) (pair? (cadr grounding)))
         (reject 'invalid-grounding (list 'grounding index) grounding))
       (check-atom (car grounding) (list 'grounding index 'head))
       (hash-put! heads (car grounding) #t)
       (for-each (lambda (atom body-index)
                   (check-atom atom (list 'grounding index 'body body-index))
                   (hash-put! protected atom #t))
                 (cadr grounding) (iota (length (cadr grounding)))))
     groundings (iota (length groundings)))
    (for-each (lambda (grounding index)
                (when (hash-get protected (car grounding))
                  (reject 'withheld-head-protected (list 'grounding index 'head)
                          (car grounding))))
              groundings (iota (length groundings)))
    (reasoning-source-snapshot
     (reasoning-snapshot-identity source) generation
     (map (lambda (entry)
            (list (car entry) (cadr entry)
                  (filter (lambda (row) (not (hash-get heads (cons (car entry) row))))
                          (caddr entry))))
          (reasoning-snapshot-relations source)))))
