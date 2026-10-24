;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Repeated source-selection cost; declaration graph compilation is upfront.
(import :gerbil/runtime/gambit
        (only-in :gerbil/expander core-resolve-library-module-path)
        (only-in :gerbil-ascent/program/objects gerbil-ascent-program
                 gerbil-ascent-relation gerbil-ascent-rule gerbil-ascent-atom
                 gerbil-ascent-variable)
        (only-in :gerbil-ascent/program/analysis gerbil-ascent-program-schema)
        (only-in :gerbil-ascent/program/planning gerbil-ascent-prepare-program)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/update-selection gerbil-ascent-update-selection)
        (rename-in :gerbil-ascent/t/performance/update-dependencies/reference
                   (gerbil-ascent-update-selection old-selection)))
(export main)
(def (median xs) (list-ref (list-sort < xs) (quotient (length xs) 2)))
(def (measure call)
  (let (before (##process-statistics))
    (let loop ((left 10) (result #f))
      (if (zero? left)
        (let (after (##process-statistics))
          (values result
            (/ (- (f64vector-ref after 7) (f64vector-ref before 7)) 10)
            (/ (- (+ (f64vector-ref after 0) (f64vector-ref after 1))
                  (+ (f64vector-ref before 0) (f64vector-ref before 1))) 10)))
        (loop (- left 1) (call))))))
(def (main scenario library)
  (for-each
   (lambda (name)
     (let (path (path-expand (string-append "gerbil-ascent/" name ".ssi") library))
       (unless (and (equal? path (core-resolve-library-module-path
                                  (string->symbol (string-append ":gerbil-ascent/" name))))
                    (file-exists? (string-append (path-strip-extension path) ".o1")))
         (error "dependency selection benchmark requires native modules" name))))
   '("core/dependency-graph" "core/rule-semantics" "program/planning"
     "program/update-selection" "t/performance/update-dependencies/reference"))
  (displayln "NATIVE-MODULES-OK") (force-output)
  (let* ((wide? (string-prefix? "wide" scenario))
         (unchanged? (string-suffix? "unchanged" scenario))
         (count 64)
         (names (map (lambda (n) (string->symbol (string-append "r" (number->string n)))) (iota count)))
         (variable (gerbil-ascent-variable 'x))
         (atom (lambda (index) (gerbil-ascent-atom (list-ref names index) [variable])))
         (rules (if wide?
                  (map (lambda (_) (gerbil-ascent-rule (map atom (iota 32 32))
                                                      (map atom (iota 32)))) (iota 16))
                  (map (lambda (index) (gerbil-ascent-rule [(atom (+ index 1))] [(atom index)]))
                       (iota 63))))
         (relations (map (lambda (name) (gerbil-ascent-relation name 1 '((1)))) names))
         (program (gerbil-ascent-program relations rules 128 8192 16384))
         (analysis (gerbil-ascent-prepare-program relations rules
                    (gerbil-ascent-program-schema program relations) #f))
         (before (list->vector (map (lambda (index) (cons (if (and (zero? index) (not unchanged?)) [] '((1))) []))
                                   (iota count))))
         (old (lambda () (old-selection before program analysis)))
         (new (lambda () (gerbil-ascent-update-selection before program analysis)))
         (ab []) (bb []) (ac []) (bc []) (wins 0))
    (##gc)
    (unless (equal? (old) (new)) (error "selection warm parity"))
    (let loop ((sample 0))
      (when (< sample 100)
        (let-values (((a x y b u v)
                      (if (even? sample)
                        (let-values (((a x y) (measure old)) ((b u v) (measure new))) (values a x y b u v))
                        (let-values (((b u v) (measure new)) ((a x y) (measure old))) (values a x y b u v)))))
          (unless (equal? a b) (error "selection paired parity" scenario sample))
          (set! ab (cons x ab)) (set! bb (cons u bb))
          (set! ac (cons y ac)) (set! bc (cons v bc))
          (when (< v y) (set! wins (+ wins 1))))
        (when (zero? (modulo (+ sample 1) 10))
          (displayln "PROGRESS " scenario " " (+ sample 1) "/100") (force-output))
        (loop (+ sample 1))))
    (displayln "RESULT " scenario " old-bytes=" (median ab) " new-bytes=" (median bb)
               " old-cpu-us=" (* 1000000 (median ac)) " new-cpu-us=" (* 1000000 (median bc))
               " cpu-wins=" wins "/100") (force-output)
    ;; Set before sampling. Narrow graphs are a regression control; the wide
    ;; cases must reduce allocation by 20%, CPU by 10%, and win 75/100 pairs.
    (unless (and (<= (median bb) (median ab))
                 (if wide?
                   (and (<= (median bb) (* 0.8 (median ab)))
                        (<= (median bc) (* 0.9 (median ac))) (>= wins 75))
                   (<= (median bc) (* 1.05 (median ac)))))
      (error "selection allocation/CPU gate failed" scenario wins))
    (displayln "OK") (force-output)))
