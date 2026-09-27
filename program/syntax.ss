;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Source syntax only: declarations lower to the existing POO contracts.
;;; The evaluator and its validation remain the single semantic authority.
(import "objects.ss")

(export ascent)

(defsyntax (ascent-term stx)
  (syntax-case stx (lit)
    ((_ (lit value))
     (syntax (gerbil-ascent-literal value)))
    ((_ value)
     (identifier? (syntax value))
     (syntax (gerbil-ascent-variable 'value)))
    ((_ value)
     (syntax (gerbil-ascent-literal value)))))

(defsyntax (ascent-atom stx)
  (syntax-case stx ()
    ((_ (name term ...))
     (syntax (gerbil-ascent-atom 'name
                               (list (ascent-term term) ...))))))

(defsyntax (ascent-clause stx)
  (syntax-case stx ()
    ((_ (kind output operation (input ...) (name term ...)))
     (eq? (syntax->datum (syntax kind)) 'aggregate)
     (syntax (gerbil-ascent-aggregate
              'output 'name (list (ascent-term term) ...)
              '(input ...) operation)))
    ((_ (kind (name term ...)))
     (eq? (syntax->datum (syntax kind)) 'not)
     (syntax (gerbil-ascent-negation
              'name (list (ascent-term term) ...))))
    ((_ (kind (input ...) predicate))
     (eq? (syntax->datum (syntax kind)) 'guard)
     (syntax (gerbil-ascent-guard '(input ...) predicate)))
    ((_ (kind output (input ...) procedure))
     (eq? (syntax->datum (syntax kind)) 'bind)
     (syntax (gerbil-ascent-binding 'output '(input ...) procedure)))
    ((_ (kind output (input ...) procedure))
     (eq? (syntax->datum (syntax kind)) 'for)
     (syntax (gerbil-ascent-generator 'output '(input ...) procedure)))
    ((_ (name term ...))
     (not (memq (syntax->datum (syntax name))
                '(aggregate not guard bind for)))
     (syntax (ascent-atom (name term ...))))))

(defsyntax (ascent-relation stx)
  (syntax-case stx ()
    ((_ (name (column ...) source))
     (syntax (gerbil-ascent-relation
              'name (length '(column ...)) source)))
    ((_ (name (column ...)))
     (syntax (gerbil-ascent-relation
              'name (length '(column ...)) [])))))

(defsyntax (ascent-rule stx)
  (syntax-case stx (<--)
    ((_ (((name term ...) ...) <-- body ...))
     (syntax (gerbil-ascent-rule
              (list (ascent-atom (name term ...)) ...)
              (list (ascent-clause body) ...))))
    ((_ ((name term ...) <-- body ...))
     (syntax (gerbil-ascent-rule
              (list (ascent-atom (name term ...)))
              (list (ascent-clause body) ...))))))

(defsyntax (ascent-collect stx)
  (syntax-case stx (relation bounds <--)
    ((_ (declared ...) (lowered ...)
        (relation name (column ...) source) clause ...)
     (syntax (ascent-collect
              (declared ... (ascent-relation (name (column ...) source)))
              (lowered ...) clause ...)))
    ((_ (declared ...) (lowered ...)
        (relation name (column ...)) clause ...)
     (syntax (ascent-collect
              (declared ... (ascent-relation (name (column ...))))
              (lowered ...) clause ...)))
    ((_ (declared ...) (lowered ...)
        (head <-- body ...) clause ...)
     (syntax (ascent-collect
              (declared ...)
              (lowered ... (ascent-rule (head <-- body ...)))
              clause ...)))
    ((_ (declared ...) (lowered ...)
        (bounds input derived output))
     (syntax (gerbil-ascent-program
              (list declared ...) (list lowered ...)
              input derived output)))))

(defsyntax (ascent stx)
  (syntax-case stx ()
    ((_ clause ...)
     (syntax (ascent-collect () () clause ...)))))
