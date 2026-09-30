;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite)
        (only-in :std/list/list append-map delete-duplicates/hash)
        (only-in :clan/poo/object .ref)
        (only-in :clan/poo/mop element?)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :gerbil-ascent/program/types
                 GerbilAscentFragmentContract)
        (only-in :gerbil-ascent/program/scheme-language
                 relational-program relational-fragment
                 relational-compose)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program
                 gerbil-ascent-open-session
                 gerbil-ascent-session-replace-source!))

(export scheme-relational-test)

;;; Floyd-Warshall over finite edge pairs, independent of rule evaluation.
(def (reference-closure edges)
  (foldl
   (lambda (pivot paths)
     (delete-duplicates/hash
      (append
       paths
       (append-map
        (lambda (left)
          (if (equal? (cadr left) pivot)
            (filter-map
             (lambda (right)
               (and (equal? (car right) pivot)
                    (list (car left) (cadr right))))
             paths)
            []))
        paths))))
   (delete-duplicates/hash edges)
   (delete-duplicates/hash (append (map car edges) (map cadr edges)))))

(def (same-set? actual expected)
  (and (= (length actual) (length expected))
       (andmap (lambda (row) (if (member row expected) #t #f))
               actual)))

(def (evaluate edges (derived-limit 32))
  (gerbil-ascent-evaluate-program
   (relational-program
    (relation edge (from to) edges)
    (relation path (from to))
    (rule (path ?x ?y) (edge ?x ?y))
    (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
    (limits 32 derived-limit 64))))

(def (rows result name)
  ((.ref result 'rows-of) name))

(def (source-fragment edges)
  (relational-fragment
   (import)
   (source (edge (from to) edges))
   (private)
   (export edge)))

(def (reach-fragment edge-handle)
  (relational-fragment
   (import (edge edge-handle))
   (source)
   (private (path (from to)))
   (export path)
   (rule (path ?x ?y) (edge ?x ?y))
   (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))))

(def scheme-relational-test
  (test-suite "Scheme relational finite positive gate"
    (poo-flow-test-case "two fragment instances retain private identities"
      (let-values (((source-a edge-a)
                    (source-fragment '((1 2) (2 3))))
                   ((source-b edge-b)
                    (source-fragment '((7 8)))))
        (let-values (((reach-a path-a) (reach-fragment edge-a))
                     ((reach-b path-b) (reach-fragment edge-b)))
          (let ((result
                 (gerbil-ascent-evaluate-program
                  (relational-compose
                   (list source-a source-b reach-a reach-b)
                   16 16 32)))
                (reordered
                 (gerbil-ascent-evaluate-program
                  (relational-compose
                   (list reach-b source-b reach-a source-a)
                   16 16 32))))
            (check-equal? (element? GerbilAscentFragmentContract reach-a)
                          #t)
            (check-equal? (eq? edge-a edge-b) #f)
            (check-equal? (eq? path-a path-b) #f)
            (check-equal? (same-set? (rows result path-a)
                                     '((1 2) (2 3) (1 3))) #t)
            (check-equal? (rows result path-b) '((7 8)))
            (check-equal? (same-set? (rows result path-a)
                                     (rows reordered path-a)) #t)
            (check-equal? (same-set? (rows result path-b)
                                     (rows reordered path-b)) #t)))))
    (poo-flow-test-case "assembled program rejects duplicate instance"
      (let-values (((source edge) (source-fragment '((1 2)))))
        (check-exception
         (gerbil-ascent-evaluate-program
          (relational-compose (list source source) 8 8 16))
         true)))
    (poo-flow-test-case "recursive closure equals independent graph model"
      (for-each
       (lambda (edges)
         (let ((actual (rows (evaluate edges) 'path))
               (expected (reference-closure edges)))
           (check-equal? (same-set? actual expected) #t)))
       '(() ((1 2)) ((1 2) (2 3) (3 1))
         ((1 2) (1 2) (2 3) (4 5))
         ((1 1) (1 2) (2 2)))))
    (poo-flow-test-case "all 64 simple directed graphs on three nodes"
      (let (graphs
            (foldl
             (lambda (edge sets)
               (append sets
                       (map (lambda (set) (cons edge set)) sets)))
             (list [])
             '((1 2) (1 3) (2 1) (2 3) (3 1) (3 2))))
        (check-equal? (length graphs) 64)
        (for-each
         (lambda (edges)
           (check-equal?
            (same-set? (rows (evaluate edges) 'path)
                       (reference-closure edges))
            #t))
         graphs)))
    (poo-flow-test-case "new source snapshot does not mutate old result"
      (let* ((before (evaluate '((1 2) (2 3))))
             (after (evaluate '((1 2)))))
        (check-equal? (same-set? (rows before 'path)
                                 '((1 2) (2 3) (1 3))) #t)
        (check-equal? (same-set? (rows after 'path) '((1 2))) #t)
        (check-equal? (length (rows before 'path)) 3)))
    (poo-flow-test-case "repeated variables and scalar literals"
      (let* ((result
              (gerbil-ascent-evaluate-program
               (relational-program
                (relation edge (from to) '((1 1) (1 2) (2 3)))
                (relation loop (node))
                (relation from-one (node))
                (rule (loop ?x) (edge ?x ?x))
                (rule (from-one ?y) (edge 1 ?y))
                (limits 8 8 16)))))
        (check-equal? (rows result 'loop) '((1)))
        (check-equal? (same-set? (rows result 'from-one)
                                 '((1) (2))) #t)))
    (poo-flow-test-case "source replacement retains scalar contract"
      (let (session
            (gerbil-ascent-open-session
             (relational-program
              (relation edge (from to) '((1 2)))
              (limits 8 8 16))))
        (check-exception
         (gerbil-ascent-session-replace-source!
          session 'edge '((1 "mutable")))
         true)))
    (poo-flow-test-case "unsafe head, invalid source and budget fail"
      (check-exception
       (gerbil-ascent-evaluate-program
        (relational-program
         (relation edge (from to) '((1 2)))
         (relation path (from to))
         (rule (path ?x ?z) (edge ?x ?y))
         (limits 8 8 16)))
       true)
      (check-exception
       (relational-program
        (relation edge (from to) '((1 "mutable")))
        (limits 8 8 16))
       true)
      (check-exception
       (eval
        '(begin
           (import :gerbil-ascent/program/scheme-language)
           (relational-program
            (relation edge (from to) '((1 2)))
            (relation path (from to))
            (rule (path plain ?y) (edge ?x ?y))
            (limits 8 8 16))))
       true)
      (check-exception (evaluate '((1 2) (2 3)) 1) true))))
