;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/iter in-range)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-guard
                 gerbil-ascent-generator gerbil-ascent-binding
                 gerbil-ascent-negation
                 gerbil-ascent-rule
                 gerbil-ascent-program
                 gerbil-ascent-evaluate-program))

(export ascent-rule-fixture-program
        ascent-rule-fixture-evaluate)

(def (v name) (gerbil-ascent-variable name))
(def (a name . terms) (gerbil-ascent-atom name terms))
(def (r head . body) (gerbil-ascent-rule (list head) body))

(def (ascent-rule-fixture-program edges (derived-limit 32))
  (gerbil-ascent-program
        (list (gerbil-ascent-relation 'edge 3 edges)
              (gerbil-ascent-relation 'node 1 '((1) (2) (3)))
              (gerbil-ascent-relation 'labelled 4 [])
              (gerbil-ascent-relation 'cycle 1 [])
              (gerbil-ascent-relation 'hot 1 [])
              (gerbil-ascent-relation 'selected 2 [])
              (gerbil-ascent-relation 'choice 2 [])
              (gerbil-ascent-relation 'generated 1 [])
              (gerbil-ascent-relation 'dependent 2 [])
              (gerbil-ascent-relation 'successor 2 [])
              (gerbil-ascent-relation 'blocked 2 [])
              (gerbil-ascent-relation 'allowed 2 [])
              (gerbil-ascent-relation 'denied 2 [])
              (gerbil-ascent-relation 'safe-reach 2 [])
              (gerbil-ascent-relation 'reach 2 []))
        (list
         (r (a 'labelled (v 'x) (v 'z) (v 'first) (v 'second))
            (a 'edge (v 'x) (v 'y) (v 'first))
            (a 'edge (v 'y) (v 'z) (v 'second)))
         (r (a 'cycle (v 'x))
            (a 'edge (v 'x) (v 'x) (v 'label)))
         (gerbil-ascent-rule
          (list (a 'hot (v 'x)) (a 'selected (v 'x) (v 'y)))
          (list (a 'edge (v 'x) (v 'y) (v 'label))
                (gerbil-ascent-guard '(label)
                                     (lambda (label) (equal? label "a")))))
         (r (a 'choice (v 'x) (v 'y))
            (a 'node (v 'x))
            (gerbil-ascent-generator 'y [] (lambda () '(1 2 3)))
            (gerbil-ascent-guard '(x y) (lambda (x y) (not (= x y)))))
         (r (a 'generated (v 'x))
            (gerbil-ascent-generator '(x unused) []
                                     (lambda () '#(#(1 2) #(2 3) #(3 4)))))
         (r (a 'dependent (v 'x) (v 'y))
            (a 'node (v 'x))
            (gerbil-ascent-generator 'y '(x)
                                     (lambda (x) (in-range 0 (- x 1)))))
         (r (a 'successor (v 'x) (v 'y))
            (a 'node (v 'x))
            (gerbil-ascent-binding 'y '(x) (lambda (x) (+ x 1))))
         (r (a 'blocked (v 'x) (v 'y))
            (a 'edge (v 'x) (v 'y) (v 'label))
            (gerbil-ascent-guard '(label)
                                 (lambda (label) (equal? label "c"))))
         (r (a 'allowed (v 'x) (v 'y))
            (a 'edge (v 'x) (v 'y) (v 'label))
            (gerbil-ascent-negation 'blocked (list (v 'x) (v 'y))))
         (r (a 'denied (v 'x) (v 'y))
            (a 'edge (v 'x) (v 'y) (v 'label))
            (gerbil-ascent-negation 'allowed (list (v 'x) (v 'y))))
         (r (a 'safe-reach (v 'x) (v 'y))
            (a 'allowed (v 'x) (v 'y)))
         (r (a 'safe-reach (v 'x) (v 'z))
            (a 'safe-reach (v 'x) (v 'y))
            (a 'allowed (v 'y) (v 'z)))
         (r (a 'reach (v 'x) (v 'y))
            (a 'edge (v 'x) (v 'y) (v 'label)))
         (r (a 'reach (v 'x) (v 'z))
            (a 'reach (v 'x) (v 'y))
            (a 'edge (v 'y) (v 'z) (v 'label))))
        16 derived-limit 64))

(def (ascent-rule-fixture-evaluate edges (derived-limit 32))
  (gerbil-ascent-evaluate-program
   (ascent-rule-fixture-program edges derived-limit)))
