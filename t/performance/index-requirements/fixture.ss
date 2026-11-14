;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/program/index
 :gerbil-ascent/table/provider
 (prefix-in :gerbil-ascent/t/performance/index-requirements/reference old-))
(export requirement-input requirement-workflow requirement-expected requirement-owner requirement-atoms)
(def (requirement-atoms index)
 (map (lambda (columns)
  (let (terms '((literal . #f) (literal . a) (wildcard . #f)))
   (vector index terms columns terms (map (cut list-ref terms <>) columns))))
  '((1) (0 1) (1 0))))
(def (requirement-input groups relations rows kind)
 (let* ((curried? (memq kind '(curried mixed)))
        (selected (if (eq? kind 'mixed) (- relations 1) 0))
        (atoms (requirement-atoms selected)) (ordinary (car (requirement-atoms 0)))
        (providers (make-vector relations gerbil-ascent-hash-index-provider))
        (positive (map (lambda (n)
          (let* ((chosen (if (and (eq? kind 'mixed) (not (zero? (modulo n 16)))) (list ordinary) atoms))
                 (actions (append (map (lambda (atom)
                            ;; Independent atom identities and detached equal
                            ;; column spines model separately compiled rules.
                            (let (fresh (vector-copy atom))
                              (vector-set! fresh 2 (reverse (reverse (vector-ref atom 2))))
                              (vector fresh [] 0))) chosen) (list (vector 'callbacks [])))))
           (vector (vector [] actions 0 #t []) '(0)))) (iota groups))))
  (when curried? (vector-set! providers selected gerbil-ascent-curried-index-provider))
  (vector positive
    (map (lambda (rule)
      (vector [] (map (lambda (action)
        (let (atom (vector-ref action 0))
          (if (vector? atom) (vector (cond ((equal? (vector-ref atom 2) '(1)) 'atom) ((equal? (vector-ref atom 2) '(0 1)) 'negation) (else 'aggregate)) atom) (vector 'callback #f))))
       (vector-ref (vector-ref rule 0) 1)))) positive)
    providers (map (lambda (n) (list #f 'a n)) (iota rows)) atoms)))
(def (requirement-owner old? input)
 (let* ((rows (vector-ref input 3)) (count (vector-length (vector-ref input 2)))
        (all (make-vector count rows)) (delta (make-vector count rows))
        (sizes (make-vector count (length rows))) (versions (make-vector count 0))
        (owner ((if old? old-gerbil-ascent-make-row-indexes gerbil-ascent-make-row-indexes)
                all delta sizes (vector-copy sizes) versions (vector-copy versions) (vector-ref input 2))))
  (vector owner all sizes versions)))
(def (requirement-workflow old? input lane)
 (let* ((context (requirement-owner old? input)) (owner (vector-ref context 0))
        (atoms (vector-ref input 4)) (atom (cadr atoms)) (index (vector-ref atom 0))
        (lookup ((if old? old-row-indexes-rows row-indexes-rows) owner))
        (advance! ((if old? old-row-indexes-advance! row-indexes-advance!) owner)))
  (case lane
   ((rules) ((if old? old-row-indexes-plan-rules! row-indexes-plan-rules!) owner (vector-ref input 1)))
   ((actions) ((if old? old-row-indexes-plan-actions! row-indexes-plan-actions!) owner
                (if (null? (vector-ref input 0)) [] (vector-ref (vector-ref (car (vector-ref input 0)) 0) 1))))
   ((positive)
    (if old?
     (old-row-indexes-plan-actions! owner
      (foldr append [] (map (lambda (rule) (vector-ref (vector-ref rule 0) 1)) (vector-ref input 0))))
     (row-indexes-plan-positive-rules! owner (vector-ref input 0))))
   (else (error "unknown requirement lane" lane)))
  (let ((held (lookup atom [] #f #f)) (delta-before (lookup atom [] #t #f)))
   (advance! index '((#f a 40)))
   (vector-set! (vector-ref context 1) index (cons '(#f a 40) (vector-ref input 3)))
   (vector-set! (vector-ref context 2) index (+ 1 (length (vector-ref input 3))))
   (vector-set! (vector-ref context 3) index 1)
   (list held delta-before (lookup atom [] #f #f) (lookup atom [] #t #f) held))))
(def (requirement-expected input)
 (let (rows (vector-ref input 3)) (list rows rows (cons '(#f a 40) rows) rows rows)))
