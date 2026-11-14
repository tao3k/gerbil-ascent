(define-program (make-graph-values)
  (let ((cycle (make-vector 1)) (shared (vector 17)) (table (make-hash-table-eq)))
    (vector-set! cycle 0 cycle)
    (hash-put! table 'same shared)
    (gerbil-ascent-program
     (list (gerbil-ascent-relation 'input 1
             (map list (list cycle (vector shared shared) table #\a (cons 1 2) identity
                             (string->uninterned-symbol "scoped") (string->uninterned-symbol "scoped")))))
     [] 32 64 96 '(input))))
