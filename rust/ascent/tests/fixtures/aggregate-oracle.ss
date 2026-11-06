;;; Compare native aggregate contracts against the unchanged Scheme library.
(import :gerbil-ascent/program/aggregators)
(let loop ()
  (let (datum (read))
    (unless (eof-object? datum)
      (let ((name (car datum)) (tuples (cadr datum)))
        (write ((case name
                  ((count) gerbil-ascent-count) ((sum) gerbil-ascent-sum)
                  ((min) gerbil-ascent-min) ((max) gerbil-ascent-max)
                  ((mean) gerbil-ascent-mean)) tuples))
        (newline))
      (loop))))
