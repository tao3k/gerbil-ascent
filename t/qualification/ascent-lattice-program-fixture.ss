;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-lattice
                 gerbil-ascent-variable gerbil-ascent-atom
                 gerbil-ascent-binding gerbil-ascent-rule
                 gerbil-ascent-program gerbil-ascent-evaluate-program))

(export ascent-lattice-fixture-evaluate ascent-lattice-wide-evaluate)

(def (v name) (gerbil-ascent-variable name))
(def (a name . terms) (gerbil-ascent-atom name terms))
(def (r head . body) (gerbil-ascent-rule (list head) body))

(def (ascent-lattice-fixture-evaluate edges)
  (gerbil-ascent-evaluate-program
   (gerbil-ascent-program
    (list (gerbil-ascent-relation 'edge 3 edges)
          (gerbil-ascent-lattice 'shortest 3 [] min))
    (list (r (a 'shortest (v 'x) (v 'y) (v 'distance))
             (a 'edge (v 'x) (v 'y) (v 'weight))
             (gerbil-ascent-binding 'distance '(weight)
                                    (lambda (weight) weight)))
          (r (a 'shortest (v 'x) (v 'z) (v 'distance))
             (a 'shortest (v 'x) (v 'y) (v 'first))
             (a 'edge (v 'y) (v 'z) (v 'second))
             (gerbil-ascent-binding 'distance '(first second) +)))
    64 256 320)))

(def (ascent-lattice-wide-evaluate size)
  (let (source
        (append
         (map (lambda (key) (list key (+ key size))) (iota size))
         (map (lambda (key) (list key (+ key 1))) (iota size))))
    (gerbil-ascent-evaluate-program
     (gerbil-ascent-program
      (list (gerbil-ascent-relation 'seed 2 source)
            (gerbil-ascent-lattice 'best 2 [] min))
      (list (r (a 'best (v 'key) (v 'value))
               (a 'seed (v 'key) (v 'value))))
      (* 2 size) size (* 3 size)))))
