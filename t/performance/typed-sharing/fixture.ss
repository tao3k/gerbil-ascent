;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .ref)
        :gerbil-ascent/program/higher-order
        (rename-in (only-in :gerbil-ascent/t/performance/typed-sharing/reference
                   relational-relation-type relational-typed-source relational-typed-flatmap
                   relational-typed-union relational-typed-compile)
          (relational-relation-type old-type) (relational-typed-source old-source)
          (relational-typed-flatmap old-flatmap) (relational-typed-union old-union)
          (relational-typed-compile old-compile))
        (only-in :gerbil-ascent/program/scheme-language relational-admit relational-solve relational-query-name))
(export sharing-prepare sharing-consume sharing-verify!)
(def (shared-term make-type source mapping union width count depth mapped?)
  (let* ((type (make-type 1 (iota width))) (rows (map list (iota count)))
         (seed (source 'seed type rows))
         (base (if mapped? (mapping seed type (map (lambda (row) (list row row)) rows)) seed)))
    (let loop ((remaining depth) (term base))
      (if (zero? remaining) term
        (loop (- remaining 1) (union term term))))))
(def (sharing-prepare old? scenario)
  (let ((width (if (eq? scenario 'small) 2 512))
        (count (case scenario ((small) 2) ((single) 8) (else 512)))
        (depth (case scenario ((small) 1) ((single) 0) ((mapping) 4) (else 5))))
    (vector old?
      (if old?
        (shared-term old-type old-source old-flatmap old-union width count depth (eq? scenario 'mapping))
        (shared-term relational-relation-type relational-typed-source relational-typed-flatmap
                     relational-typed-union width count depth (eq? scenario 'mapping)))
      (map list (iota count)))))
(def (compiled state)
  (with (#(old? term _) state)
    (if old? (old-compile term 32768 32768 32768 10000)
      (relational-typed-compile term 32768 32768 32768 10000))))
(def (sharing-consume state scenario)
  (let-values (((program output) (compiled state)))
    (list (length (.ref program 'rules))
      (map (lambda (relation)
             (list (.ref relation 'arity) (.ref relation 'rows)
                   (vector-ref (.ref relation 'checked-domain) 1)))
           (.ref program 'relations)))))
(def (sharing-verify! state)
  (let-values (((program output) (compiled state)))
    (let ((rows (relational-query-name (relational-solve (relational-admit program)) output))
          (expected (vector-ref state 2)))
      (unless (and (= (length rows) (length expected))
                   (andmap (lambda (row) (and (member row rows) #t)) expected))
        (error "shared typed native rows differ" rows expected)))))
