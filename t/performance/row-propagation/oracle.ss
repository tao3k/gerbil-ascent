;;; Independent positive-path Floyd-Warshall oracle for the research kernels.
(import (only-in :clan/poo/object .o .mix .ref .call)
        (only-in :clan/poo/trie UIntTrieSet)
        :gerbil-ascent/t/performance/row-propagation/kernel
        :gerbil-ascent/t/performance/row-propagation/reference)
(def (expression prototype edges width)
  (.mix prototype (.o (source-pairs (.call UIntTrieSet .<-list edges)) (radix width))))
(def (same left right)
  (unless (equal? left right) (error "research kernel mismatch" left right)))
(def (matrix edges radix)
  (let (result (make-vector (* radix radix) #f))
    (for-each (lambda (edge) (vector-set! result edge 1)) edges)
    (for-each
     (lambda (via)
       (for-each
        (lambda (from)
          (for-each
           (lambda (to)
             (let ((left (vector-ref result (+ (* from radix) via)))
                   (right (vector-ref result (+ (* via radix) to)))
                   (old (vector-ref result (+ (* from radix) to))))
               (when (and left right (or (not old) (< (+ left right) old)))
                 (vector-set! result (+ (* from radix) to) (+ left right)))))
           (iota radix))) (iota radix))) (iota radix))
    result))
(for-each
 (lambda (mask)
   (let* ((edges (filter (lambda (pair) (bit-set? pair mask)) (iota 9)))
          (truth (matrix edges 3))
          (rows (filter (lambda (pair) (vector-ref truth pair)) (iota 9))))
     (for-each
      (lambda (prototype)
        (let ((candidate (expression prototype edges 3)) (reference (expression row-reference-prototype edges 3)))
          (same (.ref candidate 'closure-pairs) rows)
          (same (.ref candidate 'shortest-distance-pairs) rows)
          (for-each
           (lambda (slot) (same (.ref candidate slot) (.ref reference slot)))
           '(two-hop-pairs at-most-two-hop-pairs))
          (for-each
           (lambda (pair)
             (same ((.ref candidate 'closure-contains?) pair) (and (vector-ref truth pair) #t))
             (same ((.ref candidate 'shortest-distance-of) pair) (vector-ref truth pair))) (iota 9))
          (for-each
           (lambda (budget)
             (same (with-catch (lambda (e) (error-message e))
                     (lambda () (.ref ((.ref candidate 'closure-bounded) budget) 'pairs)))
                   (if (< budget (length rows)) "ASCENT derived pair budget exceeded" rows))) (iota 10))))
      (list row-frontier-prototype row-warshall-prototype)))
   (when (zero? (modulo (+ mask 1) 32))
     (displayln "ORACLE " (+ mask 1) "/512") (force-output))) (iota 512))
(for-each
 (lambda (radix)
   (let* ((edges (list 0 1 (- radix 1) (+ radix 1) (- (* radix radix) 1)))
          (reference (expression row-reference-prototype edges radix)))
     (for-each
      (lambda (prototype)
        (let (candidate (expression prototype edges radix))
          (for-each
           (lambda (slot) (same (.ref candidate slot) (.ref reference slot)))
           '(two-hop-pairs at-most-two-hop-pairs closure-pairs shortest-distance-pairs))
          (for-each
           (lambda (pair)
             (same ((.ref candidate 'shortest-distance-of) pair) ((.ref reference 'shortest-distance-of) pair)))
           (append (.ref reference 'closure-pairs) (list -1 (* radix radix) 1/2)))))
      (list row-frontier-prototype row-warshall-prototype)))
   (displayln "BOUNDARY " radix) (force-output)) '(16 17 31 32 61 62 63 64 65 511 512))
(displayln "OK")
