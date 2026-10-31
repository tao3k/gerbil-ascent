;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o .ref)
        :gerbil-ascent/program/operator
        (prefix-in :gerbil-ascent/t/performance/operator-publication/reference old-)
        (only-in :gerbil-ascent/program/objects gerbil-ascent-relation gerbil-ascent-program)
        (only-in :gerbil-ascent/program/interface relational-admit relational-solve relational-query-name))
(export publication-prepare publication-consume publication-expected publication-verify!
        publication-shape)
(def (graph width)
  (let* ((row (if (zero? width) [] (cons #f (cdr (iota width)))))
         (left (relational-op-source 'left width (list row))))
    (if (zero? width) left
      (let* ((right (relational-op-source 'right width (list row)))
             (join (relational-op-join left right 0 0))
             (selected (relational-op-select-eq join 0 #f))
             (projected (relational-op-project selected (reverse (iota width))))
             (mapped (relational-op-flatmap projected width (list (list (reverse row) row)))))
        (relational-op-fix width (lambda (parameter) (relational-op-union mapped parameter)))))))
(def (publication-prepare old? scenario)
  (let ((width (case scenario ((program fragment) 64) ((custom) 16) ((cold) 8) ((small) 2) (else 0)))
        (base (if old? old-relational-op-compiler relational-op-compiler)))
    (vector (graph width) width
      (if (eq? scenario 'custom)
        (.o (:: @ base) (.make-relation (lambda (name arity rows)
                                         (gerbil-ascent-relation name arity rows)))) base))))
(def (produce state scenario old?)
  (with (#(root _ compiler) state)
    (if (eq? scenario 'fragment)
      (let* ((fragment ((if old? old-relational-op-fragment relational-op-fragment) root 'answer compiler))
             (output ((.ref fragment 'exports) 'answer)))
        (values fragment output))
      ((if old? old-relational-op-compile relational-op-compile) root 64 64 128 compiler))))
;;; Consume every declaration and variable binding before ending the clock.
;;; Alpha normalization preserves relation/rule order and lexical term identity.
(def (publication-shape object output)
  (let* ((relations (.ref object 'relations)) (positions (make-hash-table-eq)))
    (for-each (lambda (relation index) (hash-put! positions (.ref relation 'name) index))
              relations (iota (length relations)))
    (list
     (map (lambda (relation) (list (.ref relation 'arity) (.ref relation 'rows))) relations)
     (map (lambda (rule)
       (let ((names (make-hash-table-eq)) (next 0))
         (def (atom-shape atom)
           (list (hash-ref positions (.ref atom 'relation))
             (map (lambda (term)
                    (let (name (.ref term 'value))
                      (unless (hash-get names name)
                        (set! next (+ next 1)) (hash-put! names name next))
                      (list (.ref term 'kind) (hash-ref names name)))) (.ref atom 'terms))))
         (list (map atom-shape (.ref rule 'heads)) (map atom-shape (.ref rule 'body)))))
       (.ref object 'rules))
     (map (cut hash-ref positions <>) (.ref object 'source-handles))
     (hash-ref positions output))))
(def (solve-rows object output fragment?)
  (let (program (if fragment?
                 (gerbil-ascent-program (.ref object 'relations) (.ref object 'rules)
                   64 64 128 (.ref object 'source-handles)) object))
    (relational-query-name (relational-solve (relational-admit program)) output)))
(def (relation-position name relations)
  (let scan ((remaining relations) (index 0))
    (if (eq? name (.ref (car remaining) 'name)) index
      (scan (cdr remaining) (+ index 1)))))
(def (publication-consume state scenario old?)
  (let-values (((object output) (produce state scenario old?)))
    (let (shape (publication-shape object output))
      (if (eq? scenario 'cold) (list shape (solve-rows object output #f))
        (if (eq? scenario 'fragment)
          (list shape
            (map (lambda (label)
                   ;; Resolve all published labels, including fresh source handles.
                   (let (name ((.ref object 'exports) label))
                     (list label (relation-position name (.ref object 'relations))))) '(answer left right)))
          shape)))))
(def (publication-expected state scenario)
  ;; The native qualification Suite owns both independent solve/query oracles.
  ;; The benchmark owns the full differential projection; cold still solves
  ;; inside every timed consumer. Do not repeat Suite work during sampling.
  (publication-consume state scenario #t))
(def (publication-verify! state scenario old?)
  (let-values (((object output) (produce state scenario old?)))
    (let* ((width (vector-ref state 1))
           (expected (list (if (zero? width) [] (cons #f (cdr (iota width)))))))
      (unless (equal? (solve-rows object output (eq? scenario 'fragment)) expected)
        (error "operator publication independent rows differ" scenario)))))
