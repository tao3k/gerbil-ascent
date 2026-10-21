(define-program (make-lattice inputs)
  (gerbil-ascent-program
   (list (gerbil-ascent-relation 'improve 2 inputs)
         (gerbil-ascent-lattice 'best 2 [] min))
   (list (gerbil-ascent-rule
     (list (gerbil-ascent-atom 'best (list (gerbil-ascent-variable 'k) (gerbil-ascent-variable 'v))))
     (list (gerbil-ascent-atom 'improve (list (gerbil-ascent-variable 'k) (gerbil-ascent-variable 'v))))))
   32 64 96 '(improve)))
