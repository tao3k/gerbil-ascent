(import :std/test
        :gerbil-ascent/program/objects
        (only-in :gerbil-ascent/program/types gerbil-ascent-projection-tree-current?)
        (only-in :gerbil-ascent/interface/projection-cache ascent-projection-program)
        (only-in :clan/poo/object .o .ref))
(export ascent-projection-cache-test)
(def (program rows)
  (gerbil-ascent-program (list (gerbil-ascent-relation 'input 1 rows)) [] 32 64 96 '(input)))
(def (rows value) (.ref (car (.ref value 'relations)) 'rows))
(def ascent-projection-cache-test
  (test-suite "Private projection reuse retains fresh validation and source identity"
    (test-case "same generation reuses objects and replacement invalidates them"
      (let* ((original (program '((1)))) (sources '((input (2)))))
        (check-equal? (gerbil-ascent-projection-tree-current? original) #t)
        (let-values (((first cache) (ascent-projection-program original sources 0 #f)))
          (let-values (((second reused) (ascent-projection-program original sources 0 cache)))
            (check-equal? (eq? first second) #t)
            (check-equal? (eq? cache reused) #t)
            (check-equal? (rows second) '((2))))
          (let-values (((third replaced) (ascent-projection-program original '((input (3))) 1 cache)))
            (check-equal? (eq? first third) #f)
            (check-equal? (rows third) '((3)))))))
    (test-case "a reused object undergoes root validation after row mutation"
      (let* ((row (list 2)) (original (program '((1))))
             (sources (list (cons 'input (list row)))))
        (let-values (((first cache) (ascent-projection-program original sources 0 #f)))
          (set-cdr! row '(3))
          (check-exception (ascent-projection-program original sources 0 cache) true))))
    (test-case "foreign getter objects never enter the cache"
      (let* ((original (program '((1)))) (reads 0)
             (foreign (.o (:: @ original) relations: (begin (set! reads (+ reads 1)) (.ref original 'relations)))))
        (check-equal? (gerbil-ascent-projection-tree-current? foreign) #f)
        (let-values (((first cache) (ascent-projection-program foreign '((input (2))) 0 #f)))
          (check-equal? cache #f)
          (check-equal? (rows first) '((2))))
        (check-equal? (> reads 0) #t)))))
