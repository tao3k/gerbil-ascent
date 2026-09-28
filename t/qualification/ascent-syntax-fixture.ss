;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/t/qualification/ascent-fragment-source
                 ascent-reach-fragment ascent-generated-seed-fragment)
        (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage
                 gerbil-ascent-set-storage-provider))

(export ascent-syntax-program ascent-syntax-evaluate
        ascent-expression-evaluate ascent-index-expression-evaluate
        ascent-syntax-parity-evaluate
        ascent-included-fragment-evaluate
        ascent-generated-fragment-evaluate
        ascent-inline-macro-evaluate
        ascent-inline-rule-macro-evaluate
        ascent-pattern-clauses-evaluate)

(def (ascent-syntax-program edges anchor)
  (ascent
   (relation edge (from to) edges
             (index gerbil-ascent-hash-index-provider)
             (storage gerbil-ascent-set-storage-provider))
   (relation seed (node))
   (relation marker (node))
   (relation chosen (node))
   (relation packed (value) '((#(2 9)) (#(3 10)) (#(4))))
   (relation unpacked (from to))
   (relation tripled (value))
   (relation even-packed (value))
   (relation cross (left right))
   (fact (seed (lit anchor)))
   (facts (marker (lit anchor))
          (marker (lit (+ anchor 1))))
   ((chosen x) <--
    (or (and (seed x))
        (and (edge x y))))
   ((unpacked x y) <-- (packed value)
    (match (x y) (value) (vector x y)))
   ((tripled y) <-- (seed x) (let y (x) (* x 3)))
   ((even-packed x) <-- (packed value)
    (if-let (x y) (value) value (vector x y))
    (if (x) (even? x)))
   ((cross a b) <--
    (or (and (seed a)) (and (unpacked a ignored)))
    (or (and (seed b)) (and (marker b))))
   (bounds 16 16 32)))

(def (ascent-syntax-evaluate edges anchor)
  (gerbil-ascent-evaluate-program
   (ascent-syntax-program edges anchor)))

(def (ascent-expression-evaluate edges)
  (gerbil-ascent-evaluate-program
   (ascent
    (relation edge (from to) edges)
    (relation anchor (value) '((7)))
    (relation consecutive (from))
    (relation anchored-target (to))
    ((consecutive x) <-- (edge x (expr (x) (+ x 1))))
    ((anchored-target y) <-- (anchor x)
     (edge (expr (x) (+ x 1)) y))
    (bounds 8 8 16))))

(def (ascent-index-expression-evaluate edges provider)
  (gerbil-ascent-evaluate-program
   (ascent
    (relation edge (from to) edges (index provider))
    (relation anchor (value) '((7)))
    (relation anchored-target (to))
    ((anchored-target y) <-- (anchor x)
     (edge (expr (x) (+ x 1)) y))
    (bounds 40 4 44))))

(def (ascent-syntax-parity-evaluate edges)
  (gerbil-ascent-evaluate-program
   (ascent
    (relation edge ((from integer?) (to integer?)) edges)
    (relation seed (value))
    (relation marker (value))
    (relation selected (value))
    (relation successor ((value integer?)))
    (relation optional (value) '(((some . 4)) (#f)))
    (relation unwrapped (value))
    (relation unwrapped-pattern (value))
    (relation missing-successor (value))
    (facts (seed (lit 7)) (marker (lit 8)))
    ((selected x) <--
     (or (and (seed x)) (and (edge x y))))
    ((successor (expr (x) (+ x 1))) <-- (edge x y))
    ((unwrapped x) <-- (optional value)
     (if-let (x) (value) value (cons 'some x)))
    ((unwrapped-pattern x) <--
     (optional (pat (x) (cons 'some x))))
    ((missing-successor x) <-- (seed x)
     (not (edge x (expr (x) (+ x 1)))))
    (bounds 16 16 32))))

(def (ascent-pattern-clauses-evaluate edges)
  (gerbil-ascent-evaluate-program
   (ascent
    (relation edge (from to) edges)
    (relation let-pair (from to))
    (relation for-pair (from to))
    ((let-pair x y) <-- (edge a b)
     (let (x y) (a b) (vector a (+ b 1)) (vector x y)))
    ((for-pair x y) <-- (edge a b)
     (for (x y) (a b)
          (list (vector a b) (vector b a))
          (vector x y)))
    (bounds 8 16 24))))

(def (ascent-included-fragment-evaluate edges)
  (let (source-fragment (ascent-reach-fragment edges))
    (gerbil-ascent-evaluate-program
     (ascent
      (include source-fragment)
      (bounds 16 32 48)))))

(def (ascent-generated-fragment-evaluate)
  (let (generated (ascent-generated-seed-fragment 9))
    (gerbil-ascent-evaluate-program
     (ascent
      (include generated)
      (bounds 4 4 8)))))

(def (ascent-inline-macro-evaluate)
  (gerbil-ascent-evaluate-program
   (ascent
    (relation macro-seed ((value integer?)))
    (macro emit-seed! (value)
      (fact (macro-seed (lit value))))
    (emit-seed! 9)
    (emit-seed! 10)
    (bounds 4 4 8))))

(def (ascent-inline-rule-macro-evaluate edges)
  (gerbil-ascent-evaluate-program
   (ascent
    (relation edge ((from integer?) (to integer?)) edges)
    (macro emit-copy! (destination)
      (relation destination ((from integer?) (to integer?)))
      ((destination from to) <-- (edge from to)))
    (emit-copy! copied)
    (bounds 8 8 16))))
