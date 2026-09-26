;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-rule
                 gerbil-ascent-aggregate gerbil-ascent-program
                 gerbil-ascent-evaluate-program
                 gerbil-ascent-count gerbil-ascent-sum
                 gerbil-ascent-min gerbil-ascent-max
                 gerbil-ascent-mean))

(export ascent-aggregate-fixture-evaluate)

(def (v name) (gerbil-ascent-variable name))
(def (a name . terms) (gerbil-ascent-atom name terms))
(def (r head body) (gerbil-ascent-rule (list head) (list body)))
(def (agg operation (inputs '(x)))
  (gerbil-ascent-aggregate 'value 'number (list (v 'x))
                           inputs operation))

(def (ascent-aggregate-fixture-evaluate values)
  (gerbil-ascent-evaluate-program
   (gerbil-ascent-program
    (list (gerbil-ascent-relation 'number 1 (map list values))
          (gerbil-ascent-relation 'group-key 1 '((1) (2)))
          (gerbil-ascent-relation 'pair 2 '((1 10) (1 20) (2 5)))
          (gerbil-ascent-relation 'by-group 2 [])
          (gerbil-ascent-relation 'minimum 1 [])
          (gerbil-ascent-relation 'maximum 1 [])
          (gerbil-ascent-relation 'total 1 [])
          (gerbil-ascent-relation 'cardinality 1 [])
          (gerbil-ascent-relation 'average 1 [])
          (gerbil-ascent-relation 'custom 1 []))
    (list (gerbil-ascent-rule
           (list (a 'by-group (v 'group) (v 'total)))
           (list (a 'group-key (v 'group))
                 (gerbil-ascent-aggregate
                  'total 'pair (list (v 'group) (v 'x))
                  '(x) gerbil-ascent-sum)))
          (r (a 'minimum (v 'value)) (agg gerbil-ascent-min))
          (r (a 'maximum (v 'value)) (agg gerbil-ascent-max))
          (r (a 'total (v 'value)) (agg gerbil-ascent-sum))
          (r (a 'cardinality (v 'value))
             (agg gerbil-ascent-count []))
          (r (a 'average (v 'value)) (agg gerbil-ascent-mean))
          (r (a 'custom (v 'value))
             (agg (lambda (tuples)
                    (if (null? tuples)
                      []
                      (let (values (map car tuples))
                        (list (apply min values) (apply max values))))))))
    32 32 64)))
