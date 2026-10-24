;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; ASCENT business exports. GC, roots and conversions belong to the upstream bridge.
(import (only-in "engine-api.ss" ascent-engine-call)
        :gerbil-scheme-rust/scheme/runtime
        (only-in :gerbil/runtime/loader set-load-path! load-module)
        (only-in :gerbil/runtime/init __scheme-source)
        (only-in :gerbil/runtime/mop slot-ref)
        :gerbil/runtime/gambit
        :gerbil-ascent/program/execution-control)
(extern namespace: #f gerbil-ascent/interface/hybrid#checkpoint
                       gerbil-ascent/interface/hybrid#bind-checkpoint)
(export main)
(def instance-loader-installed? #f)
(def (install-instance-source-loader! library)
  (set-load-path! (list library))
  (unless instance-loader-installed?
    ;; The SDK's generated .scm carriers are raw Gambit code. Scope its existing
    ;; raw-source parameter to module loading only; user `load` and DSL evaluation
    ;; retain their ordinary semantics. No compiler is entered or reimplemented.
    (let (original load-module)
      (set! load-module
        (lambda (module)
          (parameterize ((__scheme-source module)) (original module)))))
    (set! instance-loader-installed? #t)))
(def (main . _) (void))
(def (failure-message failure)
  ;; SyntaxError display pretty-prints through Gambit's terminal machinery.
  ;; A library error must not require a controlling terminal or enter a REPL.
  (or (let (message (error-message failure))
        (if (and message (equal? message "Reference to unbound identifier"))
          (string-append message ": "
            (call-with-output-string (lambda (port) (write (cond
              ((unbound-global-exception? failure) (unbound-global-exception-variable failure))
              (else
                (map (lambda (value) (slot-ref value 'e (lambda _ value)))
                     (slot-ref failure 'irritants (lambda _ []))))) port))))
          message))
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
  (let* ((active #t) (pending #f) (owner (current-thread))
         (monitor (make-thread
           (lambda ()
             (let loop ()
               (thread-sleep! 0.005)
               (when active
                 (when (and (not pending)
                            (not (= 0 (gerbil-ascent/interface/hybrid#checkpoint control 0 0))))
                   ;; A callback may catch an interrupt. Keep monitoring until
                   ;; the ABI extent exits, with at most one queued interrupt.
                   (set! pending #t)
                   (thread-interrupt! owner
                     (lambda ()
                       (set! pending #f)
                       (when active (check-execution control 0 0)))))
                 (loop)))))))
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
  (c-declare "#include <stdint.h>
typedef int (*ascent_check_type)(int64_t, int64_t, int64_t);
static ascent_check_type ascent_check_fn = 0;
void ascent_hybrid_set_checkpoint(ascent_check_type fn) { ascent_check_fn = fn; }")
  (namespace ("gerbil-ascent/interface/hybrid#" checkpoint bind-checkpoint))
  (define bind-checkpoint
    (c-lambda (unsigned-int64) void
      "ascent_hybrid_set_checkpoint((ascent_check_type)(uintptr_t)___arg1);"))
  (c-define (bind request) (int64) int64 "ascent_hybrid_bind" "extern"
    (gerbil-scheme-rust/scheme/runtime#gerbil-rs-rooted-call request
      (lambda (input)
        (unless (and (vector? input) (= (vector-length input) 2)
                     (string? (vector-ref input 1)))
          (error "invalid fixed-owner initialization"))
        (gerbil-ascent/interface/hybrid#install-instance-source-loader! (vector-ref input 1))
        (gerbil-ascent/interface/hybrid#bind-checkpoint (vector-ref input 0)))))
  (c-define (table request) (int64) int64 "ascent_hybrid_table" "extern"
    (gerbil-scheme-rust/scheme/runtime#gerbil-rs-rooted-call request
      (lambda (entries)
        (unless (and (vector? entries) (even? (vector-length entries)))
          (error "invalid typed table entries"))
        (let ((out (make-hash-table)))
          (let loop ((i 0))
            (if (= i (vector-length entries)) out
              (begin
                (hash-put! out (vector-ref entries i) (vector-ref entries (+ i 1)))
                (loop (+ i 2)))))))))
  (define checkpoint (c-lambda (int64 int64 int64) int "___return(ascent_check_fn ? ascent_check_fn(___arg1, ___arg2, ___arg3) : 5);"))
  (c-define (invoke request) (int64) int64 "ascent_hybrid_call" "extern"
    (gerbil-scheme-rust/scheme/runtime#gerbil-rs-rooted-call request
      gerbil-ascent/interface/hybrid#invoke)))
