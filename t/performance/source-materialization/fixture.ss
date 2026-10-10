;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object :gerbil-ascent/program/objects
        (only-in :std/error Error? Error-message)
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine)
        (rename-in (only-in :gerbil-ascent/t/performance/source-materialization/reference-session
                           gerbil-ascent-open-session) (gerbil-ascent-open-session old-open))
        (rename-in (only-in :gerbil-ascent/t/performance/source-materialization/reference-evaluate
                           gerbil-ascent-make-engine) (gerbil-ascent-make-engine old-engine)))
(export materialization-prepare materialization-consume materialization-verify!)

(def (materialization-prepare old? scenario)
  (let* ((wide? (memq scenario '(retained rejected replay)))
         (count (if wide? 8 0))
         (x (gerbil-ascent-variable 'x))
         (relations
          (append (list (gerbil-ascent-relation 'input 1 '((0)))
                        (gerbil-ascent-relation 'blocked 1 [])
                        (gerbil-ascent-relation 'output 1 []))
                  (map (lambda (i)
                         (gerbil-ascent-relation
                          (string->symbol (string-append "source" (number->string i)))
                          1 (map list (iota 1024)))) (iota count))))
         (program (gerbil-ascent-program relations
                    (list (gerbil-ascent-rule
                           (list (gerbil-ascent-atom 'output (list x)))
                           (list (gerbil-ascent-atom 'input (list x)))))
                    65536 65536 65536))
         (session (if (eq? scenario 'replay)
                    (if old? (old-engine program #t) (gerbil-ascent-make-engine program #t))
                    (if old? (old-open program) (gerbil-ascent-open-session program)))))
    ((.ref session '.run))
    ;; Persistent additions are prepared outside timing. Repeated complete cuts
    ;; still read all declarations and rows; no answer or provider check is cached.
    (for-each (lambda (relation)
                ((.ref session '.append-source!) (.ref relation 'name) '(1024)))
              (drop relations 3))
    ((.ref session '.run))
    (list session relations scenario)))

(def (projection session relations)
  (let (result ((.ref session '.run)))
    (list (.ref result 'finished)
          (map (lambda (relation)
                 (let (name (.ref relation 'name))
                   (cons name ((.ref result 'rows-of) name)))) relations))))

(def (materialization-consume prepared scenario)
  (with ([session relations _] prepared)
    (map
     (lambda (i)
       (let (rows (if (even? i) '((0)) []))
         (cond
          ((eq? scenario 'replay) ((.ref session '.replace-source!) 'blocked rows))
          ((eq? scenario 'rejected)
           (unless
             (with-catch
              (lambda (failure)
                (and (Error? failure)
                     (equal? (Error-message failure) "ASCENT replacement result was not accepted")))
              (lambda ()
                ((.ref session '.replace-sources!) (list (cons 'blocked rows)) (lambda (_) #f))
                #f))
             (error "rejected source cut did not retain its diagnostic")))
          (else ((.ref session '.replace-sources!) (list (cons 'blocked rows)))))
         (projection session relations)))
     (iota 4))))

(def (materialization-verify! prepared)
  (with ([session relations scenario] prepared)
    (for-each
     (lambda (snapshot i)
       (with ([finished rows] snapshot)
         (unless (and finished
                      (equal? (cdr (assq 'input rows)) '((0)))
                      (equal? (cdr (assq 'output rows)) '((0)))
                      (equal? (cdr (assq 'blocked rows))
                              (if (and (even? i) (not (eq? scenario 'rejected))) '((0)) []))
                      (andmap (lambda (entry)
                                (equal? (cdr entry) (map list (iota 1025)))) (drop rows 3)))
           (error "source materialization independent truth differs" scenario i))))
     (materialization-consume prepared scenario) (iota 4))))
