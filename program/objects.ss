;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Public POO declarations for positive ASCENT rules. No table state lives
;;; in these objects; each evaluation owns its own relation storage.
(import (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop validate)
        (only-in "types.ss"
                 GerbilAscentRelationContract
                 GerbilAscentTermContract
                 GerbilAscentAtomContract
                 GerbilAscentRuleContract
                 GerbilAscentProgramContract))

(export gerbil-ascent-relation
        gerbil-ascent-variable
        gerbil-ascent-literal
        gerbil-ascent-atom
        gerbil-ascent-rule
        gerbil-ascent-positive-program)

(def Relation. (.ref GerbilAscentRelationContract 'proto))
(def Term. (.ref GerbilAscentTermContract 'proto))
(def Atom. (.ref GerbilAscentAtomContract 'proto))
(def Rule. (.ref GerbilAscentRuleContract 'proto))
(def Program. (.ref GerbilAscentProgramContract 'proto))

(def (gerbil-ascent-relation relation-name column-count source-rows)
  (unless (and (symbol? relation-name)
               (exact-integer? column-count) (<= 0 column-count)
               (list? source-rows))
    (error "invalid ASCENT relation declaration" relation-name column-count))
  (for-each
   (lambda (row)
     (unless (and (list? row) (= (length row) column-count))
       (error "invalid ASCENT relation row" relation-name row column-count)))
   source-rows)
  (validate GerbilAscentRelationContract
            (.o (:: @ Relation.)
                name: relation-name arity: column-count rows: source-rows)))

(def (gerbil-ascent-variable name)
  (unless (symbol? name) (error "ASCENT variable name must be a symbol" name))
  (validate GerbilAscentTermContract
            (.o (:: @ Term.) kind: 'variable value: name)))

(def (gerbil-ascent-literal literal-value)
  (validate GerbilAscentTermContract
            (.o (:: @ Term.) kind: 'literal value: literal-value)))

(def (gerbil-ascent-atom relation-name atom-terms)
  (validate GerbilAscentAtomContract
            (.o (:: @ Atom.) relation: relation-name terms: atom-terms)))

(def (gerbil-ascent-rule head-atom body-atoms)
  (validate GerbilAscentRuleContract
            (.o (:: @ Rule.) head: head-atom body: body-atoms)))

(def (gerbil-ascent-positive-program declared-relations declared-rules
                                     input-fact-limit derived-fact-limit
                                     output-fact-limit)
  (validate GerbilAscentProgramContract
            (.o (:: @ Program.)
                relations: declared-relations rules: declared-rules
                max-input-facts: input-fact-limit
                max-derived-facts: derived-fact-limit
                max-output-facts: output-fact-limit)))
