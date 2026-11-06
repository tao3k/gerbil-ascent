;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite test-case check-equal?)
        (only-in :clan/poo/object .get)
        "../init.ss")
(export library-module-test)

(def library-module-test
  (test-suite "Native Library capability publication"
    (test-case "Inference publishes callable constructors in its owned source context"
      (check-equal? (procedure? (.get gerbil-ascent.init.exports Library inference scope program)) #t)
      (check-equal? (procedure? (.get gerbil-ascent.init.exports Library inference scope relation)) #t))
    (test-case "Native providers and inference evaluate the published relations"
      (let* ((make-program (.get gerbil-ascent.init.exports Library inference scope program))
             (evaluate (.get gerbil-ascent.init.exports Library inference scope evaluate))
             (index (.get gerbil-ascent.init.exports Library relations scope hash-index-provider))
             (storage (.get gerbil-ascent.init.exports Library relations scope set-storage-provider))
             (program (make-program
                        (list ((.get gerbil-ascent.init.exports Library inference scope relation) 'edge 2 '((1 2) (2 3)) index storage))
                        '() 8 16 32))
             (rows ((.get (evaluate program) rows-of) 'edge)))
        (check-equal? (length rows) 2)
        (check-equal? (and (member '(1 2) rows) (member '(2 3) rows) #t) #t)))
    (test-case "Real query, independent finite replay and source-bound reuse"
      (let* ((evidence (.get gerbil-ascent.init.exports Library evidence scope))
             (snapshot ((.get evidence snapshot) 'library/reachability 1
                         '((edge 2 ((1 2) (2 3))))))
             (changed ((.get evidence snapshot) 'library/reachability 2
                        '((edge 2 ((1 2))))))
             (datum '(candidate (relation path 2)
                       (rule (path ?x ?y) (edge ?x ?y))
                       (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
                       (query path 1 ?y) (limits 8 16 32)))
             (receipt ((.get evidence attempt) snapshot datum))
             (spec ((.get evidence inspect) snapshot datum))
             (digest ((.get evidence digest) receipt))
             (status ((.get evidence status) receipt))
             (rows ((.get evidence rows) receipt))
             (capture (.get gerbil-ascent.init.exports Library evidence scope capture))
             (verify (.get gerbil-ascent.init.exports Library evidence scope verify))
             (certificate (capture snapshot spec digest status rows 1000)))
        ;; Independent expected reachability; no production-query output as oracle.
        (check-equal? status 'complete)
        (check-equal? (length rows) 2)
        (check-equal? (and (member '(1 2) rows) (member '(1 3) rows) #t) #t)
        (check-equal? (verify snapshot spec digest status rows certificate 1000) 'valid)
        (check-equal? (verify changed spec digest status rows certificate 1000) 'invalid)
        ;; Historical evidence remains valid for its own source snapshot.
        (check-equal? (verify snapshot spec digest status rows certificate 1000) 'valid)))))
