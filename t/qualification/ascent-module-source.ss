;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; A reusable Gerbil module supplies the rule family. The caller's origin
;;; is an ordinary lexical Scheme value captured by the guard procedure.
(import (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-guard
                 gerbil-ascent-rule gerbil-ascent-program))

(export ascent-origin-reach-program)

(def (v name) (gerbil-ascent-variable name))
(def (a name . terms) (gerbil-ascent-atom name terms))

(def (ascent-origin-reach-program edges origin)
  (gerbil-ascent-program
   (list (gerbil-ascent-relation 'edge 2 edges)
         (gerbil-ascent-relation 'reach 2 []))
   (list
    (gerbil-ascent-rule
     (list (a 'reach (v 'x) (v 'y)))
     (list (a 'edge (v 'x) (v 'y))
           (gerbil-ascent-guard '(x)
                                (lambda (x) (equal? x origin)))))
    (gerbil-ascent-rule
     (list (a 'reach (v 'x) (v 'z)))
     (list (a 'reach (v 'x) (v 'y))
           (a 'edge (v 'y) (v 'z)))))
   64 256 320))
