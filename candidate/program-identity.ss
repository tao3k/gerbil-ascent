;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Certificate program identity is an ordered wire projection, not a semantic
;;; normalization. Preserve the historical finite and positive encodings;
;;; neither sorting nor expanding whole vectors is valid at this boundary.
(import (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode)
        (only-in :gerbil-ascent/candidate/types
                 reasoning-candidate-relations reasoning-candidate-facts
                 reasoning-candidate-rules reasoning-candidate-query
                 reasoning-candidate-limits))

(export candidate-finite-program-fingerprint
        candidate-positive-program-fingerprint)

;; : (-> CandidateEntry IdentityEntry)
(def (entry-datum entry)
  (list (vector-ref entry 0) (vector-ref entry 1) (vector-ref entry 2)))

;; : (-> InspectedCandidate ProgramIdentityDatum)
(def (program-shape spec)
  (list (reasoning-candidate-relations spec)
        (map entry-datum (reasoning-candidate-facts spec))
        (map entry-datum (reasoning-candidate-rules spec))
        (vector-ref (reasoning-candidate-query spec) 0)
        (reasoning-candidate-limits spec)))

;; : (-> ProgramIdentityDatum Digest)
(def (datum-fingerprint datum)
  (hex-encode
   (sha256
    (string->utf8
     (call-with-output-string ""
       (lambda (port) (write datum port)))))))

;; candidate-finite-program-fingerprint
;;   : (-> InspectedCandidate Digest)
;;   | doc m%
;;       Bind the finite certificate to its original untagged program encoding.
;;       Relation, fact and rule order, labels, query terms and limits retain
;;       their wire meaning. The query's source label is not projected.
;;
;;       # Examples
;;
;;       ```scheme
;;       (candidate-finite-program-fingerprint inspected-program)
;;       ;; => the SHA-256 digest of its untagged identity datum
;;       ```
;;     %
(def (candidate-finite-program-fingerprint spec)
  (datum-fingerprint (program-shape spec)))

;; candidate-positive-program-fingerprint
;;   : (-> InspectedCandidate Digest)
;;   | doc m%
;;       Bind positive nonmembership to the positive-program-v1 tagged encoding.
;;       This preserves its distinct certificate protocol and existing digests.
;;
;;       # Examples
;;
;;       ```scheme
;;       (candidate-positive-program-fingerprint inspected-program)
;;       ;; => the SHA-256 digest of its positive-program-v1 identity datum
;;       ```
;;     %
(def (candidate-positive-program-fingerprint spec)
  (datum-fingerprint (cons 'positive-program-v1 (program-shape spec))))
