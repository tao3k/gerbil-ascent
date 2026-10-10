;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .ref)
        :gerbil-ascent/program/higher-order
        (rename-in (only-in :gerbil-ascent/t/performance/typed-admission/reference relational-relation-type relational-typed-source relational-typed-flatmap relational-typed-compile)
          (relational-relation-type old-type) (relational-typed-source old-source)
          (relational-typed-flatmap old-flatmap) (relational-typed-compile old-compile))
        (only-in :gerbil-ascent/program/scheme-language relational-admit relational-solve relational-query-name))
(export typed-prepare typed-consume)
(def (typed-prepare old? scenario)
  (let* ((width (if (memq scenario '(small empty)) 2 4096))
         (count (case scenario ((empty) 0) ((small) 2) (else 512)))
         (domain (iota width))
         (rows (map (lambda (i) (list (- width 1 i))) (iota count)))
         (entries (map (lambda (row) (list row row)) rows)))
    (vector old? domain rows entries)))
(def (compile-view program output)
  ;; Compare the complete published domain and source representation. The
  ;; generated output handle is deliberately represented by its position.
  (map (lambda (relation)
         (list (.ref relation 'arity) (.ref relation 'rows)
               (vector-ref (.ref relation 'checked-domain) 1)))
       (.ref program 'relations)))
(def (typed-consume state scenario)
  (with (#(old? domain rows entries) state)
    ;; Explicit static calls retain the two independent implementations.
    (let-values (((program output)
      (if old?
        (let* ((type (old-type 1 domain)) (source (old-source 'seed type rows)))
          (old-compile (if (eq? scenario 'mapping) (old-flatmap source type entries) source)
                       4096 8192 8192))
        (let* ((type (relational-relation-type 1 domain))
               (source (relational-typed-source 'seed type rows)))
          (relational-typed-compile
           (if (eq? scenario 'mapping) (relational-typed-flatmap source type entries) source)
           4096 8192 8192)))))
      (compile-view program output))))
