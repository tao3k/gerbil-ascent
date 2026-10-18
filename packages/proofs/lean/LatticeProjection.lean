-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Keyed last-column map-lattice update and settled row projection. This models
native pending-before-committed lookup and replacement publication, not arbitrary
Scheme hash equality or user join purity. Replacement gamma need not be Set-monotone. -/
namespace Ascent.LatticeProjection
variable {Key Value : Type} [DecidableEq Key]
abbrev Store (Key Value : Type) := Key → Option Value

def update (merge : Value → Value → Value) (store : Store Key Value)
    (key : Key) (value : Value) : Store Key Value :=
  fun k => if k = key then some (match store key with
    | none => value
    | some prior => merge prior value) else store k

theorem update_hit (merge : Value → Value → Value) (store : Store Key Value)
    (key : Key) (value : Value) :
    update merge store key value key = some (match store key with
      | none => value | some prior => merge prior value) := by simp [update]

theorem update_other (merge : Value → Value → Value) (store : Store Key Value)
    (key other : Key) (value : Value) (different : other ≠ key) :
    update merge store key value other = store other := by simp [update,different]

def gamma (store : Store Key Value) (row : Key × Value) : Prop := store row.1 = some row.2

omit [DecidableEq Key] in
theorem gamma_unique (store : Store Key Value) (key : Key) (a b : Value)
    (ha : gamma store (key,a)) (hb : gamma store (key,b)) : a = b :=
  Option.some.inj (ha.symm.trans hb)

theorem replaced_row_absent (merge : Value → Value → Value) (store : Store Key Value)
    (key : Key) (old incoming : Value) (present : store key = some old)
    (changed : merge old incoming ≠ old) : ¬ gamma (update merge store key incoming) (key,old) := by
  intro retained
  have merged : merge old incoming = old := by simpa [gamma,update,present] using retained
  exact changed merged

structure JoinLaws (Value : Type) where
  merge : Value → Value → Value
  assoc : ∀ a b c, merge (merge a b) c = merge a (merge b c)
  comm : ∀ a b, merge a b = merge b a
  idem : ∀ a, merge a a = a

def Below (j : JoinLaws Value) (a b : Value) : Prop := j.merge a b = b

theorem join_above_left (j : JoinLaws Value) (a b : Value) : Below j a (j.merge a b) := by
  dsimp [Below]
  rw [← j.assoc, j.idem]

theorem below_trans (j : JoinLaws Value) (a b c : Value)
    (ab : Below j a b) (bc : Below j b c) : Below j a c := by
  dsimp [Below] at *
  rw [← bc, ← j.assoc, ab]

def StoreBelow (j : JoinLaws Value) (a b : Store Key Value) : Prop :=
  ∀ key value, a key = some value → ∃ next, b key = some next ∧ Below j value next

theorem update_inflationary (j : JoinLaws Value) (store : Store Key Value)
    (key : Key) (value : Value) : StoreBelow j store (update j.merge store key value) := by
  intro k old present
  by_cases same : k = key
  · subst k
    exact ⟨j.merge old value, by simp [update,present], join_above_left j old value⟩
  · exact ⟨old, by simp [update,same,present], j.idem old⟩

theorem update_twice (j : JoinLaws Value) (store : Store Key Value)
    (key : Key) (a b : Value) :
    update j.merge (update j.merge store key a) key b = update j.merge store key (j.merge a b) := by
  funext k
  by_cases same : k = key
  · subst k
    cases prior : store key <;> simp [update,prior,j.assoc]
  · simp [update,same]

def stage (merge : Value → Value → Value) (store : Store Key Value) : List (Key × Value) → Store Key Value
  | [] => store
  | row :: rest => stage merge (update merge store row.1 row.2) rest

theorem store_below_trans (j : JoinLaws Value) (a b c : Store Key Value)
    (ab : StoreBelow j a b) (bc : StoreBelow j b c) : StoreBelow j a c := by
  intro key value hit
  obtain ⟨middle,found,first⟩ := ab key value hit
  obtain ⟨final,last,second⟩ := bc key middle found
  exact ⟨final,last,below_trans j value middle final first second⟩

theorem stage_inflationary (j : JoinLaws Value) (store : Store Key Value)
    (rows : List (Key × Value)) : StoreBelow j store (stage j.merge store rows) := by
  induction rows generalizing store with
  | nil => exact fun _ value hit => ⟨value,hit,j.idem value⟩
  | cons row rest ih =>
    exact store_below_trans j _ _ _
      (update_inflationary j store row.1 row.2) (ih _)

theorem stage_untouched (merge : Value → Value → Value) (store : Store Key Value)
    (rows : List (Key × Value)) (key : Key) (absent : key ∉ rows.map Prod.fst) :
    stage merge store rows key = store key := by
  induction rows generalizing store with
  | nil => rfl
  | cons row rest ih =>
      have other : key ≠ row.1 := by intro h; exact absent (by simp [h])
      have tail : key ∉ rest.map Prod.fst := by intro h; exact absent (by simp [h])
      rw [stage,ih _ tail,update_other merge store row.1 key row.2 other]

def publish (old pending : Store Key Value) (touched : List Key) : Store Key Value :=
  fun key => if key ∈ touched then pending key else old key

theorem publish_exact (old pending : Store Key Value) (touched : List Key)
    (untouched : ∀ key, key ∉ touched → pending key = old key) :
    publish old pending touched = pending := by
  funext key
  by_cases touchedKey : key ∈ touched
  · simp [publish,touchedKey]
  · simp [publish,touchedKey,untouched key touchedKey]

theorem publish_stage_exact (merge : Value → Value → Value) (old : Store Key Value)
    (rows : List (Key × Value)) :
    publish old (stage merge old rows) (rows.map Prod.fst) = stage merge old rows :=
  publish_exact old _ _ (stage_untouched merge old rows)

-- The pending row table contains one final row per touched key. Public row
-- materialization removes every old row for those keys, rather than unioning it.
def replaceRows (old pending : List (Key × Value)) : List (Key × Value) :=
  pending ++ old.filter (fun row => !(decide (row.1 ∈ pending.map Prod.fst)))

theorem replacement_member (old pending : List (Key × Value)) (row : Key × Value) :
    row ∈ replaceRows old pending ↔ row ∈ pending ∨
      (row ∈ old ∧ row.1 ∉ pending.map Prod.fst) := by simp [replaceRows]

theorem old_key_removed (old pending : List (Key × Value)) (row : Key × Value)
    (touched : row.1 ∈ pending.map Prod.fst) (notFinal : row ∉ pending) :
    row ∉ replaceRows old pending := by simp [replacement_member,touched,notFinal]

-- Last-column encoding agrees with the native butlast/last row convention.
def encode (key : List Value) (value : Value) : List Value := key ++ [value]
theorem encode_key (key : List Value) (value : Value) : (encode key value).dropLast = key := by
  simp [encode]
theorem encode_value (key : List Value) (value : Value) : (encode key value).getLast? = some value := by
  simp [encode]

end Ascent.LatticeProjection
