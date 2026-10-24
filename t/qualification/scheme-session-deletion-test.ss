;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? check-exception test-case test-suite)
        (only-in :gerbil-ascent/core/rule-semantics gerbil-ascent-rule-successors)
        (only-in :gerbil-ascent/core/dependency-graph gerbil-ascent-graph-close!)
        (only-in :gerbil/runtime/gambit call-with-output-string display-exception)
        (only-in :clan/poo/object .o .ref)
        (only-in :gerbil-ascent/program/scheme-language relational-program)
        (only-in :gerbil-ascent/program/objects gerbil-ascent-program gerbil-ascent-guard
                 gerbil-ascent-relation gerbil-ascent-atom gerbil-ascent-rule
                 gerbil-ascent-variable gerbil-ascent-literal)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/program/update-selection gerbil-ascent-update-selection
                 gerbil-ascent-update-eligible?)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-set-storage-provider)
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session
                 gerbil-ascent-session-run gerbil-ascent-session-append-source!
                 gerbil-ascent-session-replace-source! gerbil-ascent-session-replace-sources!))
(export scheme-session-deletion-test session-benefit-main)

;; A fresh update starts from the same immutable declarations and replacement
;; rows as a retained transaction. POO field names are implicit bindings: a
;; lexical value named `relations` would become a recursive self-field here.
(def (fresh-replacement-program base-program replacements)
  (let (replacement-relations
        (map (lambda (relation)
               (let (replacement (assq (.ref relation 'name) replacements))
                 (.o (:: @ relation)
                     rows: (if replacement (cdr replacement) (.ref relation 'rows)))))
             (.ref base-program 'relations)))
    (.o (:: @ base-program) relations: replacement-relations)))

;;; Counterbalanced native samples. Construction, initial session solve, GC
;;; and independent checking are outside each timer. Session replacement keeps
;;; its actual snapshot/admission/publication costs inside the timed operation;
;;; fresh evaluation includes engine admission and publication. No speed gate.
(def (session-benefit-main)
  (def allocations (make-f64vector 2 0.0))
  ;; Verified against the installed Gambit dcd677c _kernel.scm:
  ;; get-bytes-allocated! writes the native allocator counter into this buffer.
  ;; The buffer and result vector are allocated outside each timing boundary.
  (def (sample thunk batch)
    (let* ((results (make-vector batch #f)) (indices (iota batch))
           (wall (current-jiffy)) (cpu (cpu-time)))
      (##get-bytes-allocated! allocations 0)
      (for-each (lambda (n) (vector-set! results n (thunk n))) indices)
      (##get-bytes-allocated! allocations 1)
      (let ((cpu-seconds (- (cpu-time) cpu))
            (wall-seconds (/ (- (current-jiffy) wall) (jiffies-per-second)))
            (bytes (- (f64vector-ref allocations 1) (f64vector-ref allocations 0))))
        (unless (>= bytes 0) (error "native allocation counter regressed"))
        (vector results (/ wall-seconds batch) (/ cpu-seconds batch) (/ bytes batch)))))
  (def (benchmark-program edges cold)
    (let (program (relational-program
     (relation edge (from to) edges) (relation path (from to) '())
     (relation cold (value) cold) (relation seen (value) '())
     (rule (path ?x ?y) (edge ?x ?y))
     (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
     (rule (seen ?x) (cold ?x))
     (limits 128 8192 262144)))
      (displayln "BENEFIT-DECLARED edges=" (length edges))
      (force-output)
      program))
  ;; A complete fresh update starts with the same base declarations and ready
  ;; replacement rows as Session replacement. Candidate construction belongs
  ;; inside both update timers. Keep solve-only as a separately named control.
  (def (check-result result edges nodes first cold)
    (check-equal? (.ref result 'finished) #t)
    (check-set (rows result 'edge) edges)
    (check-set (rows result 'cold) cold)
    (check-set (rows result 'seen) cold)
    ;; Independent chain model: first <= x < y <= nodes, no duplicates, and
    ;; the complete triangular cardinality. Membership plus cardinality implies
    ;; exact closure, without a quadratic membership scan of every result.
    (let ((seen (make-hash-table test: equal?)) (count (+ (- nodes first) 1)))
      (for-each
       (lambda (row)
         (unless (and (list? row) (= (length row) 2)
                      (integer? (car row)) (integer? (cadr row))
                      (<= first (car row)) (< (car row) (cadr row))
                      (<= (cadr row) nodes) (not (hash-get seen row)))
           (error "independent native chain model rejected row" row))
         (hash-put! seen row #t)) (rows result 'path))
      (check-equal? (hash-length seen) (/ (* count (- count 1)) 2))))
  (for-each
   (lambda (workload)
    (let ((nodes (car workload)) (batch (cadr workload)))
     (for-each
      (lambda (condition)
       (let* ((edges (map (lambda (x) (list x (+ x 1))) (iota nodes)))
            (edge-change? (not (eq? condition 'independent)))
            (cold-change? (not (eq? condition 'recursive)))
            (next-edges (if edge-change? (cdr edges) edges))
            (next-cold (if cold-change? '((8)) '((7))))
            (replacements
             (append (if edge-change? (list (cons 'edge next-edges)) [])
                     (if cold-change? (list (cons 'cold next-cold)) [])))
            (base (benchmark-program edges '((7))))
            (prospective (benchmark-program next-edges next-cold)))
       (let loop ((n 0))
         (when (< n 30)
           (let ((sessions
                  (list->vector
                   (map (lambda (_)
                          (let* ((session (gerbil-ascent-open-session base))
                                 (initial (gerbil-ascent-session-run session)))
                            (check-result initial edges nodes 0 '((7)))
                            (displayln "BENEFIT-INITIALIZED " condition " edges=" nodes " group=" n " instance=" _)
                            (force-output)
                            session)) (iota batch)))))
             (##gc)
             (let ((fresh #f) (updated #f) (retained #f)
                   (order (list-ref
                           '((ABC fresh updated retained) (ACB fresh retained updated)
                             (BAC updated fresh retained) (BCA updated retained fresh)
                             (CAB retained fresh updated) (CBA retained updated fresh))
                           (modulo n 6))))
               (for-each
                (lambda (arm)
                  (displayln "BENEFIT-MEASURE-START " condition " edges=" nodes " group=" n " arm=" arm)
                  (force-output)
                  (case arm
                    ((fresh) (set! fresh (sample (lambda (_) (gerbil-ascent-evaluate-program prospective)) batch)))
                    ((updated) (set! updated (sample (lambda (_) (gerbil-ascent-evaluate-program (fresh-replacement-program base replacements))) batch)))
                    ((retained) (set! retained (sample (lambda (n) (gerbil-ascent-session-replace-sources! (vector-ref sessions n) replacements)) batch)))
                    (else (error "unknown native measurement arm" arm)))
                  (displayln "BENEFIT-MEASURED " condition " edges=" nodes " group=" n " arm=" arm)
                  (force-output)) (cdr order))
               (for-each
                (lambda (a b c)
                  (check-result a next-edges nodes (if edge-change? 1 0) next-cold)
                  (check-result b next-edges nodes (if edge-change? 1 0) next-cold)
                  (check-result c next-edges nodes (if edge-change? 1 0) next-cold)
                  (check-equal? (.ref a 'active-rule-count) 3)
                  (check-equal? (.ref b 'active-rule-count) 3)
                  (check-equal? (.ref c 'active-rule-count)
                                (case condition ((independent) 1) ((recursive) 2) (else 3))))
                (vector->list (vector-ref fresh 0)) (vector->list (vector-ref updated 0)) (vector->list (vector-ref retained 0)))
               (write (list 'BENEFIT condition nodes batch n (car order)
                            (list 'solve (vector-ref fresh 1) (vector-ref fresh 2) (vector-ref fresh 3)
                                  (.ref (vector-ref (vector-ref fresh 0) 0) 'active-rule-count))
                            (list 'fresh-update (vector-ref updated 1) (vector-ref updated 2) (vector-ref updated 3)
                                  (.ref (vector-ref (vector-ref updated 0) 0) 'active-rule-count))
                            (list 'retained (vector-ref retained 1) (vector-ref retained 2) (vector-ref retained 3)
                                  (.ref (vector-ref (vector-ref retained 0) 0) 'active-rule-count))))
               (newline) (force-output)))
           (loop (+ n 1))))))
       '(independent recursive all-inputs))))
   '((12 16) (48 4)))
  (displayln "BENEFIT-OK groups=180 independent-native-verdicts=5400")
  (force-output))

(def (rows result name) ((.ref result 'rows-of) name))
(def (check-set actual expected)
  (check-equal? (length actual) (length expected))
  (for-each (lambda (row) (check-equal? (and (member row actual) #t) #t)) expected))
(def (check-fresh result program)
  (let (fresh (gerbil-ascent-evaluate-program program))
    (check-equal? (.ref result 'finished) #t)
    (for-each (lambda (name) (check-set (rows result name) (rows fresh name)))
              (.ref fresh 'relation-names))))
(def (path-program edges (cold '((7))))
  (relational-program
   (relation edge (from to) edges) (relation path (from to) '())
   (relation cold (value) cold) (relation seen (value) '())
   (rule (path ?x ?y) (edge ?x ?y))
   (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
   (rule (seen ?x) (cold ?x))
   (limits 32 256 512)))
(def (stratified-program banned supplied-weights (edges '((0 1) (1 2))))
  (relational-program
   (relation edge (from to) edges)
   (relation blocked (to) banned) (relation weight (to value) supplied-weights)
   (relation root (from) '((0))) (relation path (from to) '())
   (relation allowed (from to) '()) (relation weighted (from value) '())
   (relation summary (from value) '())
   (rule (path ?x ?y) (edge ?x ?y))
   (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
   (rule (allowed ?x ?y) (path ?x ?y) (not (blocked ?y)))
   (rule (weighted ?x ?v) (allowed ?x ?y) (weight ?y ?w)
     (where (even? ?w)) (compute ?v (+ ?w ?w)))
   (rule (summary ?r ?n) (root ?r) (reduce ?n (sum ?v) (weighted ?r ?v)))
   (limits 32 256 512)))
(def (lattice-program inputs cold)
  (relational-program
   (relation input (key value) inputs) (lattice best (key value) '() max)
   (relation answer (key value) '()) (relation cold (value) cold)
   (relation seen (value) '())
   (rule (best ?k ?v) (input ?k ?v)) (rule (answer ?k ?v) (best ?k ?v))
   (rule (seen ?v) (cold ?v)) (limits 32 256 512)))
(def corpus-edges '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)))
(def (edges-for-mask mask)
  (filter-map (lambda (edge index) (and (odd? (quotient mask (expt 2 index))) edge)) corpus-edges (iota 6)))
(def (matrix-closure edges)
  (let (matrix (make-vector 9 #f))
    (for-each (lambda (edge) (vector-set! matrix (+ (* 3 (car edge)) (cadr edge)) #t)) edges)
    (for-each (lambda (k)
      (for-each (lambda (i)
        (for-each (lambda (j)
          (when (and (vector-ref matrix (+ (* 3 i) k)) (vector-ref matrix (+ (* 3 k) j)))
            (vector-set! matrix (+ (* 3 i) j) #t))) (iota 3))) (iota 3))) (iota 3))
    (filter-map (lambda (i) (and (vector-ref matrix i) (list (quotient i 3) (modulo i 3)))) (iota 9))))

(def scheme-session-deletion-test
  (test-suite "Native dependency invalidation and source withdrawal"
    (test-case "only reading clauses compile source-to-every-head edges"
      (let* ((plans
              (list (vector (list (vector 1 []) (vector 2 []))
                            (list (vector 'atom (vector 0 []))
                                  (vector 'negation (vector 0 []))
                                  (vector 'aggregate (vector 0 []))
                                  (vector 'guard #f)
                                  (vector 'generator #f)
                                  (vector 'binding #f)))))
             (successors (gerbil-ascent-rule-successors plans 3)))
        (check-equal? (andmap (lambda (target)
                                (and (member target (vector-ref successors 0)) #t))
                              '(1 2))
                      #t)
        (check-equal? (vector-ref successors 1) [])
        (check-equal? (vector-ref successors 2) [])))
    (test-case "cached adjacency remains read-only across independent closures"
      (let ((graph '#((0 1 1) (2) (2)))
            (first (vector #t #f #f))
            (second (vector #f #f #t)))
        (gerbil-ascent-graph-close! graph first)
        (gerbil-ascent-graph-close! graph second)
        (check-equal? first '#(#t #t #t))
        (check-equal? second '#(#f #f #t))
        (check-equal? graph '#((0 1 1) (2) (2))))
      (gerbil-ascent-graph-close! '#() '#())
      (let* ((count 4096)
             (graph (list->vector
                     (map (lambda (index) (if (= (+ index 1) count) [] [(+ index 1)]))
                          (iota count))))
             (selected (make-vector count #f)))
        (vector-set! selected 0 #t)
        (gerbil-ascent-graph-close! graph selected)
        (check-equal? (andmap identity (vector->list selected)) #t)
        (check-equal? (vector-ref graph 0) '(1))
        (check-equal? (vector-ref graph (- count 1)) [])))
    (test-case "every changed-source subset closes to independent matrix reachability"
      ;; The Lean bitmap model permits any seed subset. Compare the actual
      ;; mutable vector/list loop with a separate transitive-closure oracle.
      (for-each
       (lambda (mask)
         (let* ((edges (edges-for-mask mask))
                (closure (matrix-closure edges))
                (graph
                 (list->vector
                  (map (lambda (source)
                         (map cadr (filter (lambda (edge) (= (car edge) source)) edges)))
                       (iota 3)))))
           (for-each
            (lambda (seed-mask)
              (def (seeded? index)
                (odd? (quotient seed-mask (expt 2 index))))
              (let (selected (list->vector (map seeded? (iota 3))))
                (gerbil-ascent-graph-close! graph selected)
                (check-equal?
                 (vector->list selected)
                 (map (lambda (target)
                        (or (seeded? target)
                            (and (ormap
                                  (lambda (source)
                                    (and (seeded? source)
                                         (member (list source target) closure)))
                                  (iota 3))
                                 #t)))
                      (iota 3)))))
            (iota 8))))
       (iota 64)))
    (test-case "completed reuse matches real finite rule evaluation and matrix oracle"
      ;; Each graph is compiled into actual recursive Core rules. For every
      ;; source cut, compare the retained result, a fresh solve, and a matrix
      ;; oracle which never reads the compiler's successor vector.
      (let (names '(a b c))
        (for-each
         (lambda (mask)
           (let* ((edges (edges-for-mask mask))
                  (closure (matrix-closure edges))
                  (x (gerbil-ascent-variable 'x))
                  (base
                   (gerbil-ascent-program
                    (map (lambda (name) (gerbil-ascent-relation name 1 '((0)))) names)
                    (map (lambda (edge)
                           (gerbil-ascent-rule
                            (list (gerbil-ascent-atom (list-ref names (cadr edge)) (list x)))
                            (list (gerbil-ascent-atom (list-ref names (car edge)) (list x)))))
                         edges)
                    8 16 32)))
             (for-each
              (lambda (seed-mask)
                (def (seeded? source)
                  (odd? (quotient seed-mask (expt 2 source))))
                (def (reaches? source target)
                  (or (= source target)
                      (and (member (list source target) closure) #t)))
                (let* ((changed
                        (filter-map (lambda (index)
                                      (and (seeded? index)
                                           (cons (list-ref names index) '((1)))))
                                    (iota 3)))
                       (replacements (if (null? changed) '((a (0))) changed))
                       (session (gerbil-ascent-open-session base))
                       (initial (gerbil-ascent-session-run session))
                       (updated (gerbil-ascent-session-replace-sources!
                                 session replacements))
                       (fresh (gerbil-ascent-evaluate-program
                               (fresh-replacement-program base replacements))))
                  (for-each
                   (lambda (target)
                     (let ((name (list-ref names target))
                           (expected
                            (append
                             (if (ormap (lambda (source)
                                          (and (not (seeded? source))
                                               (reaches? source target))) (iota 3))
                               '((0)) [])
                             (if (ormap (lambda (source)
                                          (and (seeded? source)
                                               (reaches? source target))) (iota 3))
                               '((1)) []))))
                       (check-set (rows initial name) '((0)))
                       (check-set (rows updated name) expected)
                       (check-set (rows updated name) (rows fresh name))
                       (check-equal?
                        (and (memq name (.ref updated 'reused-relations)) #t)
                        (not (ormap (lambda (source)
                                      (and (seeded? source)
                                           (reaches? source target))) (iota 3))))))
                   (iota 3))
                  (check-equal? (.ref updated 'evaluation-path)
                                'stratified-dependency-invalidation)))
              (iota 8))
             (displayln "READ-FRAME-CHECKED graph=" mask " seed-cuts=8")
             (force-output)))
         (iota 64))))
    (test-case "fresh replacement reads lexical candidate rows without self-field recursion"
      (let* ((base (path-program '((0 1) (1 2))))
             (candidate (fresh-replacement-program
                         base '((edge (1 2)) (cold (8)))))
             (updated (gerbil-ascent-evaluate-program candidate)))
        (check-set (rows updated 'edge) '((1 2)))
        (check-set (rows updated 'path) '((1 2)))
        (check-set (rows updated 'cold) '((8)))
        (check-set (rows updated 'seen) '((8)))
        (for-each
         (lambda (field) (check-equal? (.ref candidate field) (.ref base field)))
         '(rules source-handles max-input-facts max-derived-facts max-output-facts))
        (let (original (gerbil-ascent-evaluate-program base))
          (check-set (rows original 'edge) '((0 1) (1 2)))
          (check-set (rows original 'path) '((0 1) (0 2) (1 2)))
          (check-set (rows original 'seen) '((7))))
        (let (empty (gerbil-ascent-evaluate-program
                     (fresh-replacement-program base '((edge)))))
          (check-set (rows empty 'edge) '())
          (check-set (rows empty 'path) '())
          (check-set (rows empty 'seen) '((7))))))
    (test-case "source log comparison retains base order, reverse appends, duplicates and nullary facts"
      (for-each
       (lambda (fixture)
         (let* ((base (vector-ref fixture 1)) (additions (vector-ref fixture 2))
                (before (vector (cons base additions)))
                (candidate (gerbil-ascent-program
                            (list (gerbil-ascent-relation 'input (vector-ref fixture 0)
                                                         (vector-ref fixture 3))) [] 64 64 128)))
           (check-equal? (vector-ref (gerbil-ascent-update-selection before candidate (vector [] [] [] #f #f #f '#(()))) 0)
                         (vector-ref fixture 4))
           (check-equal? (eq? base (car (vector-ref before 0))) #t)
           (check-equal? (eq? additions (cdr (vector-ref before 0))) #t)))
       (list '#(1 ((1) (1) (#f)) () ((1) (1) (#f)) #f)
             '#(1 ((1) (1) (#f)) () ((1) (#f) (1)) #t)
             '#(1 ((1) (1) (#f)) ((3) (2)) ((1) (1) (#f) (2) (3)) #f)
             '#(1 ((1) (1) (#f)) ((3) (2)) ((1) (1) (#f) (3) (2)) #t)
             '#(1 ((1) (1)) ((3) (2)) ((1) (2) (3)) #t)
             '#(1 () ((3) (2)) ((2) (3)) #f)
             '#(1 ((1)) ((3) (2)) () #t)
             '#(0 (() ()) (()) (() () ()) #f)
             '#(0 (() ()) (()) (() ()) #t))))
    (test-case "replacement of a materialized append log retains closure and later updates"
      (let* ((session (gerbil-ascent-open-session (path-program '((0 1)))))
             (first (gerbil-ascent-session-run session)))
        (gerbil-ascent-session-append-source! session 'edge '(1 2))
        (gerbil-ascent-session-append-source! session 'edge '(2 3))
        (let (appended (gerbil-ascent-session-run session))
          (gerbil-ascent-session-replace-source! session 'edge '((0 1) (1 2) (2 3)))
          (let (same (gerbil-ascent-session-run session))
            (check-equal? (.ref same 'active-rule-count) 0)
            (check-equal? (rows same 'path) (rows appended 'path))
            (check-set (rows first 'path) '((0 1))))
          (gerbil-ascent-session-replace-source! session 'edge '((0 1) (2 3)))
          (check-fresh (gerbil-ascent-session-run session) (path-program '((0 1) (2 3)))))))
    (test-case "lowered dependencies agree with matrix reachability for every graph and root"
      ;; Exercise the lowered dependency boundary independently of rule planning.
      ;; Atom, negation and aggregate reads all propagate to every head.
      (let (candidate
            (relational-program
             (relation a (value) '((1))) (relation b (value) '((1)))
             (relation c (value) '((1))) (limits 8 8 16)))
        (for-each
         (lambda (mask)
           (let* ((edges (edges-for-mask mask))
                  (closure (matrix-closure edges))
                  (plans
                   (map (lambda (edge index)
                          (vector (list (vector (cadr edge) []) (vector (cadr edge) []))
                                  (list (vector (list-ref '(atom negation aggregate) (modulo index 3))
                                                (vector (car edge) [])))))
                        edges (iota (length edges))))
                  (successors (gerbil-ascent-rule-successors plans 3))
                  (graph-before (vector-map (lambda (targets) (map identity targets)) successors)))
             (for-each
              (lambda (root)
                (let* ((before (list->vector
                                (map (lambda (index) (cons (if (= index root) [] '((1))) []))
                                     (iota 3))))
                       (actual (gerbil-ascent-update-selection before candidate
                                                              (vector [] [] plans #f #f #f successors))))
                  (check-equal?
                   (vector->list actual)
                   (map (lambda (target)
                          (or (= target root) (and (member (list root target) closure) #t)))
                        (iota 3)))
                  (check-equal? successors graph-before)))
              (iota 3))))
         (iota 64))))
    (test-case "unchanged lattice source joins consume no reused derived budget"
      (let* ((program
              (relational-program
               (lattice best (key value) '((1 2) (1 5)) max)
               (relation input (key value) '((2 9)))
               (relation cold (value) '((7) (7)))
               (rule (best ?k ?v) (input ?k ?v))
               (limits 8 1 16)))
             (session (gerbil-ascent-open-session program))
             (old (gerbil-ascent-session-run session))
             (updated (gerbil-ascent-session-replace-sources! session '((cold (8) (8))))))
        (check-set (rows old 'best) '((1 5) (2 9)))
        (check-set (rows updated 'best) '((1 5) (2 9)))
        (check-equal? (rows updated 'cold) '((8) (8)))
        (check-equal? (.ref updated 'active-rule-count) 0)
        (check-exception (gerbil-ascent-session-replace-sources! session '((input (2 9) (3 10)))) true)
        (check-equal? (eq? updated (gerbil-ascent-session-run session)) #t)))
    (test-case "field callbacks require fresh evaluation and preserve source membership"
      (let* ((cell (list 7)) (armed? #f) (checks 0)
             (checker (lambda (value)
                        (when armed?
                          (set! checks (+ checks 1))
                          (set-car! value (+ (car value) 1)))
                        #t))
             (base
              (relational-program
               (relation item (value) '())
               (relation input (value) '((1))) (relation out (value) '())
               (relation trigger (value) '((0)))
               (rule (out ?v) (input ?v)) (limits 8 1 16)))
             (declarations (.ref base 'relations))
             (updated-declarations
              (cons (gerbil-ascent-relation
                     'item 1 (list (list cell))
                     (.ref (car declarations) 'index-provider)
                     (.ref (car declarations) 'storage-provider)
                     (list checker))
                    (cdr declarations)))
             (program (.o (:: @ base) relations: updated-declarations))
             (session (gerbil-ascent-open-session program)))
        (gerbil-ascent-session-run session)
        (set! armed? #t)
        (let (updated (gerbil-ascent-session-replace-sources! session '((trigger (1)))))
          (check-equal? (.ref updated 'finished) #t)
          (check-equal? (.ref updated 'evaluation-path) 'stratified-semi-naive)
          (check-equal? checks 2)
          (check-equal? (rows updated 'item) '(((9))))
          (check-equal? (rows updated 'out) '((1))))
        ;; Eligibility itself invokes no callback; each fresh replacement
        ;; checks its admitted source rows independently.
        (check-equal? (gerbil-ascent-update-eligible? program) #f)
        (check-equal? checks 2)
        (let (updated (gerbil-ascent-session-replace-sources! session '((trigger (2)))))
          (check-equal? (.ref updated 'finished) #t)
          (check-equal? (.ref updated 'evaluation-path) 'stratified-semi-naive)
          (check-equal? checks 4)
          (check-equal? (rows updated 'item) '(((11))))
          (check-equal? (rows updated 'out) '((1))))))
    (test-case "field callback changing a shared payload requires fresh evaluation"
      (let* ((cell (list 1)) (armed? #f)
             (checker (lambda (_)
                        (when armed? (set-car! cell 2))
                        #t))
             (program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'input 1 (list (list cell)))
                     (gerbil-ascent-relation 'probe 1 '((0))
                                             gerbil-ascent-hash-index-provider
                                             gerbil-ascent-set-storage-provider
                                             (list checker))
                     (gerbil-ascent-relation 'trigger 1 '((0)))
                     (gerbil-ascent-relation 'out 1 []))
               (list (gerbil-ascent-rule
                      (list (gerbil-ascent-atom 'out
                              (list (gerbil-ascent-literal 'hit))))
                      (list (gerbil-ascent-atom 'input
                              (list (gerbil-ascent-literal (list 1)))))))
               8 16 32))
             (session (gerbil-ascent-open-session program)))
        (check-set (rows (gerbil-ascent-session-run session) 'out) '((hit)))
        (set! armed? #t)
        (let (updated (gerbil-ascent-session-replace-sources! session '((trigger (1)))))
          (check-set (rows updated 'input) '(((2))))
          (check-set (rows updated 'out) '())
          (check-equal? (.ref updated 'evaluation-path) 'stratified-semi-naive))))
    (test-case "mutable Core source payload cannot authorize completed reuse"
      (let* ((cell (list 1))
             (program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'input 1 (list (list cell)))
                     (gerbil-ascent-relation 'trigger 1 '((0)))
                     (gerbil-ascent-relation 'out 1 []))
               (list (gerbil-ascent-rule
                      (list (gerbil-ascent-atom 'out
                              (list (gerbil-ascent-literal 'hit))))
                      (list (gerbil-ascent-atom 'input
                              (list (gerbil-ascent-literal (list 1)))))))
               8 16 32))
             (session (gerbil-ascent-open-session program)))
        (check-set (rows (gerbil-ascent-session-run session) 'out) '((hit)))
        (set-car! cell 2)
        (let ((updated (gerbil-ascent-session-replace-sources!
                        session '((trigger (1)))))
              (fresh (gerbil-ascent-evaluate-program
                      (fresh-replacement-program program '((trigger (1)))))))
          (check-set (rows updated 'out) (rows fresh 'out))
          (check-equal? (.ref updated 'evaluation-path) 'stratified-semi-naive))))
    (test-case "mutable Core rule literal cannot authorize completed reuse"
      (let* ((program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'input 1 '((1)))
                     (gerbil-ascent-relation 'out 1 []))
               (list (gerbil-ascent-rule
                      (list (gerbil-ascent-atom 'out
                              (list (gerbil-ascent-literal (list 1)))))
                      (list (gerbil-ascent-atom 'input
                              (list (gerbil-ascent-literal 1))))))
               8 16 32)))
        (check-equal? (gerbil-ascent-update-eligible? program) #f)))
    (test-case "published rows cannot mutate retained scalar source"
      (let* ((x (gerbil-ascent-variable 'x))
             (program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'input 1 '((1)))
                     (gerbil-ascent-relation 'trigger 1 '((0)))
                     (gerbil-ascent-relation 'out 1 []))
               (list (gerbil-ascent-rule
                      (list (gerbil-ascent-atom 'out (list x)))
                      (list (gerbil-ascent-atom 'input (list x)))))
               8 16 32))
             (session (gerbil-ascent-open-session program))
             (initial (gerbil-ascent-session-run session)))
        (set-car! (car (rows initial 'input)) 2)
        (set-car! (car (rows initial 'out)) 3)
        (let (updated (gerbil-ascent-session-replace-sources!
                       session '((trigger (1)))))
          (check-set (rows updated 'input) '((1)))
          (check-set (rows updated 'out) '((1)))
          (check-equal? (.ref updated 'evaluation-path)
                        'stratified-dependency-invalidation))))
    (test-case "initial source snapshot owns caller row spines before first run"
      (let* ((row (list 1)) (x (gerbil-ascent-variable 'x))
             (program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'input 1 (list row))
                     (gerbil-ascent-relation 'trigger 1 '((0)))
                     (gerbil-ascent-relation 'out 1 []))
               (list (gerbil-ascent-rule
                      (list (gerbil-ascent-atom 'out (list x)))
                      (list (gerbil-ascent-atom 'input (list x)))))
               8 16 32))
             (session (gerbil-ascent-open-session program)))
        (set-car! row 2)
        (let (initial (gerbil-ascent-session-run session))
          (check-set (rows initial 'input) '((1)))
          (check-set (rows initial 'out) '((1))))
        (set-car! row 3)
        (let (updated (gerbil-ascent-session-replace-sources! session '((trigger (1)))))
          (check-set (rows updated 'input) '((1)))
          (check-set (rows updated 'out) '((1)))
          (check-equal? (.ref updated 'evaluation-path)
                        'stratified-dependency-invalidation))))
    (test-case "deletion skips an independent component and restores all rules for later append"
      (let* ((session (gerbil-ascent-open-session (path-program '((0 1) (1 2)))))
             (old (gerbil-ascent-session-run session))
             (updated (gerbil-ascent-session-replace-sources! session '((edge (0 1))))))
        (check-fresh updated (path-program '((0 1))))
        (check-equal? (.ref updated 'evaluation-path) 'stratified-dependency-invalidation)
        (check-equal? (.ref old 'active-rule-count) 3)
        (check-equal? (.ref updated 'active-rule-count) 2)
        (check-equal? (and (memq 'seen (.ref updated 'reused-relations)) #t) #t)
        (check-set (rows old 'path) '((0 1) (1 2) (0 2)))
        (gerbil-ascent-session-append-source! session 'cold '(8))
        (check-fresh (gerbil-ascent-session-run session) (path-program '((0 1)) '((7) (8))))
        (check-equal? (.ref updated 'active-rule-count) 2)
        (check-equal? (.ref updated 'evaluation-path) 'stratified-dependency-invalidation)))
    (test-case "removing all base support eliminates a recursive cycle"
      (let* ((program (relational-program
                      (relation edge (from to) '((0 1) (1 0))) (relation path (from to) '())
                      (rule (path ?x ?y) (edge ?x ?y))
                      (rule (path ?x ?y) (path ?x ?y))
                      (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
                      (limits 32 256 512)))
             (session (gerbil-ascent-open-session program)))
        (gerbil-ascent-session-run session)
        (gerbil-ascent-session-replace-source! session 'edge '((0 1)))
        (check-set (rows (gerbil-ascent-session-run session) 'path) '((0 1)))
        (gerbil-ascent-session-replace-source! session 'edge '())
        (check-set (rows (gerbil-ascent-session-run session) 'path) '())))
    (test-case "negation and aggregate dependencies invalidate lower-stratum changes"
      (let (session (gerbil-ascent-open-session (stratified-program '() '((1 2) (2 4)))))
        (let (initial (gerbil-ascent-session-run session))
          (check-equal? (.ref initial 'finished) #t))
        (let (result (gerbil-ascent-session-replace-sources! session '((blocked (2)))))
          (check-fresh result (stratified-program '((2)) '((1 2) (2 4))))
          ;; This checks the actual reuse path, not just coincidentally equal
          ;; rows from a full fresh evaluation. The recursive path is framed;
          ;; the negative read and downstream aggregate must be recomputed.
          (check-equal? (.ref result 'evaluation-path) 'stratified-dependency-invalidation)
          (check-equal? (.ref result 'active-rule-count) 3)
          (check-equal? (and (memq 'path (.ref result 'reused-relations)) #t) #t)
          (check-equal? (and (memq 'allowed (.ref result 'reused-relations)) #t) #f)
          (check-equal? (and (memq 'summary (.ref result 'reused-relations)) #t) #f)
          (check-set (rows result 'summary) '((0 4))))
        (let (result (gerbil-ascent-session-replace-sources! session '((blocked) (weight (1 6) (2 4)))))
          (check-fresh result (stratified-program '() '((1 6) (2 4))))
          (check-equal? (.ref result 'evaluation-path) 'stratified-dependency-invalidation)
          (check-equal? (.ref result 'active-rule-count) 3)
          (check-equal? (and (memq 'path (.ref result 'reused-relations)) #t) #t)
          (check-equal? (and (memq 'summary (.ref result 'reused-relations)) #t) #f)
          (check-set (rows result 'summary) '((0 20))))))
    (test-case "stratified source cuts agree with independent negative and aggregate oracle"
      ;; Source values and expected rows are computed from finite matrices and
      ;; scalar arithmetic, without asking the rule compiler for dependencies.
      (let ((base-edges '((0 1) (1 2)))
            (base-weights '((1 2) (2 4)))
            (names '(edge blocked weight root path allowed weighted summary)))
        (for-each
         (lambda (edges)
           (for-each
            (lambda (blocked-mask)
              (let (blocked
                    (filter-map (lambda (node)
                                  (and (odd? (quotient blocked-mask (expt 2 (- node 1))))
                                       (list node))) '(1 2)))
                (for-each
                 (lambda (weights)
                   (let* ((path (matrix-closure edges))
                          (allowed (filter (lambda (pair)
                                             (not (member (list (cadr pair)) blocked))) path))
                          (weighted
                           (filter-map
                            (lambda (pair)
                              (let (weight (assv (cadr pair) weights))
                                (and weight (even? (cadr weight))
                                     (list (car pair) (* 2 (cadr weight))))))
                            allowed))
                          (summary
                           (list (list 0
                                       (foldl + 0
                                              (map cadr
                                                   (filter (lambda (row) (= (car row) 0))
                                                           weighted))))))
                          (changed-edge? (not (equal? edges base-edges)))
                          (changed-blocked? (pair? blocked))
                          (changed-weight? (not (equal? weights base-weights)))
                          (affected
                           (append (if changed-edge? '(edge path) [])
                                   (if changed-blocked? '(blocked) [])
                                   (if changed-weight? '(weight) [])
                                   (if (or changed-edge? changed-blocked?) '(allowed) [])
                                   (if (or changed-edge? changed-blocked? changed-weight?)
                                     '(weighted summary) [])))
                          (base (stratified-program [] base-weights))
                          (session (gerbil-ascent-open-session base)))
                     (gerbil-ascent-session-run session)
                     (let* ((replacements
                             (list (cons 'edge edges) (cons 'blocked blocked)
                                   (cons 'weight weights)))
                            (updated (gerbil-ascent-session-replace-sources!
                                      session replacements))
                            (fresh (gerbil-ascent-evaluate-program
                                    (stratified-program blocked weights edges))))
                       (for-each
                        (lambda (name)
                          (let (expected
                                (case name
                                  ((edge) edges) ((blocked) blocked)
                                  ((weight) weights) ((root) '((0)))
                                  ((path) path) ((allowed) allowed)
                                  ((weighted) weighted) ((summary) summary)))
                            (check-set (rows updated name) expected)
                            (check-set (rows updated name) (rows fresh name))
                            (check-equal?
                             (and (memq name (.ref updated 'reused-relations)) #t)
                             (not (memq name affected)))))
                        names)
                       (check-equal? (.ref updated 'evaluation-path)
                                     'stratified-dependency-invalidation)
                       (displayln "STRATIFIED-READ-CHECKED edge=" edges
                                  " blocked=" blocked-mask " weights=" weights)
                       (force-output))))
                 (list base-weights '((1 3) (2 4)) '((1 2)) []))))
            (iota 4)))
         (list base-edges '((0 2)) '((0 1) (0 2)) []))))
    (test-case "lattice replacement retracts an old maximum and preserves independent final rows"
      (let (session (gerbil-ascent-open-session (lattice-program '((1 2) (1 5)) '((7)))))
        (gerbil-ascent-session-run session)
        (let (result (gerbil-ascent-session-replace-sources! session '((input (1 2)))))
          (check-fresh result (lattice-program '((1 2)) '((7))))
          (check-set (rows result 'answer) '((1 2))))
        (let (result (gerbil-ascent-session-replace-sources! session '((cold (8)))))
          (check-fresh result (lattice-program '((1 2)) '((8))))
          (check-equal? (and (memq 'best (.ref result 'reused-relations)) #t) #t))
        (gerbil-ascent-session-append-source! session 'input '(1 9))
        (check-fresh (gerbil-ascent-session-run session) (lattice-program '((1 2) (1 9)) '((8))))))
    (test-case "failed prospective deletion transaction retains completed state"
      (let (session (gerbil-ascent-open-session (path-program '((0 1) (1 2)))))
        (let (old (gerbil-ascent-session-run session))
          (for-each
           (lambda (replace)
             (let (diagnostic
                   (with-catch
                    (lambda (failure) (call-with-output-string
                                      (lambda (port) (display-exception failure port))))
                    (lambda () (replace) #f)))
               (check-equal? (and (string? diagnostic)
                                 (string-contains diagnostic "invalid ASCENT replacement source row") #t) #t)))
           (list (lambda () (gerbil-ascent-session-replace-source! session 'edge '((0 1 2))))
                 (lambda () (gerbil-ascent-session-replace-sources! session '((edge (0 1 2)))))))
          (check-exception (gerbil-ascent-session-replace-sources! session '((edge (0)))) true)
          (check-equal? (eq? old (gerbil-ascent-session-run session)) #t)
          (check-exception (gerbil-ascent-session-replace-sources! session '((unknown))) true)
          (gerbil-ascent-session-replace-source! session 'edge '((0 1)))
          (check-fresh (gerbil-ascent-session-run session) (path-program '((0 1)))))))
    (test-case "batch replacement owns caller row spines"
      (let* ((session (gerbil-ascent-open-session (path-program '((0 1) (1 2)))))
             (replacement-row (list 0 1))
             (replacement-rows (list replacement-row)))
        (gerbil-ascent-session-run session)
        (let (updated
              (gerbil-ascent-session-replace-sources!
               session (list (cons 'edge replacement-rows))))
          (set-car! replacement-row 7)
          (set-car! replacement-rows '(9 10))
          (check-set (rows updated 'edge) '((0 1)))
          (check-fresh
           (gerbil-ascent-session-replace-sources! session '((cold (8))))
           (path-program '((0 1)) '((8))))
          (let* ((provisional-row (list 1 2))
                 (provisional-rows (list provisional-row)))
            (gerbil-ascent-session-replace-source!
             session 'edge provisional-rows)
            (set-car! provisional-row 9)
            (check-fresh (gerbil-ascent-session-run session)
                         (path-program '((1 2)) '((8))))))))
    (test-case "source append owns caller row spine"
      (let* ((session (gerbil-ascent-open-session (path-program '((0 1)))))
             (added (list 1 2)))
        (gerbil-ascent-session-run session)
        (gerbil-ascent-session-append-source! session 'edge added)
        (set-car! added 9)
        (check-fresh (gerbil-ascent-session-run session)
                     (path-program '((0 1) (1 2))))))
    (test-case "opaque index lookup cannot authorize completed-result reuse"
      ;; A custom Provider may capture state outside the declared rule graph.
      ;; With 32 candidate rows, the bound second atom must use its index.
      ;; Change admissible enumeration order and observe the captured mode.
      ;; The physical index must still return every matching row. An incomplete
      ;; batch is a separate rejected transaction, not an alternate meaning.
      (let* ((reverse-lookups? #f)
             (observed-reverse? #f)
             (omit-matches? #f)
             (lookups 0)
             (provider
              (.o (:: @ gerbil-ascent-hash-index-provider)
                  (.lookup-index (lambda (index key)
                                   (set! lookups (+ lookups 1))
                                   (set! observed-reverse? reverse-lookups?)
                                   (let (matching (or (hash-get index key) []))
                                     (if omit-matches? []
                                       (if reverse-lookups? (reverse matching) matching)))))))
             (right-rows (map (lambda (n) (list (modulo n 4) n)) (iota 32)))
             (expected-joined (filter (lambda (row) (= (car row) 0)) right-rows))
             (base
              (relational-program
               (relation left (key) '((0)))
               (relation right (key value) right-rows)
               (relation joined (key value) '())
               (relation cold (value) '((7)))
               (relation seen (value) '())
               (rule (joined ?k ?v) (left ?k) (right ?k ?v))
               (rule (seen ?v) (cold ?v))
               (limits 128 128 256)))
             (source-relations (.ref base 'relations))
             (custom-right (.o (:: @ (cadr source-relations)) index-provider: provider))
             (program (.o (:: @ base)
                          relations: (cons (car source-relations)
                                           (cons custom-right (cddr source-relations)))))
             (session (gerbil-ascent-open-session program)))
        (check-equal? (gerbil-ascent-update-eligible? program) #f)
        (check-set (rows (gerbil-ascent-session-run session) 'joined) expected-joined)
        (check-equal? (> lookups 0) #t)
        (check-equal? observed-reverse? #f)
        (let (before-update-lookups lookups)
          (set! reverse-lookups? #t)
          (let* ((replacements '((cold (8))))
                 (updated (gerbil-ascent-session-replace-sources! session replacements)))
            (check-equal? (> lookups before-update-lookups) #t)
            (check-equal? (.ref updated 'evaluation-path) 'stratified-semi-naive)
            (check-equal? (.ref updated 'reused-relations) '())
            (check-equal? observed-reverse? #t)
            (check-set (rows updated 'joined) expected-joined)
            (check-fresh updated (fresh-replacement-program program replacements))
            ;; A genuinely incomplete lookup must fail atomically. Restoring
            ;; the receiver leaves the accepted cold(8) source, never cold(9).
            (set! omit-matches? #t)
            (check-exception
             (gerbil-ascent-session-replace-sources! session '((cold (9)))) true)
            (set! omit-matches? #f)
            (let (recovered (gerbil-ascent-session-run session))
              (check-set (rows recovered 'joined) expected-joined)
              (check-set (rows recovered 'seen) '((8)))
              (check-fresh recovered (fresh-replacement-program program replacements)))))))
    (test-case "a forged descriptor cannot authorize an opaque callback for result reuse"
      (let* ((allow? #t)
             (base (path-program '((0 1))))
             (rules (.ref base 'rules))
             (guard (gerbil-ascent-guard '() (lambda () allow?) (vector 'where 'even? '())))
             (first (.o (:: @ (car rules)) body: (append (.ref (car rules) 'body) (list guard))))
             (program (gerbil-ascent-program (.ref base 'relations) (cons first (cdr rules)) 32 256 512))
             (session (gerbil-ascent-open-session program)))
        (check-equal? (gerbil-ascent-update-eligible? program) #f)
        (gerbil-ascent-session-run session)
        (set! allow? #f)
        (let (result (gerbil-ascent-session-replace-sources! session '((cold (8)))))
          (check-equal? (.ref result 'reused-relations) '())
          (check-set (rows result 'path) '()))))
    (test-case "all 64 three-node graphs and 192 successive withdrawals agree with fresh closure"
      (for-each (lambda (mask)
        (let* ((edges (edges-for-mask mask))
               (session (gerbil-ascent-open-session (path-program edges))))
          (let (result (gerbil-ascent-session-run session))
            (check-set (rows result 'path) (matrix-closure edges))
            (displayln "DELETE-CHECKED initial " mask) (force-output))
          (let withdraw ((remaining edges) (position 1))
            (unless (null? remaining)
              (let* ((next (cdr remaining))
                     (result (gerbil-ascent-session-replace-sources! session (list (cons 'edge next)))))
                (check-fresh result (path-program next))
                (check-set (rows result 'path) (matrix-closure next))
                (displayln "DELETE-CHECKED withdrawal " mask " " position) (force-output)
                (withdraw next (+ position 1))))))) (iota 64)))))
