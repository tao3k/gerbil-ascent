;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/evidence/interface (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/core/relation-view
                 gerbil-ascent-view-with-export gerbil-ascent-explicit-view))
(export make-values make-lattice make-operator make-aggregate make-graph-values
        make-projection-transformer native-values make-export-view)

(def (make-export-view rows exported)
  (gerbil-ascent-view-with-export
   (gerbil-ascent-explicit-view rows (length rows))
   (lambda () exported)))

(def (make-projection-transformer)
  (relational-op-function 2 (lambda (input) (relational-op-project input '(1)))))
(def (native-values . items) (apply values items))

(defrules copy-rule ()
  ((_ from to)
   (gerbil-ascent-rule
    (list (gerbil-ascent-atom to (list (gerbil-ascent-variable 'value))))
    (list (gerbil-ascent-atom from (list (gerbil-ascent-variable 'value)))))))

(define-evidence (make-values values)
  (gerbil-ascent-program
   (list (gerbil-ascent-relation 'input 1 (map list values))
         (gerbil-ascent-relation 'output 1 []))
   (list (copy-rule 'input 'output)) 32 64 96 '(input))
  (lambda (program result query scope)
    (hash ("status" "recorded-only") ("query" query)
          ("scope" scope)
          ("dependencies" (.ref program 'rules))
          ("gap" "declaration dependencies are not a per-row derivation certificate"))))

(define-evidence (make-lattice inputs)
  (gerbil-ascent-program
   (list (gerbil-ascent-relation 'improve 2 inputs)
         (gerbil-ascent-lattice 'best 2 [] min))
   (list (gerbil-ascent-rule
     (list (gerbil-ascent-atom 'best (list (gerbil-ascent-variable 'k) (gerbil-ascent-variable 'v))))
     (list (gerbil-ascent-atom 'improve (list (gerbil-ascent-variable 'k) (gerbil-ascent-variable 'v))))))
   32 64 96 '(improve)))

(def (make-operator inputs)
  (let (fragment (relational-op-fragment
                  (relational-op-project (relational-op-source 'edge 2 inputs) '(1)) 'targets))
    (ascent-evidence-module (relational-compose (list fragment) 32 64 96) #f
      (list (cons 'targets (relational-export fragment 'targets))
            (cons 'edge (relational-export fragment 'edge))))))

(define-evidence (make-aggregate inputs)
  (gerbil-ascent-program
   (list (gerbil-ascent-relation 'number 1 (map list inputs))
         (gerbil-ascent-relation 'average 1 []))
   (list (gerbil-ascent-rule
     (list (gerbil-ascent-atom 'average (list (gerbil-ascent-variable 'mean))))
     (list (gerbil-ascent-aggregate 'mean 'number
             (list (gerbil-ascent-variable 'v)) '(v) gerbil-ascent-mean))))
   32 64 96 '(number)))

(define-evidence (make-graph-values)
  (let ((cycle (make-vector 1)) (shared (vector 17)) (table (make-hash-table-eq)))
    (vector-set! cycle 0 cycle)
    (hash-put! table 'same shared)
    (gerbil-ascent-program
     (list (gerbil-ascent-relation 'input 1
             (map list (list cycle (vector shared shared) table #\a (cons 1 2) identity
                             (string->uninterned-symbol "scoped") (string->uninterned-symbol "scoped")))))
     [] 32 64 96 '(input))))
