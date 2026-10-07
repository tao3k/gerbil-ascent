;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .ref)
        :gerbil-ascent/program/objects
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine)
        :gerbil-ascent/program/positive-components
        (rename-in :gerbil-ascent/t/performance/component-scope/reference
                   (gerbil-ascent-positive-components old-components)
                   (gerbil-ascent-compile-positive-components old-compile)
                   (gerbil-ascent-component-mode? old-mode?)
                   (gerbil-ascent-run-positive-components! old-run)
                   (positive-component-id old-id) (positive-component-members old-members)
                   (positive-component-rules old-rules) (positive-component-predecessors old-predecessors)))
(export component-scope-program component-scope-request component-scope-plan component-scope-run
        component-scope-normalize)
(def (component-scope-program count width rows (multi? #f))
  (let* ((x (gerbil-ascent-variable 'x))
         (names (map (lambda (n) (string->symbol (string-append "out" (number->string n)))) (iota count)))
         (heads (map (lambda (name) (gerbil-ascent-atom name (list x))) names))
         (body (make-list width (gerbil-ascent-atom 'source (list x)))))
    (gerbil-ascent-program
     (cons (gerbil-ascent-relation 'source 1 (map list (iota rows)))
           (map (lambda (name) (gerbil-ascent-relation name 1 [])) names))
     (if multi? (list (gerbil-ascent-rule heads body))
       (map (lambda (head) (gerbil-ascent-rule (list head) body)) heads))
     65536 65536 65536)))
(def (component-scope-request program)
  (let (engine (gerbil-ascent-make-engine program #t))
    (vector (.ref engine '.analysis) (.ref engine '.schema)
            (list->vector (map (lambda (relation) (reverse (.ref relation 'rows))) (.ref program 'relations))))))
(def (component-scope-plan old? request)
  ((if old? old-compile gerbil-ascent-compile-positive-components) (vector-ref request 0)))
;; Preserve the entire original execution data. Additional compiled visitors
;; have fresh procedure identities; their behavior is checked by native plans.
(def (component-scope-plan-data plan)
  (and plan
    (vector
      (map (lambda (output) (vector (vector-ref output 0) (vector-ref output 1))) (vector-ref plan 0))
      (map (lambda (action)
             (if (vector? (vector-ref action 0))
               (vector (vector-ref action 0) (vector-ref action 1) (vector-ref action 2)) action))
           (vector-ref plan 1))
      (vector-ref plan 2))))
(def (component-scope-normalize old? components)
  (map (lambda (component)
         (list ((if old? old-id positive-component-id) component)
               ((if old? old-members positive-component-members) component)
               ;; Compare the original execution metadata explicitly. Current
               ;; plans additionally carry an independently tested purity flag.
               (map (lambda (rule)
                      (let (plan (vector-ref rule 0))
                        (vector (component-scope-plan-data plan)
                                (vector-ref rule 1))))
                    ((if old? old-rules positive-component-rules) component))
               ((if old? old-predecessors positive-component-predecessors) component))) components))
(def (component-scope-run old? request jobs)
  (let* ((initial (vector-ref request 2))
         (count (vector-length initial))
         (rows (vector-copy initial))
         (seen (vector-map (lambda (source) (let (table (make-hash-table))
                                            (for-each (lambda (row) (hash-put! table row #t)) source) table)) initial)))
    ((if old? old-run gerbil-ascent-run-positive-components!)
     (vector-ref request 0) (vector-ref request 1) initial jobs
     (lambda (atom row)
       (let* ((index (vector-ref atom 0)) (table (vector-ref seen index)))
         (unless (hash-get table row)
           (hash-put! table row #t)
           (vector-set! rows index (cons row (vector-ref rows index))))))
     (lambda () #f))
    ;; Independent components may interleave, so compare per-relation values.
    (vector-map (lambda (source) (list-sort (lambda (a b) (< (car a) (car b))) source)) rows)))
