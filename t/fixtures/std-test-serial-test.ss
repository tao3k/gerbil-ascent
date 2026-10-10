;;; Native harness execution contract; no Core sampling or ASCENT engine.
(import :std/test)
(export std-test-serial-test)
(def events [])
(def owner #f)
(def std-test-serial-test
  (test-suite "native std/test scheduling"
    (test-case "first Case finishes on its harness thread"
      (set! owner (current-thread))
      (set! events (cons 'first-start events))
      (thread-sleep! 0.01)
      (set! events (cons 'first-end events)))
    (test-case "second Case starts after the first finishes"
      (check-equal? (eq? owner (current-thread)) #t)
      (check-equal? (reverse events) '(first-start first-end))
      (set! events (cons 'second-start events))
      (thread-sleep! 0.01)
      (set! events (cons 'second-end events)))
    (test-case "third Case observes the complete ordered execution"
      (check-equal? (eq? owner (current-thread)) #t)
      (check-equal? (reverse events)
                    '(first-start first-end second-start second-end)))))
