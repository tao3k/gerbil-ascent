;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object :gerbil-ascent/program/objects
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine)
        (rename-in (only-in :gerbil-ascent/t/performance/source-snapshot/reference-session
                           gerbil-ascent-open-session) (gerbil-ascent-open-session old-open))
        (rename-in (only-in :gerbil-ascent/t/performance/source-snapshot/reference-evaluate
                           gerbil-ascent-make-engine) (gerbil-ascent-make-engine old-engine)))
(export snapshot-program snapshot-prepare snapshot-consume)

(def (snapshot-program count positive? (dense? #f))
  (let* ((x (gerbil-ascent-variable 'x))
         (input (gerbil-ascent-atom 'input (list x)))
         (output (gerbil-ascent-atom 'output (list x))))
    (gerbil-ascent-program
     (append (list (gerbil-ascent-relation 'input 1 '((0)))
                   (gerbil-ascent-relation 'blocked 1 [])
                   (gerbil-ascent-relation 'output 1 []))
             (map (lambda (index)
                    (gerbil-ascent-relation
                     (string->symbol (string-append "unused" (number->string index))) 1
                     (if dense? '((10) (11) (12) (13)) [])))
                  (iota count)))
     (list (gerbil-ascent-rule (list output)
              (if positive? (list input)
                (list input (gerbil-ascent-negation 'blocked (list x))))))
     4096 4096 8192)))

(def (snapshot-prepare old? scenario)
  (let* ((replay? (eq? scenario 'replay))
         (positive? (eq? scenario 'positive))
         (program (snapshot-program (if (eq? scenario 'small) 0 64) positive?
                                   (eq? scenario 'dense)))
         (session (if replay?
                    (if old? (old-engine program #t) (gerbil-ascent-make-engine program #t))
                    (if old? (old-open program) (gerbil-ascent-open-session program)))))
    ((.ref session '.run))
    (when positive? ((.ref session '.replace-sources!) (list (cons 'input []))))
    (cons session (.ref program 'relations))))

(def (snapshot-projection result declarations)
  (list (.ref result 'finished) (.ref result 'evaluation-path)
        (.ref result 'reused-relations) (.ref result 'active-rule-count)
        (map (lambda (relation)
               (let (name (.ref relation 'name))
                 (cons name ((.ref result 'rows-of) name)))) declarations)))

(def (snapshot-consume prepared scenario)
  (with ([session . declarations] prepared)
    (map (lambda (index)
           (let ((rows (if (even? index) '((0)) []))
                 (name (if (eq? scenario 'positive) 'input 'blocked)))
             (if (eq? scenario 'replay)
               (begin
                 ((.ref session '.append-source!) 'blocked '(0))
                 (let (blocked (snapshot-projection ((.ref session '.run)) declarations))
                   ((.ref session '.replace-source!) 'blocked [])
                   (list blocked (snapshot-projection ((.ref session '.run)) declarations))))
               (begin
                 ((.ref session '.replace-sources!) (list (cons name rows)))
                 (snapshot-projection ((.ref session '.run)) declarations)))))
         (iota 4))))
