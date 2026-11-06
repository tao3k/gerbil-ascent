;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object :gerbil-ascent/program/summary
        :gerbil-ascent/t/performance/declaration-summary/fixture
        (prefix-in :gerbil-ascent/t/performance/declaration-summary/reference old-))
(export ascent-declaration-summary-test)
(def (summary-check program)
  (check-equal? (summary-data (gerbil-ascent-program-summary program))
                (summary-data (old-gerbil-ascent-program-summary program))))
(def (graph-declaration mask duplicate? reverse?)
  (def (name n) (list-ref '(a b c) n))
  (.o
   (rules
    (map (lambda (consumer)
           (.o
            (heads (make-list (if duplicate? 3 1) (.o (relation (name consumer)))))
            (body
             (let (reads
                   (filter-map
                    (lambda (producer)
                      (and (not (zero? (bitwise-and mask (arithmetic-shift 1 (+ (* producer 3) consumer)))))
                           (.o (relation (name producer))
                               (ascent-clause-kind (list-ref '(atom negation aggregate) producer)))))
                    (iota 3)))
               (append (if reverse? (reverse reads) reads)
                       (if duplicate? reads [])
                       (list (.o (ascent-clause-kind 'guard)) (.o (ascent-clause-kind 'binding))))))))
         (iota 3)))))
(def ascent-declaration-summary-test
  (test-suite "Declaration dependency publication"
    (test-case "all three-rule graphs preserve exact descriptors and component order"
      (for-each
       (lambda (mask)
         (for-each (lambda (variant)
                     (summary-check (graph-declaration mask (car variant) (cdr variant))))
                   '((#f . #f) (#t . #f) (#t . #t))))
       (iota 512)))
    (test-case "independent expected summaries cover all benchmark shapes"
      (for-each
       (lambda (config)
         (with ([width count shape] config)
           (let (input (summary-input width count shape))
             (check-equal? (summary-workflow #f input) (summary-expected input))
             (check-equal? (summary-workflow #t input) (summary-expected input)))))
       '((16 16 repeated) (8 16 dense) (1 128 chain) (1 128 isolated) (1 1 repeated) (0 0 repeated))))
    (test-case "shared multihead producers and interleaved repeated reads preserve ordering"
      (let* ((head-items (map (lambda (name) (.o (relation name))) '(b a b c a)))
             (reads (map (lambda (name kind) (.o (relation name) (ascent-clause-kind kind)))
                         '(c b a c a missing) '(aggregate atom negation atom aggregate atom)))
             (program (.o (rules (list (.o (heads head-items) (body []))
                                       (.o (heads (reverse head-items)) (body reads))
                                       (.o (heads []) (body reads)))))))
        (summary-check program)
        (check-equal? (map (lambda (head) (.ref head 'relation)) head-items) '(b a b c a))
        (check-equal? (map (lambda (clause) (.ref clause 'relation)) reads) '(c b a c a missing))))
    (test-case "membership is invocation-local and current declaration metadata is observed"
      (let* ((head-items (list (.o (relation 'a))))
             (rule (.o (heads head-items) (body []))) (program (.o (rules (list rule))))
             (before (summary-data (gerbil-ascent-program-summary program))))
        (set-car! head-items (.o (relation 'changed)))
        (check-equal? before '(((0) (a) #f)))
        (check-equal? (summary-data (gerbil-ascent-program-summary program)) '(((0) (changed) #f)))
        (summary-check program)))))
