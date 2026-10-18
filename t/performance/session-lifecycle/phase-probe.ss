(import :gerbil/runtime/gambit
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface gerbil-ascent-program gerbil-ascent-relation
                 gerbil-ascent-open-session gerbil-ascent-session-run
                 gerbil-ascent-session-append-source!))
(def rows (map list (iota 10000)))
(def p (gerbil-ascent-program (list (gerbil-ascent-relation 'item 1 [])) [] 10002 10000 10000))
(def (bytes) (inexact->exact (f64vector-ref (##process-statistics) 7)))
(def (measure phase call)
  (let ((b (bytes)) (t (current-jiffy)))
    (let (v (call))
      (displayln phase " bytes=" (- (bytes) b) " ns="
        (quotient (* (- (current-jiffy) t) 1000000000) (jiffies-per-second)))
      (force-output) v)))
(for-each
 (lambda (sample)
   (displayln "SAMPLE " sample)
   (let (s (measure 'open (lambda () (gerbil-ascent-open-session p))))
     (measure 'initial (lambda () (gerbil-ascent-session-run s)))
     (measure 'append-public (lambda () (for-each (lambda (r) (gerbil-ascent-session-append-source! s 'item r)) rows)))
     (let (result (measure 'solve (lambda () (gerbil-ascent-session-run s))))
       (measure 'demand (lambda () ((.ref result 'rows-of) 'item))))))
 (iota 6))
(displayln "OK")
