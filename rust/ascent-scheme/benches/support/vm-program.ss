;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Diagnostic-only independent heaps. No Scheme values cross VM boundaries.
(import :gerbil/runtime/gambit :std/iter :gerbil-scheme-rust/scheme/runtime
        :gerbil-ascent/program/actor-session :gerbil-ascent/program/session
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/rust/ascent-scheme/benches/support/scheme-runtime program edges truth row<?))
(export main)
(def (main . _) (void))
(def vm-id 0)
(def vm-components 0)
(def vm-input [])
(def vm-truth [])
(def vm-output [])
(extern entered)
(begin-foreign
  (namespace ("gerbil-ascent/rust/ascent-scheme/benches/support/vm-program#" entered))
  (c-declare "struct ascent_vm_context { void (*entered)(void *); void *data; };")
  (define entered (c-lambda ((pointer void)) void
    "struct ascent_vm_context *ctx = ___arg1; ctx->entered(ctx->data);")))
(def (shift rows base)
  (map (lambda (row) (list (+ base (car row)) (+ base (cadr row)))) rows))
(def (prepare k g w id owners)
  (set! vm-id (+ id 1))
  (set! vm-components k)
  (let ((one-edge (edges 1 w)) (one-truth (truth 1 w)))
    (set! vm-input
      (map (lambda (component)
        (apply append (map (lambda (group) (shift one-edge (* group w)))
          (filter (lambda (group) (= (modulo (+ (* component g) group) owners) id)) (iota g))))) (iota k)))
    (set! vm-truth
      (map (lambda (component)
        (apply append (map (lambda (group) (shift one-truth (* group w)))
          (filter (lambda (group) (= (modulo (+ (* component g) group) owners) id)) (iota g))))) (iota k))))
  (##gc)
  (if (= (##current-vm-processor-count) 1) vm-id -1))
(def (run context)
  (with-catch (lambda (failure) (display-exception failure (current-error-port)) -1)
    (lambda ()
      ;; The host barrier proves concurrent Scheme entry in every distinct image.
      (entered context)
      (let (session (gerbil-ascent-open-actor-session (program vm-components) workers: 1))
        (try
          (for-each (lambda (i input)
            (gerbil-ascent-session-replace-source! session (string->symbol (string-append "edge" (number->string i))) input))
            (iota vm-components) vm-input)
          (let (result (gerbil-ascent-session-run session))
            (unless (.ref result 'finished) (error "VM ASCENT run incomplete"))
            (set! vm-output (map (lambda (i) (list-sort row<? ((.ref result 'rows-of)
                 (string->symbol (string-append "reach" (number->string i)))))) (iota vm-components)))
            (apply + (map length vm-output)))
          (finally (gerbil-ascent-session-close! session)))))))
(def (validate)
  (if (equal? vm-output vm-truth) vm-id -1))
(begin-foreign
  (c-define (prepare k g w id owners) (unsigned-int32 unsigned-int32 unsigned-int32 unsigned-int32 unsigned-int32)
    int32 "ascent_vm_prepare" "extern" (gerbil-ascent/rust/ascent-scheme/benches/support/vm-program#prepare k g w id owners))
  (c-define (run context) ((pointer void)) int64 "ascent_vm_run" "extern"
    (gerbil-ascent/rust/ascent-scheme/benches/support/vm-program#run context))
  (c-define (validate) () int32 "ascent_vm_validate" "extern"
    (gerbil-ascent/rust/ascent-scheme/benches/support/vm-program#validate)))
