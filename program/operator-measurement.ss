;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Optional dynamic measurements for the public reference/change interpreters.
;;; Compiler lowering and native rule execution never increment these counters.
(export relational-op-measure relational-op-measurement? relational-op-measurement-result-values
        relational-op-measurement-join-probes relational-op-measurement-fix-body-evaluations
        relational-op-count-join! relational-op-count-fix!)
(defstruct relational-op-measurement
  (result-values join-probes fix-body-evaluations))

(def current-relational-op-meter (make-parameter #f))

;;; A measured run keeps counters local to its dynamic extent. Join probes
;;; count candidate row pairs before equality; fix counts body evaluations.
;;; These counts are not a cost model for index lookups or native rule plans.
;; : (forall (result ...) (-> (-> (values result ...)) RelationalOpMeasurement))
;; : (-> Thunk RelationalOpMeasurement)
(def (relational-op-measure thunk)
  (unless (procedure? thunk)
    (error "operator measurement requires a thunk" thunk))
  (let (meter (vector 0 0))
    (parameterize ((current-relational-op-meter meter))
      (call-with-values
       thunk
       (lambda results
         (make-relational-op-measurement
          results (vector-ref meter 0) (vector-ref meter 1)))))))

(def (relational-op-count-join!)
  (let (meter (current-relational-op-meter))
    (when meter (vector-set! meter 0 (+ 1 (vector-ref meter 0))))))

(def (relational-op-count-fix!)
  (let (meter (current-relational-op-meter))
    (when meter (vector-set! meter 1 (+ 1 (vector-ref meter 1))))))
