;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-replace-source!
                 gerbil-ascent-session-run)
        (only-in :gerbil-ascent/program/syntax ascent))

(export main ascent-timing-test)

(def (timed-program rows)
  (ascent
   (relation seed (value) rows)
   (relation copied (value))
   ((copied x) <-- (seed x))
   (bounds 32 32 64)))

(def (timing-values result)
  (.ref result 'rule-time-nanoseconds))

(def (timing-valid? result)
  (let (times (timing-values result))
    (and (list? times) (= (length times) 1)
         (exact-integer? (car times)) (>= (car times) 0))))

(def ascent-timing-test
  (test-suite "ASCENT per-rule timing option"
    (poo-flow-test-case "timed result and retained snapshots"
      (let* ((session (gerbil-ascent-open-session
                       (timed-program '((1)))
                       measure-rule-times?: #t))
             (first (gerbil-ascent-session-run session)))
        (check-equal? ((.ref first 'rows-of) 'copied) '((1)))
        (check-equal? ((.ref first 'relation-sizes))
                      '((seed . 1) (copied . 1)))
        (check-equal? (timing-valid? first) #t)
        (check-equal?
         (.ref (gerbil-ascent-session-run
                (gerbil-ascent-open-session (timed-program '((1)))))
               'rule-time-nanoseconds)
         #f)
        (gerbil-ascent-session-append-source! session 'seed '(2))
        (let (second (gerbil-ascent-session-run session))
          (check-equal? ((.ref second 'rows-of) 'copied) '((1) (2)))
          (check-equal? ((.ref second 'relation-sizes))
                        '((seed . 2) (copied . 2)))
          (check-equal? (timing-valid? second) #t)
          (check-equal? ((.ref first 'rows-of) 'copied) '((1)))
          (check-equal? ((.ref first 'relation-sizes))
                        '((seed . 1) (copied . 1))))
        (gerbil-ascent-session-replace-source! session 'seed '((3)))
        (let (third (gerbil-ascent-session-run session))
          (check-equal? ((.ref third 'rows-of) 'copied) '((3)))
          (check-equal? ((.ref third 'relation-sizes))
                        '((seed . 1) (copied . 1)))
          (check-equal? (timing-valid? third) #t))))))

(def (main . args)
  (unless (null? args)
    (error "ASCENT timed oracle reads rows from stdin"))
  (let* ((rows (read))
         (result (gerbil-ascent-session-run
                  (gerbil-ascent-open-session
                   (timed-program rows) measure-rule-times?: #t))))
    (for-each
     (lambda (row)
       (display "copied") (display #\tab) (display (car row)) (newline))
     ((.ref result 'rows-of) 'copied))
    (unless (timing-valid? result)
      (error "ASCENT rule timing missing"))
    (for-each
     (lambda (entry)
       (display "SIZE") (display #\tab)
       (display (car entry)) (display #\tab)
       (display (cdr entry)) (newline))
     ((.ref result 'relation-sizes)))
    (display "TIMING\t1\n")
    (display "END\n")
    (force-output)))
