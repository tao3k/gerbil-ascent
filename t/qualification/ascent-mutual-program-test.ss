;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite test-case)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-mutual-program-fixture
                 ascent-mutual-program ascent-mutual-evaluate)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-run))

(export ascent-mutual-program-test)

(def (same-rows? left right)
  (and (= (length left) (length right))
       (andmap (lambda (row) (member row right)) left)))

(def ascent-mutual-program-test
  (test-suite "ASCENT mutually recursive relations"
    (test-case "cycle reaches a fixed point across two relations"
      (let* ((result (ascent-mutual-evaluate
                      '((1 2) (2 3) (3 1))))
             (rows-of (.ref result 'rows-of)))
        (check-equal? (not (not (same-rows? (rows-of 'path0)
                                           '((1 1) (1 2) (1 3)
                                             (2 1) (2 2) (2 3)
                                             (3 1) (3 2) (3 3))))) #t)
        (check-equal? (length (rows-of 'path1)) 9)
        (check-equal? (not (not (same-rows? (rows-of 'witness)
                                           '((1) (2) (3))))) #t)))
    (test-case "source order does not change the fixed point"
      (let* ((first (ascent-mutual-evaluate
                     '((1 2) (2 3) (3 1))))
             (reverse-source (ascent-mutual-evaluate
                              '((3 1) (2 3) (1 2)))))
        (for-each
         (lambda (name)
           (check-equal?
            (not (not (same-rows? ((.ref first 'rows-of) name)
                                  ((.ref reverse-source 'rows-of) name))))
            #t))
         '(path0 path1 witness))))
    (test-case
      "retained multi-head SCC matches fresh snapshots after source additions"
      (let* ((session
              (gerbil-ascent-open-session
               (ascent-mutual-program '((1 2)))))
             (first (gerbil-ascent-session-run session)))
        (check-equal? ((.ref first 'rows-of) 'path0) '((1 2)))
        (check-equal? ((.ref first 'rows-of) 'path1) [])
        (check-equal? ((.ref first 'rows-of) 'witness) [])
        (gerbil-ascent-session-append-source! session 'edge '(2 3))
        (let* ((second (gerbil-ascent-session-run session))
               (fresh (ascent-mutual-evaluate '((1 2) (2 3)))))
          (for-each
           (lambda (name)
             (check-equal?
              (not (not (same-rows? ((.ref second 'rows-of) name)
                                    ((.ref fresh 'rows-of) name))))
              #t))
           '(path0 path1 witness))
          (check-equal? (eq? second (gerbil-ascent-session-run session)) #t)
          (gerbil-ascent-session-append-source! session 'edge '(2 3))
          (check-equal? (eq? second (gerbil-ascent-session-run session)) #t)
          (gerbil-ascent-session-append-source! session 'edge '(3 1))
          (let* ((cycle (gerbil-ascent-session-run session))
                 (fresh-cycle
                  (ascent-mutual-evaluate
                   '((1 2) (2 3) (2 3) (3 1)))))
            (for-each
             (lambda (name)
               (check-equal?
                (not (not (same-rows? ((.ref cycle 'rows-of) name)
                                      ((.ref fresh-cycle 'rows-of) name))))
                #t))
             '(path0 path1 witness))
            (check-equal? (length ((.ref cycle 'rows-of) 'path0)) 9)
            (check-equal? (length ((.ref cycle 'rows-of) 'path1)) 9)
            (check-equal? (length ((.ref cycle 'rows-of) 'witness)) 3))
          (check-equal? ((.ref second 'rows-of) 'path0) '((1 2) (2 3)))
          (check-equal? ((.ref first 'rows-of) 'path0) '((1 2))))))
    (test-case "independent fixed-point runs are reentrant across workers"
      (let* ((sources '(((1 2) (2 3) (3 1))
                       ((1 2) (2 3))
                       ((4 5) (5 6) (6 4))
                       ((1 2) (2 1))))
             (workers
              (map (lambda (edges)
                     (spawn
                      (lambda ()
                        (let (result (ascent-mutual-evaluate edges))
                          (list ((.ref result 'rows-of) 'path0)
                                ((.ref result 'rows-of) 'path1)
                                ((.ref result 'rows-of) 'witness))))))
                   sources))
             (results (map thread-join! workers)))
        (check-equal? (map (lambda (rows) (length (car rows))) results)
                      '(9 2 9 2))
        (check-equal? (map (lambda (rows) (length (cadr rows))) results)
                      '(9 1 9 2))
        (check-equal? (map (lambda (rows) (length (caddr rows))) results)
                      '(3 1 3 2))))))
