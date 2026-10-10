-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import SourceUpdateFrame

/-!
Explicit full-row rule-body semantics for the admitted closed subset. Relation
access occurs in atom, negation and aggregate constructors; matchers, guards,
bindings and reducers receive only rows/environments already supplied to them.
Head admission additionally reads its own old rows. Locality is proved from the
interpreter, rather than assumed as a compiler/evaluator `readsMatch` premise.

This is a pure typed interpreter, not extraction of Gerbil's visit-body,
semi-naive pivots, index providers, mutable buffers or actor scheduling.
-/

namespace Ascent.RuleBodyFrame

open RuleGraphClosure DependencyInvalidation

inductive Clause (Key Row Env : Type) where
  | atom (source : Key) (matchRow : Row → Env → Option Env)
  | negation (source : Key) (matchRow : Row → Env → Option Env)
  | aggregate (source : Key) (matchRow : Row → Env → Option Env)
      (reduce : List Env → Env → List Env)
  | guard (predicate : Env → Bool)
  | binding (compute : Env → Env)

variable {Key Row Env : Type}

def Clause.graph : Clause Key Row Env → RuleGraphClosure.Clause Key
  | .atom source _ => ⟨.atom, some source⟩
  | .negation source _ => ⟨.negation, some source⟩
  | .aggregate source _ _ => ⟨.aggregate, some source⟩
  | .guard _ => ⟨.guard, none⟩
  | .binding _ => ⟨.binding, none⟩

def Clause.run (clause : Clause Key Row Env) (state : Key → List Row)
    (env : Env) : List Env :=
  match clause with
  | .atom source matchRow => (state source).filterMap (fun row => matchRow row env)
  | .negation source matchRow =>
      if (state source).any (fun row => (matchRow row env).isSome) then [] else [env]
  | .aggregate source matchRow reduce =>
      reduce ((state source).filterMap (fun row => matchRow row env)) env
  | .guard predicate => if predicate env then [env] else []
  | .binding compute => [compute env]

def BodyReads (body : List (Clause Key Row Env)) (source : Key) : Prop :=
  ∃ clause ∈ body, clause.graph.source = some source

def evalBody : List (Clause Key Row Env) → (Key → List Row) → Env → List Env
  | [], _, env => [env]
  | clause :: rest, state, env =>
      (clause.run state env).flatMap (evalBody rest state)

theorem Clause.graph_reads_of_source (clause : Clause Key Row Env)
    (source : Key) (read : clause.graph.source = some source) :
    clause.graph.kind.reads = true := by
  cases clause <;> simp_all [Clause.graph, ClauseKind.reads]

theorem Clause.run_congr (clause : Clause Key Row Env)
    (before after : Key → List Row)
    (same : ∀ source, clause.graph.source = some source → before source = after source)
    (env : Env) : clause.run before env = clause.run after env := by
  cases clause <;> simp_all [Clause.run, Clause.graph]

/-- Branching, negative absence and whole-group reduction preserve equality
when their declared relation rows agree. Empty groups are included. -/
theorem evalBody_congr (body : List (Clause Key Row Env))
    (before after : Key → List Row)
    (same : ∀ source, BodyReads body source → before source = after source) :
    evalBody body before = evalBody body after := by
  induction body with
  | nil => rfl
  | cons clause rest ih =>
      have tailSame := ih (fun source read => by
        rcases read with ⟨other, member, sourceEq⟩
        exact same source ⟨other, List.mem_cons_of_mem clause member, sourceEq⟩)
      funext env
      have firstSame := clause.run_congr before after
        (fun source read => same source ⟨clause, List.mem_cons_self, read⟩) env
      simp only [evalBody, firstSame, tailSame]

structure Head (Key Row Env : Type) where
  target : Key
  emit : Env → Row

structure Rule (Key Row Env : Type) where
  heads : List (Head Key Row Env)
  body : List (Clause Key Row Env)
  seed : Env

def Rule.graph (rule : Rule Key Row Env) : RuleGraphClosure.Rule Key :=
  ⟨rule.heads.map Head.target, rule.body.map Clause.graph⟩

def plans (rules : List (Rule Key Row Env)) : List (RuleGraphClosure.Rule Key) :=
  rules.map Rule.graph

def Rule.outputs [DecidableEq Key] (rule : Rule Key Row Env)
    (target : Key) (state : Key → List Row) : List Row :=
  if target ∈ rule.heads.map Head.target then
    (evalBody rule.body state rule.seed).flatMap fun env =>
      rule.heads.filterMap fun head =>
        if head.target = target then some (head.emit env) else none
  else []

theorem Rule.outputs_congr [DecidableEq Key] (rule : Rule Key Row Env)
    (target : Key) (before after : Key → List Row)
    (same : target ∈ rule.heads.map Head.target →
      ∀ source, BodyReads rule.body source → before source = after source) :
    rule.outputs target before = rule.outputs target after := by
  unfold Rule.outputs
  split
  · rename_i member
    rw [evalBody_congr rule.body before after (same member)]
  · rfl

theorem read_into [DecidableEq Key] (rules : List (Rule Key Row Env))
    (rule : Rule Key Row Env) (member : rule ∈ rules) (source target : Key)
    (head : target ∈ rule.heads.map Head.target) (read : BodyReads rule.body source) :
    ReadsInto (plans rules) source target := by
  rcases read with ⟨clause, bodyMember, sourceEq⟩
  exact ⟨rule.graph, List.mem_map.mpr ⟨rule, member, rfl⟩,
    clause.graph, List.mem_map.mpr ⟨clause, bodyMember, rfl⟩,
    clause.graph_reads_of_source source sourceEq, sourceEq, head⟩

private theorem flatMap_congr_of_mem {A B : Type} (xs : List A)
    (f g : A → List B) (same : ∀ x ∈ xs, f x = g x) :
    xs.flatMap f = xs.flatMap g := by
  induction xs with
  | nil => rfl
  | cons x rest ih =>
      simp only [List.flatMap_cons]
      rw [same x List.mem_cons_self,
        ih (fun y member => same y (List.mem_cons_of_mem x member))]

/-- A pure admission function may deduplicate, join a lattice, or replace
rows. It sees only this head's old rows and this head's new rule emissions. -/
def step [DecidableEq Key] (rules : List (Rule Key Row Env))
    (admit : Key → List Row → List Row → List Row)
    (state : Key → List Row) (target : Key) : List Row :=
  admit target (state target) (rules.flatMap (fun rule => rule.outputs target state))

def edge [DecidableEq Key] (rules : List (Rule Key Row Env))
    (source target : Key) : Prop := source = target ∨ ReadsInto (plans rules) source target

/-- Derived from the executable body interpreter and head admission. No
independent evaluator-read checklist or locality hypothesis is supplied. -/
theorem step_local [DecidableEq Key] (rules : List (Rule Key Row Env))
    (admit : Key → List Row → List Row → List Row) : Local (edge rules) (step rules admit) := by
  intro before after target same
  unfold step
  rw [same target (Or.inl rfl)]
  apply congrArg (admit target (after target))
  apply flatMap_congr_of_mem
  intro rule member
  apply rule.outputs_congr target before after
  intro head source read
  exact same source (Or.inr (read_into rules rule member source target head read))

/-- Source-log comparison, bitmap closure and explicit rule evaluation compose
to completed reuse without a `readsMatch` premise. Completion and the native
representation/refinement boundary remain separate obligations. -/
theorem completed_reuse [DecidableEq Row]
    (rules : List (Rule (Fin count) Row Env))
    (admit : Fin count → List Row → List Row → List Row)
    (cut : SourceUpdateFrame.Cut count Row) (oldRounds newRounds : Nat)
    (oldStable : step rules admit (iterate (step rules admit) oldRounds cut.before) =
      iterate (step rules admit) oldRounds cut.before)
    (newStable : step rules admit (iterate (step rules admit) newRounds cut.candidate) =
      iterate (step rules admit) newRounds cut.candidate) :
    AgreeOutside (SourceUpdateFrame.affected (plans rules) cut)
      (iterate (step rules admit) oldRounds cut.before)
      (iterate (step rules admit) newRounds cut.candidate) := by
  have closed : Closed (edge rules) (SourceUpdateFrame.affected (plans rules) cut) := by
    intro source target read selected
    rcases read with self | bodyRead
    · simpa [self] using selected
    · exact NativeBitmapWorklist.runFuel_compiled_closed count (plans rules) cut.seeds
        cut.seeds_nodup source target bodyRead selected
  exact DependencyInvalidation.completed_frame (edge rules)
    (SourceUpdateFrame.affected (plans rules) cut) (step rules admit) closed
    (step_local rules admit) (SourceUpdateFrame.source_frame (plans rules) cut)
    oldRounds newRounds oldStable newStable

end Ascent.RuleBodyFrame
