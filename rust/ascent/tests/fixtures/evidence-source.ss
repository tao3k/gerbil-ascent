
  (defrules copy-rule ()
    ((_ from to)
     (gerbil-ascent-rule
       (list (gerbil-ascent-atom to (list (gerbil-ascent-variable 'value))))
       (list (gerbil-ascent-atom from (list (gerbil-ascent-variable 'value)))))))
  (def (make-closure n) (lambda (x) (+ n x)))
  (def (return-values . items) (apply values items))
  (def (make-cycle) (let (v (make-vector 1)) (vector-set! v 0 v) v))
  (define-evidence (make-evidence values)
    (gerbil-ascent-program
      (list (gerbil-ascent-relation 'input 1 (map list values))
            (gerbil-ascent-relation 'output 1 []))
      (list (copy-rule 'input 'output)) 32 64 96 '(input))
    (lambda (program result query scope)
      (hash ("status" "recorded-only") ("scope" scope)
            ("dependencies" (.ref program 'rules)) ("gap" "not a per-row proof"))))
