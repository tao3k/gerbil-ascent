;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/candidate/provenance
        (prefix-in :gerbil-ascent/t/performance/proof-verification/reference old-)
        (only-in :gerbil-ascent/candidate/checked-program reasoning-source-snapshot)
        (only-in :gerbil-ascent/candidate/types make-reasoning-candidate))
(export verification-prepare verification-consume verification-expected
        verification-verify!)

;; Independent scalar truth: every even source value maps to its double and #f.
(def (verification-prepare old? scenario)
  (let* ((arity (case scenario ((wide) 32) ((mixed) 16) (else 2)))
         (count (case scenario ((wide) 512) ((mixed forged) 256) ((cold) 16) (else 2)))
         (names (map (lambda (i) (string->symbol (string-append "?x" (number->string i)))) (iota arity)))
         (rows (map (lambda (i) (cons (* i 2) (make-list (- arity 1) #f))) (iota count)))
         (snapshot (reasoning-source-snapshot 'verification 0 (list (list 'edge arity rows))))
         (source? (eq? scenario 'source))
         (body (append (list (cons 'edge names))
                       (if (eq? scenario 'mixed) (list (cons 'edge names)) [])
                       (make-list (if (memq scenario '(wide mixed forged)) 8 1)
                                  '(where (even? ?x0)))
                       '((compute ?value (+ ?x0 ?x0)) (compute ?flag (identity ?x1)))))
         (spec (make-reasoning-candidate (if source? [] '((out . 2))) []
                 (if source? [] (list (vector '(out ?value ?flag) body 'rule)))
                 (vector (if source? (cons 'edge names) '(out ?value ?flag)) 0)
                 '(2048 8192 16384)))
         (expected (if source? rows (map (lambda (i) (list (* i 4) #f)) (iota count))))
         (proof ((if old? old-candidate-positive-proof candidate-positive-proof)
                  snapshot spec 'digest 'complete expected 1000000)))
    (unless (eq? ((if old? old-positive-proof-status positive-proof-status) proof) 'complete)
      (error "verification fixture producer did not complete" scenario))
    (when (eq? scenario 'forged)
      ;; Invalid final derivation, after the full validated predecessor prefix.
      (set-car! ((if old? old-proof-node-row proof-node-row)
                  (car (last-pair ((if old? old-positive-proof-nodes positive-proof-nodes) proof)))) -1))
    (vector old? snapshot spec expected proof)))

(def (verification-consume state scenario old?)
  (with (#(_ snapshot spec expected proof) state)
    (let (candidate
          (if (eq? scenario 'cold)
            ((if old? old-candidate-positive-proof candidate-positive-proof)
             snapshot spec 'digest 'complete expected 1000000)
            proof))
      ((if old? old-candidate-verify-positive-proof candidate-verify-positive-proof)
       snapshot spec 'digest 'complete expected candidate 4096))))
(def (verification-expected _state scenario) (not (eq? scenario 'forged)))
(def (verification-verify! state scenario old?)
  (unless (eq? (verification-consume state scenario old?) (verification-expected state scenario))
    (error "positive proof independent verdict differs" scenario)))
