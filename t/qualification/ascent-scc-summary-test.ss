;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-program-summary))

(export ascent-scc-summary-test main)

(def (sample-program)
  (ascent
   (relation seed (value))
   (relation copied (value))
   (relation left (value))
   (relation right (value))
   (relation final_rel (value))
   ((copied x) <-- (seed x))
   ((left x) <-- (right x))
   ((right x) <-- (left x))
   ((final_rel x) <-- (left x))
   (bounds 16 16 32)))

(def (sccs)
  (.ref (gerbil-ascent-program-summary (sample-program)) 'sccs))

(def (members scc)
  (.ref scc 'dynamic-relations))

(def ascent-scc-summary-test
  (test-suite "ASCENT rule dependency SCC summary"
    (poo-flow-test-case "recursive pair and acyclic rules have distinct SCCs"
      (let (components (sccs))
        (check-equal? (length components) 3)
        (check-equal?
         (length (filter (lambda (scc) (.ref scc 'is-looping)) components))
         1)
        (check-equal?
         (length (filter (lambda (scc)
                           (and (= (length (members scc)) 2)
                                (member 'left (members scc))
                                (member 'right (members scc))))
                         components))
         1)
        (check-equal?
         (length (filter (lambda (scc)
                           (equal? (members scc) '(copied))) components))
         1)
        (check-equal?
         (length (filter (lambda (scc)
                           (equal? (members scc) '(final_rel))) components))
         1)))))

(def (main . args)
  (unless (null? args) (error "ASCENT SCC summary takes no arguments"))
  (for-each
   (lambda (scc)
     (display "SCC")
     (display #\tab)
     (display (if (.ref scc 'is-looping) "true" "false"))
     (for-each
      (lambda (name)
        (display #\tab)
        (display name))
      (members scc))
     (newline))
   (sccs))
  (force-output))
