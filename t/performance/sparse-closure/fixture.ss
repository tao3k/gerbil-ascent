;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .ref)
        :gerbil-ascent/candidate/closure
        (prefix-in :gerbil-ascent/t/performance/sparse-closure/reference old-))
(export sparse-prepare sparse-consume sparse-verify! sparse-project)
(def (sparse-project result)
  (list (.ref result 'status) (.ref result 'input-count)
        (map (lambda (item)
               (map (lambda (key) (.ref item key)) '(pair distance support rule)))
             (.ref result 'candidates))))
(def (sparse-prepare old? scenario)
  (let* ((radix (case scenario ((dense) 32) ((small) 2) (else 1024)))
         (count (case scenario ((empty) 0) ((small) 1) ((dense) 31) (else 31)))
         (labels (iota count))
         (facts (map (lambda (i) (cons (+ (* i radix) (+ i 1)) i)) labels)))
    (list old? radix facts count)))
(def (sparse-consume prepared scenario)
  (with ([old? radix facts _] prepared)
    (sparse-project
     ((if old? old-gerbil-ascent-closure-candidates gerbil-ascent-closure-candidates)
      facts radix 4096 4096 (if (eq? scenario 'truncated) 10 4096)))))
(def (sparse-verify! prepared scenario)
  (with ([_ radix facts count] prepared)
    (let* ((expected
            (apply append
              (map (lambda (from)
                     (map (lambda (to)
                            (list (+ (* from radix) to) (- to from)
                                  (iota (- to from) from)
                                  (if (= to (+ from 1)) 'base 'transitive)))
                          (iota (- count from) (+ from 1)))) (iota count))))
           (truncated? (eq? scenario 'truncated)))
      (unless (equal? (sparse-consume prepared scenario)
                     (list (if truncated? 'output-truncated 'complete)
                           (length facts) (if truncated? (take expected 10) expected)))
        (error "independent sparse closure truth differs" scenario)))))
