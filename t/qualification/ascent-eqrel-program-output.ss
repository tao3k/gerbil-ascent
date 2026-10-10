;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-eqrel-storage-provider
                 gerbil-ascent-trrel-storage-provider
                 gerbil-ascent-trrel-uf-storage-provider)
        (only-in :gerbil-ascent/t/qualification/ascent-eqrel-program-fixture
                 ascent-storage-fixture-evaluate
                 ascent-default-storage-evaluate))

(export main)

(def (main . args)
  (let* ((request (read))
         (provider (cond
                    ((member "trrel-uf" args)
                     gerbil-ascent-trrel-uf-storage-provider)
                    ((member "trrel" args)
                     gerbil-ascent-trrel-storage-provider)
                    (else gerbil-ascent-eqrel-storage-provider)))
         (result (if (member "default" args)
                   (ascent-default-storage-evaluate
                    (car request) (cadr request))
                   (if (member "scale" args)
                     (ascent-storage-fixture-evaluate
                      (car request) (cadr request) provider 10000 200000 200000)
                     (ascent-storage-fixture-evaluate
                      (car request) (cadr request) provider))))
         (rows-of (.ref result 'rows-of)))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (display name)
          (for-each (lambda (column)
                      (display #\tab)
                      (display column))
                    row)
          (newline))
        (rows-of name)))
     '(binary-output grouped-output))
    (display "END\n")))
