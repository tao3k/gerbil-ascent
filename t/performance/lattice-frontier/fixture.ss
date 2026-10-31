;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object :gerbil-ascent/program/objects
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine)
        (rename-in (only-in :gerbil-ascent/t/performance/lattice-frontier/reference
                           gerbil-ascent-make-engine)
          (gerbil-ascent-make-engine old-engine)))
(export frontier-prepare frontier-consume frontier-verify! frontier-program frontier-view)

(def (frontier-program unused rows lattice? (join min) (derived-limit 16384))
  (let ((key (gerbil-ascent-variable 'key)) (value (gerbil-ascent-variable 'value)))
    (gerbil-ascent-program
     (append
      (list (gerbil-ascent-relation 'input 2 rows)
            (if lattice? (gerbil-ascent-lattice 'best 2 [] join)
              (gerbil-ascent-relation 'best 2 [])))
      (map (lambda (i)
             (let (name (string->symbol (string-append "unused-" (number->string i))))
               (if lattice? (gerbil-ascent-lattice name 2 [] join)
                 (gerbil-ascent-relation name 2 [])))) (iota unused)))
     (list (gerbil-ascent-rule
            (list (gerbil-ascent-atom 'best (list key value)))
            (list (gerbil-ascent-atom 'input (list key value)))))
     16384 derived-limit 32768)))

(def (frontier-prepare old? scenario)
  (let* ((unused (case scenario ((sparse) 256) ((cold) 128) ((set) 16) (else 0)))
         (rows (case scenario
                 ((repeated source) (map (lambda (i) (list (modulo i 8) i)) (iota 2048)))
                 ((distinct) (map (lambda (i) (list i i)) (iota 2048)))
                 ((cold) '((0 9))) (else [])))
         (program (if (eq? scenario 'source)
                    (gerbil-ascent-program
                     (list (gerbil-ascent-relation 'input 2 [])
                           (gerbil-ascent-lattice 'best 2 rows min))
                     [] 16384 16384 32768)
                    (frontier-program unused rows (not (eq? scenario 'set))))))
    (vector old? program scenario)))

(def (frontier-view engine program)
  (let (result (if (procedure? engine) (engine) ((.ref engine '.run))))
    (list (.ref result 'finished)
          (map (lambda (relation)
                 (let (name (.ref relation 'name))
                   (cons name ((.ref result 'rows-of) name))))
               (.ref program 'relations)))))

(def (frontier-consume state scenario)
  (let* ((program (vector-ref state 1))
         (retained? (memq scenario '(sparse small set)))
         (engine (if (vector-ref state 0) (old-engine program (not (not retained?)))
                   (gerbil-ascent-make-engine program (not (not retained?)))))
         (initial (frontier-view engine program)))
    (if retained?
      (cons initial
        (map (lambda (i)
               ((.ref engine '.append-source!) 'input (list i (- 12 i)))
               (frontier-view engine program))
             (iota (if (eq? scenario 'small) 2 12))))
      (list initial))))

;;; Independent full input truth, including unused relations and every snapshot.
(def (frontier-verify! state)
  (let* ((scenario (vector-ref state 2))
         (views (frontier-consume state scenario)))
    (for-each
     (lambda (view step)
       (unless (car view) (error "unfinished lattice frontier consumer"))
       (let* ((rows (cadr view))
              (input (cdr (assq 'input rows)))
              (best (cdr (assq 'best rows)))
              (expected-input
               (case scenario
                 ((repeated) (map (lambda (i) (list (modulo i 8) i)) (iota 2048)))
                 ((distinct) (map (lambda (i) (list i i)) (iota 2048)))
                 ((cold) '((0 9)))
                 ((source) [])
                 (else (map (lambda (i) (list i (- 12 i))) (iota step)))))
              (expected-best (if (memq scenario '(repeated source))
                               (map (lambda (i) (list i i)) (iota 8)) expected-input)))
         (unless (and (= (length input) (length expected-input))
                      (= (length best) (length expected-best))
                      (andmap (cut member <> input) expected-input)
                      (andmap (cut member <> best) expected-best)
                      (andmap (lambda (entry) (null? (cdr entry))) (drop rows 2)))
           (error "lattice frontier independent truth differs" scenario step))))
     views (iota (length views)))))
