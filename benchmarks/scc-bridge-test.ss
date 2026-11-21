;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/iter for in-range)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/func gerbil-ascent-program gerbil-ascent-relation
                 gerbil-ascent-variable gerbil-ascent-rule gerbil-ascent-atom)
        (only-in :gerbil-ascent/program/session gerbil-ascent-session-run
                 gerbil-ascent-session-replace-source!)
        (only-in :gerbil-ascent/program/actor-session gerbil-ascent-open-condensed-actor-session
                 gerbil-ascent-session-close!))
(export scc-bound-query-test scc-first-origin-test scc-split-merge-test
        scc-ten-million-split-merge-test scc-ten-million-local-split-merge-test)

(def vertices 1664)
(def group-width 64)
(def logical-rows 1437696)
(def split-source (- (* 13 group-width) 1))
(def hit '(64 1663))
(def miss '(64 0))
(def clock (make-u64vector 1 0))
(def ticks-per-sec
  (begin (##get-monotonic-time-frequency! clock 0) (u64vector-ref clock 0)))
(def (tick)
  (##get-monotonic-time! clock 0)
  (u64vector-ref clock 0))

(def (inputs omit-bridge? (return-bridge? #f) (size vertices) (return-target 0))
  (let (edges [])
    (for (v (in-range size))
      (let* ((from (* group-width (quotient v group-width))) (to (+ from group-width)))
        (for (w (in-range from to))
          (unless (= v w) (set! edges (cons (list v w) edges))))
        (when (and (= v (- to 1)) (< to size) (not (and omit-bridge? (= v split-source))))
          (set! edges (cons (list v to) edges)))
        (when (and return-bridge? (= v (- size 1)))
          (set! edges (cons (list v return-target) edges)))))
    (reverse! edges)))

(def (program facts (room logical-rows))
  (let* ((x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y))
         (z (gerbil-ascent-variable 'z))
         (edge (gerbil-ascent-atom 'edge (list x y)))
         (reach (gerbil-ascent-atom 'reach (list x y))))
    (gerbil-ascent-program
      (list (gerbil-ascent-relation 'edge 2 facts) (gerbil-ascent-relation 'reach 2 []))
      (list (gerbil-ascent-rule (list reach) (list edge))
            (gerbil-ascent-rule (list (gerbil-ascent-atom 'reach (list x z)))
              (list reach (gerbil-ascent-atom 'edge (list y z)))))
      (length facts) room (+ (length facts) room))))

(def (ordered-p95 samples)
  (list-ref samples (- (quotient (+ (* 95 (length samples)) 99) 100) 1)))

(def (report name samples)
  (let* ((ordered (list-sort < samples)) (count (length ordered))
         (p95 (ordered-p95 ordered)))
    (write (list 'TIMING name count (* 1000. (/ p95 ticks-per-sec))
                 (* 1000. (/ (car (reverse ordered)) ticks-per-sec))))
    (newline)
    (force-output)))

(def (collector expected key)
  (let (count 0)
    (values (lambda (left right)
              (unless (and (= left (car key)) (= right (cadr key))) (error "incorrect selected row"))
              (set! count (+ count 1)))
            (lambda () (check count => expected)))))

(def (hot name result key expected)
  (let* ((count 1000) (visit (.ref result 'visit-rows))
         (samples (make-vector count 0)))
    (let-values (((consume verify) (collector (* count expected) key)))
      (for (i (in-range count))
        (let (start (tick))
          (visit 'reach '(0 1) key consume fields?: #t)
          (vector-set! samples i (- (tick) start))))
      (verify))
    (report name (vector->list samples))))

(def (after-edit name session cut opposite expected)
  (let ((queries []) (replacements []) (publications []) (count 32))
    (let-values (((consume verify) (collector (* count expected) hit)))
      (for (_ (in-range count))
        (gerbil-ascent-session-replace-source! session 'edge opposite)
        (gerbil-ascent-session-run session)
        (let (replace-start (tick))
          (gerbil-ascent-session-replace-source! session 'edge cut)
          (let* ((publish-start (tick))
                 (result (gerbil-ascent-session-run session))
                 (published (tick))
                 (visit (.ref result 'visit-rows))
                 (query-start (tick)))
            (visit 'reach '(0 1) hit consume fields?: #t)
            (set! queries (cons (- (tick) query-start) queries))
            (set! replacements (cons (- publish-start replace-start) replacements))
            (set! publications (cons (- published publish-start) publications))
            (check (.ref result 'evaluation-path) => 'condensed-closure)
            (check (.ref result 'closure-update) => (if (= expected 0) 'removed 'inserted)))))
      (verify))
    (report name queries)
    (report (if (= expected 0) 'remove-replace 'restore-replace) replacements)
    (report (if (= expected 0) 'remove-publish 'restore-publish) publications)))

(def scc-bound-query-test
  (test-suite "Double-bound query of a published component closure"
    (test-case "Same-version hit and miss and removal and restoration of a bridge"
      (check (##current-vm-processor-count) => 1)
      (let* ((intact (inputs #f)) (split (inputs #t))
             (session (gerbil-ascent-open-condensed-actor-session (program intact))))
        (try
          (let* ((begin (tick)) (initial (gerbil-ascent-session-run session))
                 (end (tick)))
            (check (.ref initial 'evaluation-path) => 'condensed-closure)
            (report 'first-publish (list (- end begin)))
            (hot 'same-hit initial hit 1)
            (hot 'same-miss initial miss 0)
            (after-edit 'removed-query session split intact 0)
            (after-edit 'restored-query session intact split 1)
            (hot 'old-view-hit initial hit 1))
          (finally (gerbil-ascent-session-close! session)))))))

(def (first-origin session cut limit)
  (gerbil-ascent-session-replace-source! session 'edge cut)
  (let* ((result (gerbil-ascent-session-run session))
         (visit (.ref result 'visit-rows))
         (next 64))
    (check (.ref result 'evaluation-path) => 'condensed-closure)
    (let* ((consume (lambda (left right)
                      (unless (and (= left 64) (= right next)) (error "unordered origin result"))
                      (set! next (+ next 1))))
           (start (tick)))
      (visit 'reach '(0) '(64) consume fields?: #t)
      (let (elapsed (- (tick) start))
        (check next => limit)
        elapsed))))

(def scc-first-origin-test
  (test-suite "First origin-bound query after a bridge edit"
    (test-case "Ordered first traversal after deleting and restoring the bridge"
      (check (##current-vm-processor-count) => 1)
      (let* ((intact (inputs #f)) (split (inputs #t))
             (session (gerbil-ascent-open-condensed-actor-session (program intact)))
             (separated []) (restored []))
        (try
          (gerbil-ascent-session-run session)
          (for (_ (in-range 32))
            (set! separated (cons (first-origin session split 832) separated))
            (set! restored (cons (first-origin session intact 1664) restored)))
          (report 'removed-first-origin separated)
          (report 'restored-first-origin restored)
          (finally (gerbil-ascent-session-close! session)))))))

(def (observe-edit bytes action)
  (let* ((before (##process-statistics))
         (_ (##get-bytes-allocated! bytes 0))
         (start (tick))
         (value (action))
         (elapsed (- (tick) start))
         (_ (##get-bytes-allocated! bytes 1))
         (after (##process-statistics)))
    (def (delta slot) (- (f64vector-ref after slot) (f64vector-ref before slot)))
    (values value
      (list elapsed (* 1000. (+ (delta 0) (delta 1)))
            (- (f64vector-ref bytes 1) (f64vector-ref bytes 0))
            (* 1000. (delta 5)) (delta 6)))))

(def (report-edit direction replacement publication query)
  (def (p95 samples) (ordered-p95 (list-sort < samples)))
  (for-each
    (lambda (phase samples)
      (report (string->symbol (string-append (symbol->string direction) "-" (symbol->string phase)))
        (map car samples))
      (write (list 'COST direction phase
                   'cpu-p95-ms (p95 (map cadr samples))
                   'allocated-p95-bytes (p95 (map caddr samples))
                   'gc-p95-ms (p95 (map cadddr samples))
                   'gc-max-ms (apply max (map cadddr samples))
                   'gc-count (apply + (map (lambda (sample) (list-ref sample 4)) samples))
                   'negative-allocation (length (filter (lambda (sample) (< (caddr sample) 0)) samples))))
      (newline)
      (for-each
        (lambda (sample)
          (write (cons* 'EDIT-SAMPLE direction phase
                   (* 1000. (/ (car sample) ticks-per-sec)) (cdr sample)))
          (newline))
        (reverse samples)))
    '(replace publish first-origin) (list replacement publication query)))

;; The return bridge closes a suffix of the chain of cliques.
(def (measure-split-merge size (return-target 0))
  (check (##current-vm-processor-count) => 1)
  (let* ((intact (inputs #f #t size return-target)) (split (inputs #f #f size))
         (groups (quotient size group-width))
         (merged-groups (quotient (- size return-target) group-width))
         (split-rows (* group-width group-width (quotient (* groups (+ groups 1)) 2)))
         (merged-rows (+ split-rows
                         (* group-width group-width (quotient (* merged-groups (- merged-groups 1)) 2))))
         (session (gerbil-ascent-open-condensed-actor-session (program intact merged-rows)))
         (from (- size 1)) (bytes (make-f64vector 2 0.))
         (split-replace []) (split-publish []) (split-query [])
         (merge-replace []) (merge-publish []) (merge-query []))
    (def (edit cut merging?)
      (let*-values (((_ replace-cost)
                     (observe-edit bytes (lambda () (gerbil-ascent-session-replace-source! session 'edge cut))))
                    ((result publish-cost)
                     (observe-edit bytes (lambda () (gerbil-ascent-session-run session)))))
        (let* ((visit (.ref result 'visit-rows))
               (next (if merging? return-target (- size group-width))))
          (let-values (((_ query-cost)
                        (observe-edit bytes
                          (lambda ()
                            (visit 'reach '(0) (list from)
                              (lambda (left right)
                                (unless (and (= left from) (= right next))
                                  (error "incorrect first origin" left right))
                                (set! next (+ next 1)))
                              fields?: #t)))))
            (check next => size)
            (check (.ref result 'evaluation-path) => 'condensed-closure)
            (check (.ref result 'closure-update) => 'rebuilt)
            (check (cdr (assq 'reach ((.ref result 'relation-sizes))))
                   => (if merging? merged-rows split-rows))
            (if merging?
              (begin
                (set! merge-replace (cons replace-cost merge-replace))
                (set! merge-publish (cons publish-cost merge-publish))
                (set! merge-query (cons query-cost merge-query)))
              (begin
                (set! split-replace (cons replace-cost split-replace))
                (set! split-publish (cons publish-cost split-publish))
                (set! split-query (cons query-cost split-query))))
            result))))
    (try
      (let* ((original (gerbil-ascent-session-run session))
             (proof ((.ref original 'closure-witness) from return-target 128)))
        (check ((.ref original 'verify-closure-witness) proof) => #t)
        (for (_ (in-range 32))
          (let* ((separated (edit split #f)) (restored (edit intact #t))
                 (fresh ((.ref restored 'closure-witness) from return-target 128)))
            (check ((.ref separated 'closure-witness) from return-target 128) => #f)
            (check ((.ref separated 'verify-closure-witness) proof) => #f)
            (check ((.ref restored 'verify-closure-witness) proof) => #f)
            (check ((.ref restored 'verify-closure-witness) fresh) => #t)))
        (check ((.ref original 'verify-closure-witness) proof) => #t)
        (write (list 'WORKLOAD 'vertices size 'merged-components merged-groups
                     'split-input (length split) 'merged-input (length intact)
                     'split-rows split-rows 'merged-rows merged-rows))
        (newline)
        (report-edit 'split split-replace split-publish split-query)
        (report-edit 'merge merge-replace merge-publish merge-query))
      (finally (gerbil-ascent-session-close! session)))))

(def scc-split-merge-test
  (test-suite "Split and merge a published component using a return bridge"
    (test-case "Measure publication and first ordered origin query on both versions"
      (measure-split-merge vertices))))

(def scc-ten-million-split-merge-test
  (test-suite "Split and merge a ten-million-row logical closure"
    (test-case "Measure publication and first ordered origin query on both versions"
      (measure-split-merge (* 50 group-width)))))

(def scc-ten-million-local-split-merge-test
  (test-suite "Split and merge two components in a ten-million-row logical closure"
    (test-case "Only the last two components change their mutual reachability"
      (measure-split-merge (* 71 group-width) (* 69 group-width)))))
