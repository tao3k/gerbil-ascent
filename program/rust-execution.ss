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
;; BEGIN GENERATED BORROWED MATCH
(def (match-function function-name body)
  (function function-name
    '(("state" . "&mut crate::execution::MatchState") ("term" . "&crate::execution::Pattern") ("value" . "crate::execution::Cell"))
    "bool" body))
(def (matching-ir)
  (let* ((state (name "state")) (term (name "term")) (value (name "value"))
         (slot (method term "variable_index")))
    (list
      (match-function "bind_variable"
        (conditional (method state "contains" slot)
          (same (method state "value" slot) value)
          (method state "set" slot (method value "owned"))))
      (match-function "bind_checked"
        (conditional (method term "is_literal")
          (same (method term "literal_value") value)
          (call "bind_variable" state term value)))
      (match-function "bind_term"
        (node "binary" (cons "operator" "or")
          (cons "left" (method term "is_wildcard"))
          (cons "right" (call "bind_checked" state term value)))))))
(def (binding-ir)
  (function "bind"
    '(("terms" . "&[crate::execution::Pattern]") ("row" . "&[crate::execution::Cell]")
      ("prior" . "&[Option<crate::execution::Cell>]"))
    "Option<crate::execution::Bindings>"
    (call "crate::execution::MatchState::matching"
      (name "terms") (name "row") (name "prior") (name "bind_term"))))
;; END GENERATED BORROWED MATCH
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
(def graph-type "crate::RelationalGraph")
(def graph-result "crate::Result<crate::RelationalGraph>")
(def graph-function "impl Fn(crate::RelationalGraph) -> crate::Result<crate::RelationalGraph> + Send + Sync + 'static")
(def graph-owner "std::sync::Arc<dyn Fn(crate::RelationalGraph) -> crate::Result<crate::RelationalGraph> + Send + Sync>")
(def (closure parameters result body)
  (node "closure" (cons "parameters" (list->vector
    (map (lambda (p) (hash ("name" (car p)) ("ty" (cdr p)))) parameters)))
    (cons "result" result) (cons "move_capture" #t)
    (cons "body" (hash ("bindings" #()) ("result" body)))))
(def (borrow value) (node "borrow" (cons "value" value)))
(def (checked value) (node "try" (cons "value" value)))
(def (integer value) (node "number" (cons "value" value)))
(def (graph-ir)
  (list
    (function "make_projection_graph" '(("columns" . "Vec<usize>")) graph-function
      (closure (list (cons "input" graph-type)) graph-result
        (method (name "input") "project" (method (name "columns") "clone"))))
    (function "make_transitive_graph" [] graph-function
      (closure (list (cons "edge" graph-type)) graph-result
        (call "crate::RelationalGraph::fixed_point" (integer 2)
          (closure (list (cons "path" graph-type)) graph-result
            (method
              (checked (method
                (checked (method (name "path") "join" (borrow (name "edge")) (integer 1) (integer 0)))
                "project" (node "vector" (cons "values" (vector (integer 0) (integer 3))))))
              "union" (borrow (name "edge")))))))
    (function "compose_graphs" (list (cons "first" graph-owner) (cons "second" graph-owner)) graph-function
      (closure (list (cons "input" graph-type)) graph-result
        (call "second" (checked (call "first" (name "input"))))))))
(def (main . arguments)
  (for-each (lambda (ir) (write-json (current-output-port) ir) (newline))
    (append (matching-ir) (list (binding-ir) (rule-ir) (round-ir)) (graph-ir))))
