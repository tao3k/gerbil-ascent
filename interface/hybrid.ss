;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; ASCENT business exports. GC, roots and conversions belong to the upstream bridge.
(import (only-in "engine-api.ss" ascent-engine-call)
        :gerbil-scheme-rust/scheme/runtime
        :gerbil/runtime/gambit
        :gerbil-ascent/program/execution-control)
(extern namespace: #f gerbil-ascent/interface/hybrid#checkpoint)
(export main)
(def (main . _) (void))
(def (failure-message failure)
  ;; SyntaxError display pretty-prints through Gambit's terminal machinery.
  ;; A library error must not require a controlling terminal or enter a REPL.
  (or (error-message failure)
      (with-catch
        (lambda (_) "Scheme operation failed while formatting its exception")
        (lambda ()
          (call-with-output-string (lambda (port) (display-exception failure port)))))))
(def (check-execution control work facts)
  (case (gerbil-ascent/interface/hybrid#checkpoint control work facts)
    ((0) (void))
    ((1) (error "ASCENT execution canceled"))
    ((2) (error "ASCENT execution deadline exhausted"))
    ((3) (error "ASCENT execution work exhausted"))
    (else (error "ASCENT execution control closed"))))
(def (controlled-call control thunk)
  ;; Gambit-managed threads stay on the same VM and OS owner. No Rust thread
  ;; enters the VM. The monitor also bounds expansion and arbitrary callbacks.
  (let* ((active #t) (owner (current-thread))
         (monitor (make-thread
           (lambda ()
             (let loop ()
               (thread-sleep! 0.005)
               (when active
                 (if (= 0 (gerbil-ascent/interface/hybrid#checkpoint control 0 0))
                   (loop)
                   (thread-interrupt! owner
                     (lambda () (when active (check-execution control 0 0)))))))))))
    (dynamic-wind
      (lambda () (thread-start! monitor))
      (lambda ()
        (parameterize ((current-ascent-execution-control
                       (lambda (work facts) (check-execution control work facts))))
          (ascent-execution-checkpoint!)
          (thunk)))
      (lambda ()
        ;; Pending interrupt thunks observe this lexical flag before touching
        ;; request state, including when they arrive during the next ABI call.
        (set! active #f)
        (thread-terminate! monitor)))))
(def (invoke request)
  (with-catch
    (lambda (failure) (vector #f (failure-message failure)))
    (lambda ()
      (let (control (hash-ref request "executionControl" #f))
        (hash-remove! request "executionControl")
        (let (execute (lambda () (vector #t (ascent-engine-call request))))
          (if control (controlled-call control execute) (execute)))))))
(begin-foreign
  (c-declare "typedef int (*ascent_check_type)(int64_t, int64_t, int64_t);
static ascent_check_type ascent_check_fn = 0;
void ascent_hybrid_set_checkpoint(ascent_check_type fn) { ascent_check_fn = fn; }")
  (namespace ("gerbil-ascent/interface/hybrid#" checkpoint))
  (define checkpoint (c-lambda (int64 int64 int64) int "___return(ascent_check_fn ? ascent_check_fn(___arg1, ___arg2, ___arg3) : 5);"))
  (c-define (invoke request) (int64) int64 "ascent_hybrid_call" "extern"
    (gerbil-scheme-rust/scheme/runtime#gerbil-rs-rooted-call request
      gerbil-ascent/interface/hybrid#invoke)))
