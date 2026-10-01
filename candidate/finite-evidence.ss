;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Exact finite replay for the inspected candidate subset. This is a
;;; snapshot-relative model check, not general recursive provenance.
;;; The replay does not call the ASCENT planner, evaluator or solver.
(import (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode)
        (only-in :gerbil-ascent/candidate/types
                 reasoning-snapshot-identity reasoning-snapshot-generation
                 reasoning-snapshot-digest reasoning-snapshot-relations
                 reasoning-snapshot-valid?
                 reasoning-candidate-relations reasoning-candidate-facts
                 reasoning-candidate-rules reasoning-candidate-query
                 reasoning-candidate-limits)
        (only-in :gerbil-ascent/candidate/program candidate-variable? scalar?))

(export candidate-finite-evidence candidate-verify-finite-evidence
        finite-evidence? finite-evidence-status finite-evidence-closure
        finite-evidence-query finite-evidence-candidate-digest)

(defstruct finite-evidence
  (status snapshot-identity snapshot-generation snapshot-digest
          candidate-digest program query work-budget closure))

(def +max-certificate-relations+ 64)
(def +max-certificate-rows+ 4096)
(def +max-certificate-cells+ 32768)
(def +max-certificate-row-arity+ 1024)

;; : (forall (a) (-> (List a) Nat (Maybe Nat)))
;; : (-> Datum Nat (Maybe Nat))
(def (bounded-list-length items maximum)
  (do ((rest items (cdr rest))
       (count 0 (+ count 1)))
      ((or (null? rest) (not (pair? rest)) (>= count maximum))
       (and (null? rest) count))))

;; : (forall (a) (-> (PairTree a) (PairTree a)))
;; : (-> Datum Datum)
(def (copy-pairs datum)
  (if (pair? datum)
    (cons (copy-pairs (car datum)) (copy-pairs (cdr datum)))
    datum))

;; : (forall (row) (-> (List row) (List row) Boolean))
;; : (-> Rows Rows Boolean)
(def (same-row-set? left right)
  (and (= (length left) (length right))
       (andmap (lambda (row) (and (member row right) #t)) left)
       (andmap (lambda (row) (and (member row left) #t)) right)))

;; : (forall (row) (-> (List row) Boolean))
;; : (-> Rows Boolean)
(def (unique-rows? rows)
  (let (seen (make-hash-table))
    (andmap
     (lambda (row)
       (if (hash-get seen row)
         #f
         (begin (hash-put! seen row #t) #t)))
     rows)))

;; : (forall (row) (-> (Closure row) Schema Boolean))
;; : (-> CertificateClosure Schema Boolean)
(def (closure-valid? closure schema)
  (and (equal? (bounded-list-length closure
                                    +max-certificate-relations+)
               (length schema))
       (let ((rows 0) (cells 0))
         (andmap
          (lambda (entry declaration)
            (and (equal? (bounded-list-length entry 3) 3)
                 (eq? (car entry) (car declaration))
                 (exact-integer? (cadr entry))
                 (= (cadr entry) (cdr declaration))
                 (let (count
                       (bounded-list-length
                        (caddr entry) (- +max-certificate-rows+ rows)))
                   (and count
                        (begin (set! rows (+ rows count)) #t)))
                 (<= rows +max-certificate-rows+)
                 (unique-rows? (caddr entry))
                 (andmap
                  (lambda (row)
                    (let (width
                          (bounded-list-length
                           row (min +max-certificate-row-arity+
                                    (- +max-certificate-cells+ cells))))
                      (and width (= width (cadr entry))
                           (begin (set! cells (+ cells width))
                                  #t)
                           (andmap scalar? row))))
                  (caddr entry))))
          closure schema))))

;; : (-> InspectedCandidate Datum)
(def (program-shape spec)
  (list
   (reasoning-candidate-relations spec)
   (map (lambda (fact)
          (list (vector-ref fact 0) (vector-ref fact 1)
                (vector-ref fact 2)))
        (reasoning-candidate-facts spec))
   (map (lambda (rule)
          (list (vector-ref rule 0) (vector-ref rule 1)
                (vector-ref rule 2)))
        (reasoning-candidate-rules spec))
   (vector-ref (reasoning-candidate-query spec) 0)
   (reasoning-candidate-limits spec)))

;; : (-> InspectedCandidate Digest)
(def (program-fingerprint spec)
  (hex-encode
   (sha256
    (string->utf8
     (call-with-output-string ""
       (lambda (port) (write (program-shape spec) port)))))))

;; : (-> ReasoningSnapshot InspectedCandidate Schema)
(def (schema-of snapshot spec)
  (append
   (map (lambda (entry) (cons (car entry) (cadr entry)))
        (reasoning-snapshot-relations snapshot))
   (reasoning-candidate-relations spec)))

;;; Both strata and relation tables are keyed by their admitted relation
;;; names. A missing entry is an invalid inspected-program invariant.
;; : (forall (v) (-> Symbol (List (Pair Symbol v)) (Pair Symbol v)))
;; : (-> Symbol RelationIndex Entry)
(def (required-entry name index)
  (or (assq name index)
      (error "finite evidence is missing admitted relation" name)))

;; : (forall (v) (-> (Atom v) (Row v) (Bindings v) (Maybe (Bindings v))))
;; : (-> Atom Row Bindings (Maybe Bindings))
(def (bind-atom atom row prior)
  (let loop ((terms (cdr atom)) (values row) (bindings prior))
    (if (null? terms)
      bindings
      (let ((term (car terms)) (value (car values)))
        (cond
         ((eq? term '?_) (loop (cdr terms) (cdr values) bindings))
         ((candidate-variable? term)
          (let (old (assq term bindings))
            (if old
              (and (equal? (cdr old) value)
                   (loop (cdr terms) (cdr values) bindings))
              (loop (cdr terms) (cdr values)
                    (cons (cons term value) bindings)))))
         (else
          (and (equal? term value)
               (loop (cdr terms) (cdr values) bindings))))))))

;; : (forall (v) (-> (List v) (Bindings v) (Row v)))
;; : (-> Terms Bindings Row)
(def (instantiate terms bindings)
  (map (lambda (term)
         (if (candidate-variable? term)
           (cdr (required-entry term bindings))
           term))
       terms))

;; : (-> FixedClause Bindings (Maybe Bindings))
(def (fixed-clause clause bindings)
  (let* ((mode (car clause))
         (form (if (eq? mode 'where) (cadr clause) (caddr clause)))
         (inputs (map (lambda (name) (assq name bindings)) (cdr form))))
    (and (andmap (lambda (input) (and input #t)) inputs)
         (let (values (map cdr inputs))
           (case mode
             ((where)
              (case (car form)
                ((even?) (and (exact-integer? (car values))
                              (even? (car values)) bindings))
                ((<) (and (andmap exact-integer? values)
                          (< (car values) (cadr values)) bindings))
                (else #f)))
             ((compute)
              (and (not (assq (cadr clause) bindings))
                   (case (car form)
                     ((identity)
                      (cons (cons (cadr clause) (car values)) bindings))
                     ((+)
                      (and (andmap exact-integer? values)
                           (cons (cons (cadr clause)
                                       (+ (car values) (cadr values)))
                                 bindings)))
                     (else #f))))
             (else #f))))))

;;; A strict dependency adds one stratum; positive reads may stay in the
;;; current stratum. Relaxation beyond the number of relations rejects a
;;; negative or aggregate cycle independently of the native planner.
;; : (-> Schema Rules (Maybe Strata))
(def (strata-of schema rules)
  (let ((levels (map (lambda (entry) (cons (car entry) 0)) schema))
        (changed? #f))
    (let loop ((round 0))
      (set! changed? #f)
      (for-each
       (lambda (rule)
         (let ((head (car (vector-ref rule 0)))
               (body (vector-ref rule 1)))
           (for-each
            (lambda (clause)
              (let (dependency
                    (case (car clause)
                      ((not) (cons (caadr clause) 1))
                      ((reduce) (cons (car (cadddr clause)) 1))
                      ((where compute) #f)
                      (else (cons (car clause) 0))))
                (when dependency
                  (let ((head-level (required-entry head levels))
                        (dep-level
                         (required-entry (car dependency) levels)))
                    (let (required (+ (cdr dep-level) (cdr dependency)))
                      (when (< (cdr head-level) required)
                        (set-cdr! head-level required)
                        (set! changed? #t)))))))
            body)))
       rules)
      (cond
       ((not changed?) levels)
       ((>= round (length schema)) #f)
       (else (loop (+ round 1)))))))

;;; Returns exact relation sets or bounded/unsupported. The input is an
;;; already inspected candidate. Work counts every relation-row probe and
;;; fixed operation, including probes that do not produce a row.
;; : (-> ReasoningSnapshot InspectedCandidate Nat (Values Status Closure))
(def (finite-replay snapshot spec work-budget)
  (let* ((schema (schema-of snapshot spec))
         (rules (reasoning-candidate-rules spec))
         (levels (strata-of schema rules))
         (tables
          (map (lambda (entry) (list (car entry) (cdr entry) [])) schema))
         (steps 0)
         (bounded? #f)
         (derived-count 0)
         (derived-limit (cadr (reasoning-candidate-limits spec))))
        (def (rows name)
          (caddr (required-entry name tables)))
        (def (add-row! name row derived?)
          (let (entry (required-entry name tables))
            (if (member row (caddr entry))
              #f
              (begin
                (when derived?
                  (set! derived-count (+ derived-count 1))
                  (when (> derived-count derived-limit)
                    (set! bounded? #t)))
                (if bounded?
                  #f
                  (begin
                    (set-car! (cddr entry)
                              (append (caddr entry) (list (copy-pairs row))))
                    #t))))))
        (def (step!)
          (set! steps (+ steps 1))
          (when (> steps work-budget) (set! bounded? #t))
          (not bounded?))
        (def (evaluate-rule rule)
          (let ((head (vector-ref rule 0))
                (body (vector-ref rule 1))
                (changed? #f))
            (def (walk clauses bindings)
              (unless bounded?
                (if (null? clauses)
                  (when (add-row! (car head)
                                  (instantiate (cdr head) bindings) #t)
                    (set! changed? #t))
                  (let (clause (car clauses))
                    (case (car clause)
                      ((where compute)
                       (when (step!)
                         (let (next (fixed-clause clause bindings))
                           (when next (walk (cdr clauses) next)))))
                      ((not)
                       (let* ((atom (cadr clause))
                              (matched? #f))
                         (for-each
                          (lambda (row)
                            (when (step!)
                              (when (bind-atom atom row bindings)
                                (set! matched? #t))))
                          (rows (car atom)))
                         (when (and (not bounded?) (not matched?)
                                    (step!))
                           (walk (cdr clauses) bindings))))
                      ((reduce)
                       (let* ((output (cadr clause))
                              (operator (caddr clause))
                              (atom (cadddr clause))
                              (matches []))
                         (for-each
                          (lambda (row)
                            (when (step!)
                              (let (next (bind-atom atom row bindings))
                                (when next
                                  (set! matches
                                    (cons (if (eq? (car operator) 'count)
                                            #t
                                            (cdr (required-entry
                                                  (cadr operator) next)))
                                          matches))))))
                          (rows (car atom)))
                         (unless bounded?
                           (let (value
                                 (case (car operator)
                                   ((count) (length matches))
                                   ((sum) (and (andmap exact-integer? matches)
                                               (apply + 0 matches)))
                                   ((min) (and (pair? matches)
                                               (andmap exact-integer? matches)
                                               (apply min matches)))
                                   ((max) (and (pair? matches)
                                               (andmap exact-integer? matches)
                                               (apply max matches)))
                                   (else #f)))
                             (when value
                               (walk (cdr clauses)
                                     (cons (cons output value) bindings)))))))
                      (else
                       (for-each
                        (lambda (row)
                          (when (step!)
                            (let (next (bind-atom clause row bindings))
                              (when next (walk (cdr clauses) next)))))
                        (rows (car clause)))))))))
            (walk body [])
            changed?))
    (if (not levels)
      (values 'unsupported [])
      (begin
        (for-each
         (lambda (entry)
           (for-each (lambda (row) (add-row! (car entry) row #f))
                     (caddr entry)))
         (reasoning-snapshot-relations snapshot))
        (for-each
         (lambda (fact)
           (add-row! (vector-ref fact 0) (vector-ref fact 1) #f))
         (reasoning-candidate-facts spec))
        (let stratum ((level 0)
                      (maximum (apply max (map cdr levels))))
          (when (and (<= level maximum) (not bounded?))
            (let repeat ()
              (let (changed? #f)
                (for-each
                 (lambda (rule)
                   (when (and (not bounded?)
                              (= (cdr (required-entry
                                       (car (vector-ref rule 0)) levels))
                                 level))
                     (when (evaluate-rule rule)
                       (set! changed? #t))))
                 rules)
                (when (and changed? (not bounded?)) (repeat))))
            (stratum (+ level 1) maximum)))
        (values (if bounded? 'bounded 'complete)
                (if bounded? [] tables))))))

;; : (-> InspectedCandidate Closure Rows)
(def (query-rows spec closure)
  (let* ((query (vector-ref (reasoning-candidate-query spec) 0))
         (entry (required-entry (car query) closure)))
    (filter (lambda (row) (and (bind-atom query row []) #t))
            (caddr entry))))

;;; The generator compares independent replay with a completed native
;;; answer. Mismatch is explicit; it is never reported as a certificate.
;; : (-> ReasoningSnapshot InspectedCandidate Digest Status Rows Nat FiniteEvidence)
(def (candidate-finite-evidence snapshot spec candidate-digest
                                native-status native-rows work-budget)
  (unless (and (exact-integer? work-budget) (> work-budget 0))
    (error "finite evidence requires positive work budget" work-budget))
  (def (result status closure)
    (make-finite-evidence
     status (reasoning-snapshot-identity snapshot)
     (reasoning-snapshot-generation snapshot)
     (reasoning-snapshot-digest snapshot) candidate-digest
     (program-fingerprint spec)
     (copy-pairs (vector-ref (reasoning-candidate-query spec) 0))
     work-budget (copy-pairs closure)))
  (if (or (not (reasoning-snapshot-valid? snapshot))
          (not (eq? native-status 'complete)))
    (result 'unsupported [])
    (let-values (((status closure)
                  (finite-replay snapshot spec work-budget)))
      (case status
        ((complete)
         (cond
          ((not (closure-valid? closure (schema-of snapshot spec)))
           (result 'bounded []))
          ((same-row-set? (query-rows spec closure) native-rows)
           (result 'complete closure))
          (else (result 'mismatch []))))
        ((bounded) (result 'bounded []))
        (else (result 'unsupported []))))))

;;; Recompute from the snapshot and inspected program. A supplied closure
;;; cannot authenticate the snapshot or claim more than this finite model.
;; : (-> ReasoningSnapshot InspectedCandidate Digest Status Rows FiniteEvidence Nat Verdict)
(def (candidate-verify-finite-evidence snapshot spec candidate-digest
                                       native-status native-rows certificate
                                       work-budget)
  (unless (and (exact-integer? work-budget) (> work-budget 0))
    (error "finite evidence verification needs positive budget" work-budget))
  (if (not (and (finite-evidence? certificate)
                (reasoning-snapshot-valid? snapshot)
                (eq? native-status 'complete)
                (eq? (finite-evidence-status certificate) 'complete)
                (equal? (finite-evidence-snapshot-identity certificate)
                        (reasoning-snapshot-identity snapshot))
                (equal? (finite-evidence-snapshot-generation certificate)
                        (reasoning-snapshot-generation snapshot))
                (equal? (finite-evidence-snapshot-digest certificate)
                        (reasoning-snapshot-digest snapshot))
                (equal? (finite-evidence-candidate-digest certificate)
                        candidate-digest)
                (equal? (finite-evidence-program certificate)
                        (program-fingerprint spec))
                (equal? (finite-evidence-query certificate)
                        (vector-ref (reasoning-candidate-query spec) 0))
                (closure-valid? (finite-evidence-closure certificate)
                                (schema-of snapshot spec))))
    'invalid
    (let-values (((status closure)
                  (finite-replay snapshot spec work-budget)))
      (case status
        ((bounded) 'bounded)
        ((complete)
         (if (and
              (andmap (lambda (actual supplied)
                        (same-row-set? (caddr actual) (caddr supplied)))
                      closure (finite-evidence-closure certificate))
              (same-row-set? (query-rows spec closure) native-rows))
           'valid 'invalid))
        (else 'invalid)))))
