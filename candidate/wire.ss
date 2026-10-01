;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Versioned JSON boundary for one model-proposed reasoning attempt.
;;; The caller supplies the trusted source snapshot separately. JSON is
;;; decoded only as inert data; no Scheme reader or evaluator is involved.
(import (only-in :std/encoding/json
                 string->json json->string JSONReadOptions)
        (only-in :gerbil-ascent/candidate/types
                 reasoning-snapshot-valid? reasoning-snapshot-identity
                 reasoning-snapshot-generation reasoning-snapshot-digest
                 reasoning-snapshot-relations)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-attempt
                 reasoning-receipt-status reasoning-receipt-rows
                 reasoning-receipt-query reasoning-receipt-candidate-digest
                 reasoning-receipt-diagnostics reasoning-receipt-evidence
                 reasoning-receipt-proof reasoning-receipt-nonmembership
                 reasoning-diagnostic-code reasoning-diagnostic-path
                 reasoning-diagnostic-detail
                 reasoning-evidence-kind reasoning-evidence-support
                 reasoning-evidence-reachable)
        (only-in :gerbil-ascent/candidate/provenance
                 positive-proof-status positive-proof-nodes
                 positive-proof-roots)
        (only-in :gerbil-ascent/candidate/nonmembership
                 positive-nonmembership-status
                 positive-nonmembership-closure))

(export reasoning-wire-attempt)

(defstruct wire-rejection (code path detail))

(def +max-request-characters+ 32768)
(def +max-json-depth+ 64)
(def +max-symbol-characters+ 128)
(def +max-projection-characters+ 65536)
(def +max-projected-rows+ 256)

(def (wire-reject code path detail)
  (raise (make-wire-rejection code path detail)))

(def (json-open? character)
  (or (char=? character #\[) (char=? character #\{)))

(def (json-close? character)
  (or (char=? character #\]) (char=? character #\})))

(def (json-text-size-ok? text)
  (<= (string-length text) +max-request-characters+))

(def (json-scan-finished? depth quoted? escaped?)
  (and (zero? depth) (not quoted?) (not escaped?)))

;;; Bound nesting before the JSON parser traverses the input. The parser
;;; itself checks bracket pairing, escapes and duplicate object keys.
(def (bounded-json-text? text)
  (and (string? text)
       (json-text-size-ok? text)
       (let loop ((position 0) (depth 0) (quoted? #f) (escaped? #f))
         (if (= position (string-length text))
           (json-scan-finished? depth quoted? escaped?)
           (let (character (string-ref text position))
             (cond
              (escaped?
               (loop (+ position 1) depth quoted? #f))
              ((and quoted? (char=? character #\\))
               (loop (+ position 1) depth quoted? #t))
              ((char=? character #\")
               (loop (+ position 1) depth (not quoted?) #f))
              (quoted?
               (loop (+ position 1) depth #t #f))
              ((json-open? character)
               (and (< depth +max-json-depth+)
                    (loop (+ position 1) (+ depth 1) #f #f)))
              ((json-close? character)
               (and (> depth 0)
                    (loop (+ position 1) (- depth 1) #f #f)))
              (else
               (loop (+ position 1) depth #f #f))))))))

(def (wire-symbol text path)
  (unless (and (string? text)
               (> (string-length text) 0)
               (<= (string-length text) +max-symbol-characters+)
               (not (find (lambda (character)
                            (char<? character #\space))
                          (string->list text))))
    (wire-reject 'invalid-symbol path 'bounded-printable-name-required))
  (string->symbol text))

;;; JSON arrays become Scheme lists; strings become inert symbols. A
;;; one-character tagged object is the only object allowed inside a
;;; candidate, preserving the native character scalar without ambiguity.
(def (candidate-json->datum value path depth)
  (when (> depth +max-json-depth+)
    (wire-reject 'candidate-too-deep path +max-json-depth+))
  (cond
   ((string? value) (wire-symbol value path))
   ((or (exact-integer? value) (boolean? value)) value)
   ((list? value)
    (map (lambda (item index)
           (candidate-json->datum item (append path (list index))
                                  (+ depth 1)))
         value (iota (length value) 0)))
   ((hash-table? value)
    (if (and (= (length (hash-keys value)) 1)
             (hash-key? value "char")
             (string? (hash-get value "char"))
             (= (string-length (hash-get value "char")) 1))
      (string-ref (hash-get value "char") 0)
      (wire-reject 'invalid-value path 'expected-single-character-tag)))
   (else (wire-reject 'invalid-value path 'expected-scalar-or-array))))

(def (parse-wire-candidate payload)
  (unless (bounded-json-text? payload)
    (wire-reject 'invalid-json-bound '(request)
                 (list +max-request-characters+ +max-json-depth+)))
  (let (parsed
        (with-catch
         (lambda (_failure)
           (wire-reject 'malformed-json '(request) 'parse-failed))
         (lambda ()
           (string->json
            payload
            (JSONReadOptions key-as-symbol: #f
                             array-as-vector: #f
                             object-as-hash: #t)))))
    (unless (and (hash-table? parsed)
                 (= (length (hash-keys parsed)) 2)
                 (hash-key? parsed "version")
                 (hash-key? parsed "candidate")
                 (equal? (hash-get parsed "version") 1)
                 (list? (hash-get parsed "candidate")))
      (wire-reject 'invalid-envelope '(request)
                   'expected-version-one-and-candidate))
    (cons 'candidate
          (candidate-json->datum
           (hash-get parsed "candidate") '(candidate) 0))))

(def (datum->wire value (depth 0))
  (cond
   ((> depth +max-json-depth+) "<depth-limit>")
   ((symbol? value) (symbol->string value))
   ((char? value) (hash (char (string value))))
   ((or (exact-integer? value) (boolean? value) (string? value)) value)
   ((null? value) [])
   ((pair? value)
    (if (list? value)
      (map (lambda (item) (datum->wire item (+ depth 1))) value)
      "<non-list>"))
   (else "<unavailable>")))

(def (source-wire snapshot)
  (hash (identity (datum->wire (reasoning-snapshot-identity snapshot)))
        (generation (reasoning-snapshot-generation snapshot))
        (digest (reasoning-snapshot-digest snapshot))))

(def (source-schema-wire snapshot)
  (map (lambda (entry)
         (hash (relation (symbol->string (car entry)))
               (arity (cadr entry))))
       (reasoning-snapshot-relations snapshot)))

(def (attempt-key snapshot digest)
  (and digest
       (string-append (reasoning-snapshot-digest snapshot)
                      ":" digest)))

(def (diagnostic-wire code path detail)
  (hash (code (symbol->string code))
        (path (datum->wire path))
        (detail (datum->wire detail))))

(def (compact-receipt-wire snapshot receipt reason)
  (let (digest (reasoning-receipt-candidate-digest receipt))
    (json->string
     (hash
      (version 1)
      (status (symbol->string (reasoning-receipt-status receipt)))
      (source (source-wire snapshot))
      (candidateDigest (or digest #!void))
      (attemptId (or (attempt-key snapshot digest) #!void))
      (rowCount (length (reasoning-receipt-rows receipt)))
      (rowsComplete #f)
      (rows [])
      (projectionStatus reason)
      (diagnosticCount (length (reasoning-receipt-diagnostics receipt)))
      (evidenceStatus "omitted"))
     sort-keys: #t)))

;;; A compact projection never carries evidence or rows. This prevents a
;;; model caller from mistaking an output-budget omission for a negative
;;; answer or a checked explanation.
(def (receipt-wire/small snapshot receipt)
  (let* ((rows (reasoning-receipt-rows receipt))
         (proof (reasoning-receipt-proof receipt))
         (absence (reasoning-receipt-nonmembership receipt))
         (evidence (reasoning-receipt-evidence receipt))
         (full
          (hash
           (version 1)
           (status (symbol->string (reasoning-receipt-status receipt)))
           (source (source-wire snapshot))
           (sourceSchema (source-schema-wire snapshot))
           (candidateDigest
            (or (reasoning-receipt-candidate-digest receipt) #!void))
           (attemptId
            (or (attempt-key
                 snapshot (reasoning-receipt-candidate-digest receipt))
                #!void))
           (query (datum->wire (reasoning-receipt-query receipt)))
           (rowCount (length rows))
           (rowsComplete (eq? (reasoning-receipt-status receipt) 'complete))
           (rows (if (<= (length rows) +max-projected-rows+)
                   (datum->wire rows) []))
           (diagnostics
            (map (lambda (diagnostic)
                   (diagnostic-wire
                    (reasoning-diagnostic-code diagnostic)
                    (reasoning-diagnostic-path diagnostic)
                    (reasoning-diagnostic-detail diagnostic)))
                 (reasoning-receipt-diagnostics receipt)))
           (evidence
            (if evidence
              (hash (kind (symbol->string (reasoning-evidence-kind evidence)))
                    (support (datum->wire
                              (reasoning-evidence-support evidence)))
                    (reachable (datum->wire
                                (reasoning-evidence-reachable evidence))))
              (hash (kind "unavailable"))))
           (proof
            (if proof
              (hash (status (symbol->string (positive-proof-status proof)))
                    (nodeCount (length (positive-proof-nodes proof)))
                    (rootCount (length (positive-proof-roots proof))))
              (hash (status "unavailable"))))
           (nonmembership
            (if absence
              (hash
               (status
                (symbol->string (positive-nonmembership-status absence)))
               (relationCount
                (length (positive-nonmembership-closure absence))))
              (hash (status "unavailable")))))))
    (let (encoded (json->string full sort-keys: #t))
      (if (<= (string-length encoded) +max-projection-characters+)
        encoded
        (compact-receipt-wire snapshot receipt "size-limit")))))

(def (receipt-wire snapshot receipt)
  (if (> (length (reasoning-receipt-rows receipt))
         +max-projected-rows+)
    (compact-receipt-wire snapshot receipt "row-limit")
    (receipt-wire/small snapshot receipt)))

(def (rejection-wire snapshot rejection)
  (json->string
   (hash (version 1)
         (status "rejected")
         (source (source-wire snapshot))
         (sourceSchema (source-schema-wire snapshot))
         (candidateDigest #!void)
         (attemptId #!void)
         (rowCount 0)
         (rowsComplete #f)
         (rows [])
         (diagnostics
          (list (diagnostic-wire
                 (wire-rejection-code rejection)
                 (wire-rejection-path rejection)
                 (wire-rejection-detail rejection)))))
   sort-keys: #t))

;; reasoning-wire-attempt
;;   : (-> ReasoningSnapshot String [Nat] String)
;;   | doc m%
;;       Decode one bounded version-one JSON candidate against a separately
;;       supplied source snapshot. Return a versioned JSON receipt with
;;       explicit status, binding, rows and evidence statuses. Oversize row
;;       projection is marked incomplete even if the underlying solve ended.
;;     %
;;; The trusted caller owns the snapshot and proof budget. A malformed model
;;; message is returned as a located rejection, never as a source mutation;
;;; only the existing candidate inspector can admit rules for execution.
(def (reasoning-wire-attempt snapshot payload (proof-steps 100000))
  (unless (reasoning-snapshot-valid? snapshot)
    (error "wire attempt requires a valid caller-owned snapshot"))
  (unless (and (exact-integer? proof-steps) (> proof-steps 0))
    (error "wire attempt requires a positive proof work budget"))
  (when (> (string-length
            (if (symbol? (reasoning-snapshot-identity snapshot))
              (symbol->string (reasoning-snapshot-identity snapshot))
              (reasoning-snapshot-identity snapshot)))
           256)
    (error "wire snapshot identity exceeds projection bound"))
  (with-catch
   (lambda (failure)
     (if (wire-rejection? failure)
       (rejection-wire snapshot failure)
       (raise failure)))
   (lambda ()
     (receipt-wire
      snapshot
      (reasoning-attempt snapshot
                         (parse-wire-candidate payload)
                         proof-steps)))))
