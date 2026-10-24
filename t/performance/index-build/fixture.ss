;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .ref)
        :gerbil-ascent/program/objects
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        :gerbil-ascent/table/access
        (rename-in (only-in :gerbil-ascent/t/performance/index-build/reference-access
                           gerbil-ascent-physical-index-build gerbil-ascent-physical-index-extend!
                           gerbil-ascent-physical-index-rows)
                   (gerbil-ascent-physical-index-build old-build)
                   (gerbil-ascent-physical-index-extend! old-extend!)
                   (gerbil-ascent-physical-index-rows old-rows))
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (rename-in (only-in :gerbil-ascent/t/performance/index-build/reference-evaluate gerbil-ascent-evaluate-program)
                   (gerbil-ascent-evaluate-program old-evaluate)))
(export index-build-source index-build-key index-build-lifecycle index-build-program index-build-solve)
(def (index-build-source size (offset 0))
  (map (lambda (n) (list (modulo n 64) n (modulo n 8) n)) (iota size offset)))
(def (index-build-key row columns) (map (lambda (column) (list-ref row column)) columns))
(def (index-build-lifecycle old? source batch columns keys)
  (let (index ((if old? old-build gerbil-ascent-physical-index-build) gerbil-ascent-hash-index-provider source columns))
    ((if old? old-extend! gerbil-ascent-physical-index-extend!) gerbil-ascent-hash-index-provider index batch columns)
    (map (lambda (key) ((if old? old-rows gerbil-ascent-physical-index-rows) gerbil-ascent-hash-index-provider index key)) keys)))
(def (index-build-program)
  (let (vars (map gerbil-ascent-variable '(a b c d)))
    (gerbil-ascent-program
     (list (gerbil-ascent-relation 'input 4 (map (lambda (n) (list n n n n)) (iota 1024)))
           (gerbil-ascent-relation 'out 1 []))
     (map (lambda (_)
            (gerbil-ascent-rule (list (gerbil-ascent-atom 'out (list (car vars))))
                               (list (gerbil-ascent-atom 'input vars) (gerbil-ascent-atom 'input vars))))
          (iota 4)) 4096 4096 8192)))
(def (index-build-solve old? program)
  (let (result ((if old? old-evaluate gerbil-ascent-evaluate-program) program))
    (unless (.ref result 'finished) (error "incomplete index build solver control"))
    ((.ref result 'rows-of) 'out)))
