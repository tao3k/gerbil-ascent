-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! The physical-entry publication protocol. Mutation can fail *after* changing
the referenced payload. A failed extension therefore revokes every alias; it
does not pretend to roll the provider back. Error values are preserved exactly.
The primitive boundary is exclusive ownership of an entry and ordinary field
get/set semantics, not a premise that arbitrary providers are pure. -/
namespace Ascent.CachePublication
variable {Lookup Witness Error : Type}

structure Entry (Lookup Witness : Type) where
  version : Option Nat
  lookup : Lookup
  witness : Witness

inductive Mutation (Error Value : Type) where
  | done (value : Value)
  | failed (error : Error) (changed : Value)

inductive Op where
  | members | build | revoke | mutate | lookup | witness | publish
  deriving Repr, DecidableEq

def rebuildOps : List Op := [.members, .build, .lookup, .witness, .publish]
def extendOps : List Op := [.revoke, .mutate, .lookup, .witness, .publish]

structure Outcome (Error Lookup Witness : Type) where
  error : Option Error
  entry : Entry Lookup Witness
  trace : List Op

def extend (before : Entry Lookup Witness) (target : Except Error Nat)
    (mutate : Lookup → Mutation Error Lookup) (witness : Witness → Mutation Error Witness) :
    Outcome Error Lookup Witness :=
  let revoked := {before with version := none}
  match mutate revoked.lookup with
  | .failed error changed => ⟨some error, {revoked with lookup := changed}, [.revoke, .mutate]⟩
  | .done lookup =>
    let updated := {revoked with lookup := lookup}
    match witness updated.witness with
    | .failed error changed =>
      ⟨some error, {updated with witness := changed}, [.revoke, .mutate, .lookup, .witness]⟩
    | .done members =>
      let complete := {updated with witness := members}
      match target with
      | .error error => ⟨some error, complete, [.revoke, .mutate, .lookup, .witness]⟩
      | .ok version => ⟨none, {complete with version := some version}, extendOps⟩

theorem failed_extension_revoked (before : Entry Lookup Witness) (target : Except Error Nat)
    (mutate : Lookup → Mutation Error Lookup) (witness : Witness → Mutation Error Witness)
    (failed : (extend before target mutate witness).error.isSome = true) :
    (extend before target mutate witness).entry.version = none := by
  cases m : mutate before.lookup <;> simp_all [extend]
  cases w : witness before.witness <;> cases target <;> simp_all

theorem mutation_error_identity (before : Entry Lookup Witness) (target : Except Error Nat)
    (mutate : Lookup → Mutation Error Lookup) (witness : Witness → Mutation Error Witness)
    (error : Error) (changed : Lookup) (failed : mutate before.lookup = .failed error changed) :
    (extend before target mutate witness).error = some error ∧
      (extend before target mutate witness).entry.lookup = changed := by
  simp [extend, failed]

theorem witness_error_identity (before : Entry Lookup Witness) (target : Except Error Nat)
    (mutate : Lookup → Mutation Error Lookup) (witness : Witness → Mutation Error Witness)
    (error : Error) (lookup : Lookup) (changed : Witness)
    (mutated : mutate before.lookup = .done lookup)
    (failed : witness before.witness = .failed error changed) :
    (extend before target mutate witness).error = some error ∧
      (extend before target mutate witness).entry.lookup = lookup ∧
      (extend before target mutate witness).entry.witness = changed := by
  simp [extend, mutated, failed]

theorem revoke_before_provider (before : Entry Lookup Witness) (target : Except Error Nat)
    (mutate : Lookup → Mutation Error Lookup) (witness : Witness → Mutation Error Witness) :
    ((extend before target mutate witness).trace.take 2) = [.revoke, .mutate] := by
  cases m : mutate before.lookup <;> simp_all [extend]
  cases w : witness before.witness <;> cases target <;> rfl

theorem publish_only_after_success (before : Entry Lookup Witness) (target : Except Error Nat)
    (mutate : Lookup → Mutation Error Lookup) (witness : Witness → Mutation Error Witness) :
    Op.publish ∈ (extend before target mutate witness).trace ↔
      (extend before target mutate witness).error = none := by
  cases m : mutate before.lookup <;> simp_all [extend]
  cases w : witness before.witness <;> cases target <;> simp [extendOps]

theorem published_payload (before : Entry Lookup Witness) (target : Except Error Nat)
    (mutate : Lookup → Mutation Error Lookup) (witness : Witness → Mutation Error Witness)
    (lookup : Lookup) (members : Witness) (version : Nat)
    (m : mutate before.lookup = .done lookup) (w : witness before.witness = .done members)
    (v : target = .ok version) :
    (extend before target mutate witness).entry = ⟨some version, lookup, members⟩ := by
  simp [extend, m, w, v]

def rebuild (before : Entry Lookup Witness) (version : Nat)
    (members : Except Error Witness) (build : Except Error Lookup) : Outcome Error Lookup Witness :=
  match members with
  | .error error => ⟨some error, before, [.members]⟩
  | .ok witness => match build with
    | .error error => ⟨some error, before, [.members, .build]⟩
    | .ok lookup => ⟨none, ⟨some version, lookup, witness⟩, rebuildOps⟩

theorem failed_rebuild_preserves_entry (before : Entry Lookup Witness) (version : Nat)
    (members : Except Error Witness) (build : Except Error Lookup)
    (failed : (rebuild before version members build).error.isSome = true) :
    (rebuild before version members build).entry = before := by
  cases members <;> cases build <;> simp_all [rebuild]

/-- An instruction interpreter, independent of the source printer. Staged
rebuild values are private; an extension provider may mutate an aliased payload
before failing. A failed instruction stops the remaining program. -/
structure Machine (Error Lookup Witness : Type) where
  result : Outcome Error Lookup Witness
  stagedLookup : Lookup
  stagedWitness : Witness

def start (entry : Entry Lookup Witness) : Machine Error Lookup Witness :=
  ⟨⟨none, entry, []⟩, entry.lookup, entry.witness⟩

def instruction (extension : Bool) (target : Except Error Nat)
    (members : Except Error Witness) (build : Except Error Lookup)
    (mutate : Lookup → Mutation Error Lookup) (witness : Witness → Mutation Error Witness)
    (op : Op) (state : Machine Error Lookup Witness) : Machine Error Lookup Witness :=
  if state.result.error.isSome then state else
  let traced := {state.result with trace := state.result.trace ++ [op]}
  match op with
  | .revoke => {state with result := {traced with entry := {traced.entry with version := none}}}
  | .members => match members with
    | .error error => {state with result := {traced with error := some error}}
    | .ok value => {state with result := traced, stagedWitness := value}
  | .build => match build with
    | .error error => {state with result := {traced with error := some error}}
    | .ok value => {state with result := traced, stagedLookup := value}
  | .mutate => match mutate state.result.entry.lookup with
    | .failed error changed => {state with result := {traced with error := some error, entry := {traced.entry with lookup := changed}}}
    | .done value => {state with result := traced, stagedLookup := value}
  | .lookup => {state with result := {traced with entry := {traced.entry with lookup := state.stagedLookup}}}
  | .witness =>
    if extension then match witness state.result.entry.witness with
      | .failed error changed => {state with result := {traced with error := some error, entry := {traced.entry with witness := changed}}}
      | .done value => {state with result := {traced with entry := {traced.entry with witness := value}}}
    else {state with result := {traced with entry := {traced.entry with witness := state.stagedWitness}}}
  | .publish => match target with
    | .error error => {state with result := {state.result with error := some error}}
    | .ok version => {state with result := {traced with entry := {traced.entry with version := some version}}}

def execute (extension : Bool) (target : Except Error Nat)
    (members : Except Error Witness) (build : Except Error Lookup)
    (mutate : Lookup → Mutation Error Lookup) (witness : Witness → Mutation Error Witness)
    (ops : List Op) (before : Entry Lookup Witness) : Outcome Error Lookup Witness :=
  (ops.foldl (fun state op => instruction extension target members build mutate witness op state)
    (start before)).result

theorem extend_program_exact (before : Entry Lookup Witness) (target : Except Error Nat)
    (members : Except Error Witness) (build : Except Error Lookup)
    (mutate : Lookup → Mutation Error Lookup) (witness : Witness → Mutation Error Witness) :
    execute true target members build mutate witness extendOps before = extend before target mutate witness := by
  cases m : mutate before.lookup <;> cases w : witness before.witness <;> cases target <;>
    simp [execute, extendOps, List.foldl, start, instruction, extend, m, w]

theorem rebuild_program_exact (before : Entry Lookup Witness) (version : Nat)
    (members : Except Error Witness) (build : Except Error Lookup)
    (mutate : Lookup → Mutation Error Lookup) (witness : Witness → Mutation Error Witness) :
    execute false (.ok version) members build mutate witness rebuildOps before = rebuild before version members build := by
  cases members <;> cases build <;>
    simp [execute, rebuildOps, List.foldl, start, instruction, rebuild]

def rebuildSource : Op → String
  | .members => "(members members-expr)"
  | .build => "(built lookup-expr)"
  | .lookup => "(write-lookup! owner built)"
  | .witness => "(write-witness! owner members)"
  | .publish => "(write-version! owner version)"
  | _ => "INVALID-REBUILD-OP"

def extendSource : Op → String
  | .revoke => "(write-version! owner #f)"
  | .mutate => "(built mutate-expr)"
  | .lookup => "(write-lookup! owner built)"
  | .witness => "witness-expr"
  | .publish => "(write-version! owner next-version)"
  | _ => "INVALID-EXTEND-OP"

def source : String :=
  ";;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors\n;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later\n;;; Generated by CachePublication.lean; preserve evaluation and publication order.\n" ++
  "(export gerbil-ascent-index-rebuild! gerbil-ascent-index-extend!)\n" ++
  "(defrule (gerbil-ascent-index-rebuild! entry version members-expr lookup-expr write-lookup! write-witness! write-version!)\n  (let* ((owner entry) " ++
  String.intercalate " " ((rebuildOps.take 2).map rebuildSource) ++ ")\n    " ++
  String.intercalate "\n    " ((rebuildOps.drop 2).map rebuildSource) ++ "\n    built))\n" ++
  "(defrule (gerbil-ascent-index-extend! entry next-version mutate-expr witness-expr write-lookup! write-version!)\n  (let (owner entry)\n    " ++ extendSource .revoke ++
  "\n    (let (" ++ extendSource .mutate ++ ")\n      " ++
  String.intercalate "\n      " ((extendOps.drop 2).map extendSource) ++ ")))\n"

end Ascent.CachePublication
