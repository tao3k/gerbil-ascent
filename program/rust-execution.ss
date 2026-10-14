;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Build-only typed function IR. The Rust host supplies ownership, indexes,
;;; budgets and Rayon scheduling; ordered relational composition is defined here.
;;; JSON is the upstream compiler's build artifact, never a runtime protocol.
(import :std/encoding/json)
(export main)
(def (node kind . fields) (list->hash-table (cons (cons "kind" kind) fields)))
(def (name value) (node "name" (cons "value" value)))
(def (call function . arguments)
  (node "call" (cons "callee" (name function)) (cons "arguments" (list->vector arguments))))
(def (method receiver operation . arguments)
  (node "method" (cons "receiver" receiver) (cons "method" operation)
        (cons "arguments" (list->vector arguments))))
(def (conditional condition consequent alternate)
  (node "if" (cons "condition" condition) (cons "consequent" consequent) (cons "alternate" alternate)))
(def (same left right)
  (node "binary" (cons "operator" "equal") (cons "left" left) (cons "right" right)))
(def (match-function function-name body)
  (function function-name
    '(("state" . "crate::execution::MatchState") ("term" . "&crate::execution::Pattern") ("value" . "crate::execution::Cell"))
    "crate::execution::MatchState" body))
(def (matching-ir)
  (let* ((state (name "state")) (term (name "term")) (value (name "value"))
         (slot (method term "variable_index")) (reject (method state "reject")))
    (list
      (match-function "bind_variable"
        (conditional (method state "contains" slot)
          (conditional (same (method state "value" slot) value) state reject)
          (method state "set" slot (method value "owned"))))
      (match-function "bind_checked"
        (conditional (method term "is_literal")
          (conditional (same (method term "literal_value") value) state reject)
          (call "bind_variable" state term value)))
      (match-function "bind_term"
        (conditional (method term "is_wildcard") state (call "bind_checked" state term value)))
      (match-function "bind_step"
        (conditional (method state "is_rejected") state (call "bind_term" state term value))))))
(def (binding-ir)
  (function "bind"
    '(("terms" . "&[crate::execution::Pattern]") ("row" . "&[crate::execution::Cell]")
      ("prior" . "&[Option<crate::execution::Cell>]"))
    "Option<crate::execution::Bindings>"
    (method
      (node "fold"
        (cons "iterator" (method (method (name "terms") "iter") "zip" (method (method (name "row") "iter") "copied")))
        (cons "accumulator" "state") (cons "item" "entry")
        (cons "initial" (call "crate::execution::MatchState::new" (name "prior")))
        (cons "step" (call "bind_step" (name "state")
          (node "tuple_index" (cons "tuple" (name "entry")) (cons "index" 0))
          (node "tuple_index" (cons "tuple" (name "entry")) (cons "index" 1)))))
      "finish")))
(def (function name parameters result body)
  (hash ("schema" "gerbil-scheme-rust.rust-function-ir.v1") ("name" name)
        ("parameters" (list->vector
          (map (lambda (p) (hash ("name" (car p)) ("ty" (cdr p)))) parameters)))
        ("result" result) ("body" (hash ("bindings" #()) ("result" body)))))
(def (rule-ir)
  (function "apply_rule"
    '(("rule" . "&crate::graph::Rule") ("store" . "&crate::execution::Store")
      ("pivot" . "Option<usize>") ("budget" . "&crate::execution::Budget"))
    "bool"
    (method
      (node "fold"
        (cons "iterator" (method (method (name "rule") "clauses") "enumerate"))
        (cons "accumulator" "batch") (cons "item" "entry")
        (cons "initial" (call "crate::execution::Batch::initial" (method (name "rule") "variables")))
        (cons "step" (method (name "batch") "advance" (name "entry") (name "store") (name "pivot") (name "budget"))))
      "project" (name "rule") (name "store") (name "budget"))))
(def (round-ir)
  (function "advance_round" '(("round" . "crate::execution::Round<'_>"))
    "crate::execution::Round<'_>"
    (method (method (name "round") "evaluate" (name "crate::execution::apply_rule")) "publish")))
(def (main . arguments)
  (for-each (lambda (ir) (write-json (current-output-port) ir) (newline)) (append (matching-ir) (list (binding-ir) (rule-ir) (round-ir)))))
