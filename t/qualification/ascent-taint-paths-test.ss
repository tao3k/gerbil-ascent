;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite test-case check-equal?)
        (only-in :clan/poo/object .ref)
        :gerbil-ascent/applications/taint-paths
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session
          gerbil-ascent-session-run gerbil-ascent-session-run-timeout
          gerbil-ascent-session-replace-source!))
(export ascent-taint-paths-test)
(def (alerts result)
  (check-equal? (.ref result 'finished) #t)
  ((.ref result 'rows-of) 'taint_alert))
;; Independent graph search, with sanitizer admission before enqueueing.
(def (reachable? edges blocked)
  (let walk ((pending (if (member 0 blocked) [] '(0))) (seen []))
    (cond ((null? pending) #f)
          ((= (car pending) 2) #t)
          ((member (car pending) seen) (walk (cdr pending) seen))
          (else (walk (append (filter-map (lambda (edge)
                   (and (= (car edge) (car pending))
                        (not (member (cadr edge) blocked)) (cadr edge))) edges)
                     (cdr pending)) (cons (car pending) seen))))))
(def (subset items mask)
  (filter-map (lambda (item i)
    (and (not (zero? (bitwise-and mask (arithmetic-shift 1 i)))) item)) items (iota (length items))))
(def ascent-taint-paths-test
  (test-suite "IRIS finite unsanitized path transfer"
    (test-case "all three-node graphs and sanitizer sets match independent search"
      (for-each (lambda (mask)
        (let (edges (subset '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)) mask))
          (for-each (lambda (blocked-mask)
            (let* ((blocked (subset '(0 1 2) blocked-mask))
                   (result (gerbil-ascent-evaluate-program
                     (gerbil-ascent-taint-path-program edges '((0)) '((2)) (map list blocked)))))
              (check-equal? (alerts result) (if (reachable? edges blocked) '((0 2)) [])))) (iota 8)))
        (when (zero? (modulo (+ mask 1) 8))
          (displayln "TAINT-GRAPHS " (+ mask 1) "/64") (force-output))) (iota 64)))
    (test-case "an interior sanitizer blocks only paths traversing it"
      (check-equal? (alerts (gerbil-ascent-evaluate-program
        (gerbil-ascent-taint-path-program '((0 1) (1 2)) '((0)) '((2)) '((1))))) [])
      (check-equal? (alerts (gerbil-ascent-evaluate-program
        (gerbil-ascent-taint-path-program '((0 1) (1 2) (0 2)) '((0)) '((2)) '((1))))) '((0 2)))
      (check-equal? (alerts (gerbil-ascent-evaluate-program
        (gerbil-ascent-taint-path-program [] '((0)) '((0)) []))) '((0 0))))
    (test-case "sanitizer replacement and refused work preserve held results"
      (let* ((p (gerbil-ascent-taint-path-program '((0 1) (1 2)) '((0)) '((2)) []))
             (session (gerbil-ascent-open-session p)) (held (gerbil-ascent-session-run session)))
        (check-equal? (alerts held) '((0 2)))
        (gerbil-ascent-session-replace-source! session 'taint_sanitizer '((1)))
        (check-equal? (alerts (gerbil-ascent-session-run session)) [])
        (check-equal? (alerts held) '((0 2)))
        (gerbil-ascent-session-replace-source! session 'taint_sanitizer [])
        (check-equal? (.ref (gerbil-ascent-session-run-timeout session 0) 'finished) #f)
        (check-equal? (alerts held) '((0 2)))
        (check-equal? (alerts (gerbil-ascent-session-run session)) '((0 2)))))))
