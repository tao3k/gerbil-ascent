;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop validate element? TypeError?)
        (only-in :gerbil-ascent/program/types GerbilAscentSessionContract)
        (only-in :gerbil-ascent/program/objects gerbil-ascent-program gerbil-ascent-relation)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine))
(export ascent-engine-contract-test)

(def ascent-engine-contract-test
  (test-suite "Engine methods and public Session admission"
    (test-case "the internal engine retains its complete public method shape"
      (def program
        (gerbil-ascent-program [(gerbil-ascent-relation 'input 1 '((1)))] [] 8 8 8))
      (def engine (gerbil-ascent-make-engine program #t))
      (check-equal? (element? GerbilAscentSessionContract engine) #t)
      (check-equal? (eq? engine (validate GerbilAscentSessionContract engine)) #t)
      (def first ((.ref engine '.run)))
      (check-equal? ((.ref first 'rows-of) 'input) '((1)))
      ((.ref engine '.append-source!) 'input '(2))
      (def second ((.ref engine '.run)))
      (check-equal? (length ((.ref second 'rows-of) 'input)) 2))
    (test-case "public method getters are demanded once in the original order"
      (def observed [])
      (def method (lambda args (void)))
      (def (capture name) (set! observed (cons name observed)) method)
      (def session
        (.o (:: @ (.ref GerbilAscentSessionContract 'proto))
          (.append-source! (capture 'append))
          (.replace-source! (capture 'replace))
          (.run (capture 'run))
          (unselected (error "unselected Session getter demanded"))))
      (check-equal? (eq? session (validate GerbilAscentSessionContract session)) #t)
      (check-equal? (reverse observed) '(append replace run)))
    (test-case "prototype refusal occurs before public getter effects"
      (def observed [])
      (def session
        (.o (.append-source! (begin (set! observed (cons 'append observed)) (lambda args (void))))
            (.replace-source! (begin (set! observed (cons 'replace observed)) (lambda args (void))))
            (.run (begin (set! observed (cons 'run observed)) (lambda args (void))))))
      (check-exception (validate GerbilAscentSessionContract session) TypeError?)
      (check-equal? observed []))))
