/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

Termination for a ranked finite-height state space. This theorem is a
proof obligation for typed descriptors, not a theorem about arbitrary
Scheme closures. Construction and external data validity remain separate.
-/
import Std

namespace Ascent

def iterateStep {α : Type} (step : α → α) (initial : α) : Nat → α
  | 0 => initial
  | n + 1 => step (iterateStep step initial n)

/-- Every nonstationary step must strictly increase a bounded rank. -/
theorem bounded_rank_stabilizes {α : Type} (step : α → α)
    (initial : α) (rank : α → Nat) (height : Nat)
    (bounded : ∀ x, rank x ≤ height)
    (progress : ∀ x, step x ≠ x → rank x < rank (step x)) :
    ∃ n, n ≤ height ∧
      step (iterateStep step initial n) = iterateStep step initial n := by
  apply Classical.byContradiction
  intro h
  have moving : ∀ n, n ≤ height →
      step (iterateStep step initial n) ≠ iterateStep step initial n := by
    intro n hn heq
    exact h ⟨n, hn, heq⟩
  have climbing : ∀ n, n ≤ height + 1 →
      n ≤ rank (iterateStep step initial n) := by
    intro n
    induction n with
    | zero => intro _; omega
    | succ n ih =>
      intro hn
      have old := ih (by omega)
      have incr := progress (iterateStep step initial n)
        (moving n (by omega))
      simp only [iterateStep] at *
      omega
  have lower := climbing (height + 1) (by omega)
  have upper := bounded (iterateStep step initial (height + 1))
  omega

/-- A product's rank is additive; its height is the sum of component heights. -/
theorem product_rank_bounded {α β : Type}
    (ra : α → Nat) (rb : β → Nat) (ha hb : Nat)
    (ba : ∀ x, ra x ≤ ha) (bb : ∀ y, rb y ≤ hb) (x : α × β) :
    ra x.1 + rb x.2 ≤ ha + hb := by
  have := ba x.1
  have := bb x.2
  omega

/-- A finite function table carries one codomain rank per domain element. -/
def tableRank {α : Type} (rank : α → Nat) : List α → Nat
  | [] => 0
  | x :: xs => rank x + tableRank rank xs

theorem table_rank_bounded {α : Type} (rank : α → Nat) (height : Nat)
    (bounded : ∀ x, rank x ≤ height) (values : List α) :
    tableRank rank values ≤ values.length * height := by
  induction values with
  | nil => simp [tableRank]
  | cons x xs ih =>
    have hx := bounded x
    simp only [tableRank, List.length_cons, Nat.succ_mul]
    omega

/-- Pointwise rank order is preserved by summing a finite function table. -/
theorem function_table_rank_mono {α β : Type} (rank : β → Nat)
    (f g : α → β) (domain : List α)
    (ordered : ∀ x, x ∈ domain → rank (f x) ≤ rank (g x)) :
    tableRank rank (domain.map f) ≤ tableRank rank (domain.map g) := by
  induction domain with
  | nil => simp [tableRank]
  | cons x xs ih =>
    have head := ordered x (by simp)
    have tail := ih (fun y hy => ordered y (by simp [hy]))
    simp only [List.map_cons, tableRank]
    omega

/-- A changed point in a monotone finite function table increases its rank. -/
theorem function_table_rank_strict {α β : Type} (rank : β → Nat)
    (f g : α → β) (domain : List α)
    (ordered : ∀ x, x ∈ domain → rank (f x) ≤ rank (g x))
    (changed : ∃ x, x ∈ domain ∧ rank (f x) < rank (g x)) :
    tableRank rank (domain.map f) < tableRank rank (domain.map g) := by
  induction domain with
  | nil => obtain ⟨x, hx, _⟩ := changed; simp at hx
  | cons x xs ih =>
    have head := ordered x (by simp)
    have tailOrder : ∀ y, y ∈ xs → rank (f y) ≤ rank (g y) :=
      fun y hy => ordered y (by simp [hy])
    obtain ⟨y, hy, hstrict⟩ := changed
    rcases List.mem_cons.mp hy with heq | hmem
    · subst y
      have tail := function_table_rank_mono rank f g xs tailOrder
      simp only [List.map_cons, tableRank]
      omega
    · have tail := ih tailOrder ⟨y, hmem, hstrict⟩
      simp only [List.map_cons, tableRank]
      omega

/-- A finite relation is a Boolean table over its admitted tuple universe. -/
def booleanRank : {n : Nat} → (Fin n → Bool) → Nat
  | 0, _ => 0
  | n + 1, f => (if f 0 then 1 else 0) + booleanRank (fun i : Fin n => f i.succ)

theorem boolean_rank_bounded {n : Nat} (f : Fin n → Bool) :
    booleanRank f ≤ n := by
  induction n with
  | zero => simp [booleanRank]
  | succ n ih =>
    have h := ih (fun i => f i.succ)
    simp only [booleanRank]
    split <;> omega

theorem boolean_rank_mono {n : Nat} (f g : Fin n → Bool)
    (included : ∀ i, f i = true → g i = true) :
    booleanRank f ≤ booleanRank g := by
  induction n with
  | zero => simp [booleanRank]
  | succ n ih =>
    have h := ih (fun i => f i.succ) (fun i => g i.succ)
      (fun i => included i.succ)
    have h0 := included 0
    simp only [booleanRank]
    cases hf : f 0 <;> cases hg : g 0 <;> simp [hf, hg] at * <;> omega

theorem boolean_rank_strict {n : Nat} (f g : Fin n → Bool)
    (included : ∀ i, f i = true → g i = true)
    (changed : ∃ i, f i = false ∧ g i = true) :
    booleanRank f < booleanRank g := by
  induction n with
  | zero => obtain ⟨i, _⟩ := changed; exact Fin.elim0 i
  | succ n ih =>
    obtain ⟨i, hi⟩ := changed
    cases i using Fin.cases with
    | zero =>
      have h := boolean_rank_mono (fun i : Fin n => f i.succ)
        (fun i => g i.succ) (fun i => included i.succ)
      simp only [booleanRank]
      simp [hi.1, hi.2]
      omega
    | succ i =>
      have h := ih (fun i => f i.succ) (fun i => g i.succ)
        (fun i => included i.succ) ⟨i, hi⟩
      have h0 := included 0
      simp only [booleanRank]
      cases hf : f 0 <;> cases hg : g 0 <;> simp [hf, hg] at * <;> omega

/-- An inflationary native relation step stabilizes within its tuple count.
    Monotonicity of each compiled primitive is a separate compiler premise. -/
theorem finite_relation_stabilizes {n : Nat}
    (step : (Fin n → Bool) → (Fin n → Bool)) (initial : Fin n → Bool)
    (inflationary : ∀ f i, f i = true → step f i = true) :
    ∃ k, k ≤ n ∧ step (iterateStep step initial k) = iterateStep step initial k := by
  apply bounded_rank_stabilizes step initial booleanRank n boolean_rank_bounded
  intro f different
  apply boolean_rank_strict f (step f) (inflationary f)
  apply Classical.byContradiction
  intro unchanged
  apply different
  funext i
  cases hf : f i <;> cases hg : step f i
  · rfl
  · exact False.elim (unchanged ⟨i, hf, hg⟩)
  · have := inflationary f i hf; simp [hg] at this
  · rfl

/-- A monotone step iterated from bottom produces an ascending orbit. -/
theorem bottom_orbit_ascending {α : Type} (le : α → α → Prop)
    (step : α → α) (bottom : α)
    (least : ∀ x, le bottom x)
    (mono : ∀ x y, le x y → le (step x) (step y)) (n : Nat) :
    le (iterateStep step bottom n) (iterateStep step bottom (n + 1)) := by
  induction n with
  | zero => exact least (step bottom)
  | succ n ih =>
    exact mono (iterateStep step bottom n) (iterateStep step bottom (n + 1)) ih

/-- Once a Kleene orbit is stationary, every later iterate is identical. -/
theorem stationary_tail {α : Type} (step : α → α) (initial : α) (n : Nat)
    (fixed : step (iterateStep step initial n) = iterateStep step initial n)
    (extra : Nat) :
    iterateStep step initial (n + extra) = iterateStep step initial n := by
  induction extra with
  | zero => simp
  | succ extra ih =>
    change step (iterateStep step initial (n + extra)) = iterateStep step initial n
    rw [ih]
    exact fixed

/-- Monotone iteration from bottom need not be globally inflationary. Only
    strict rank growth on its own orbit is required for full-height unrolling. -/
theorem bounded_orbit_height_fixed {α : Type} (step : α → α) (initial : α)
    (rank : α → Nat) (height : Nat)
    (bounded : ∀ n, rank (iterateStep step initial n) ≤ height)
    (progress : ∀ n, step (iterateStep step initial n) ≠ iterateStep step initial n →
      rank (iterateStep step initial n) < rank (iterateStep step initial (n + 1))) :
    step (iterateStep step initial height) = iterateStep step initial height := by
  have stationary : ∃ n, n ≤ height ∧
      step (iterateStep step initial n) = iterateStep step initial n := by
    apply Classical.byContradiction
    intro h
    have moving : ∀ n, n ≤ height →
        step (iterateStep step initial n) ≠ iterateStep step initial n := by
      intro n hn heq
      exact h ⟨n, hn, heq⟩
    have climbing : ∀ n, n ≤ height + 1 → n ≤ rank (iterateStep step initial n) := by
      intro n
      induction n with
      | zero => intro _; omega
      | succ n ih =>
        intro hn
        have old := ih (by omega)
        have incr := progress n (moving n (by omega))
        omega
    have lower := climbing (height + 1) (by omega)
    have upper := bounded (height + 1)
    omega
  obtain ⟨n, hn, hfixed⟩ := stationary
  have tail := stationary_tail step initial n hfixed (height - n)
  have index : n + (height - n) = height := by omega
  rw [index] at tail
  rw [tail]
  exact hfixed

/-- Every approximation from bottom is below every fixed point. Together
    with full-height stationarity this establishes leastness, without comparing
    runtime function identities or sampling only observed arguments. -/
theorem bottom_iterate_le_fixed {α : Type} (le : α → α → Prop)
    (step : α → α) (bottom value : α)
    (least : ∀ x, le bottom x)
    (mono : ∀ x y, le x y → le (step x) (step y))
    (fixed : step value = value) (n : Nat) :
    le (iterateStep step bottom n) value := by
  induction n with
  | zero => exact least value
  | succ n ih =>
    simpa only [iterateStep, fixed] using mono (iterateStep step bottom n) value ih

/-- Combines full-height stationarity and leastness. The caller must supply
    bounded rank and strict progress for the admitted semantics, rather than
    treating a runtime budget or a sampled function table as that proof. -/
theorem bounded_bottom_least_fixed {α : Type} (le : α → α → Prop)
    (step : α → α) (bottom : α) (rank : α → Nat) (height : Nat)
    (least : ∀ x, le bottom x)
    (mono : ∀ x y, le x y → le (step x) (step y))
    (bounded : ∀ n, rank (iterateStep step bottom n) ≤ height)
    (progress : ∀ n, step (iterateStep step bottom n) ≠ iterateStep step bottom n →
      rank (iterateStep step bottom n) < rank (iterateStep step bottom (n + 1))) :
    step (iterateStep step bottom height) = iterateStep step bottom height ∧
      ∀ value, step value = value → le (iterateStep step bottom height) value := by
  constructor
  · exact bounded_orbit_height_fixed step bottom rank height bounded progress
  · intro value fixed
    exact bottom_iterate_le_fixed le step bottom value least mono fixed height

/-- Rank of an exhaustively indexed table; no observed-input sampling. -/
def indexedRank {α : Type} (rank : α → Nat) : {n : Nat} → (Fin n → α) → Nat
  | 0, _ => 0
  | n + 1, f => rank (f 0) + indexedRank rank (fun i : Fin n => f i.succ)

theorem indexed_rank_bounded {α : Type} (rank : α → Nat) (height : Nat)
    (bounded : ∀ x, rank x ≤ height) {n : Nat} (f : Fin n → α) :
    indexedRank rank f ≤ n * height := by
  induction n with
  | zero => simp [indexedRank]
  | succ n ih =>
    have head := bounded (f 0)
    have tail := ih (fun i => f i.succ)
    simp only [indexedRank, Nat.succ_mul]
    omega

theorem indexed_rank_mono {α : Type} (rank : α → Nat) {n : Nat}
    (f g : Fin n → α) (ordered : ∀ i, rank (f i) ≤ rank (g i)) :
    indexedRank rank f ≤ indexedRank rank g := by
  induction n with
  | zero => simp [indexedRank]
  | succ n ih =>
    have head := ordered 0
    have tail := ih (fun i => f i.succ) (fun i => g i.succ) (fun i => ordered i.succ)
    simp only [indexedRank]
    omega

theorem indexed_rank_strict {α : Type} (rank : α → Nat) {n : Nat}
    (f g : Fin n → α) (ordered : ∀ i, rank (f i) ≤ rank (g i))
    (changed : ∃ i, rank (f i) < rank (g i)) :
    indexedRank rank f < indexedRank rank g := by
  induction n with
  | zero => obtain ⟨i, _⟩ := changed; exact Fin.elim0 i
  | succ n ih =>
    obtain ⟨i, h⟩ := changed
    cases i using Fin.cases with
    | zero =>
      have tail := indexed_rank_mono rank (fun i : Fin n => f i.succ)
        (fun i => g i.succ) (fun i => ordered i.succ)
      simp only [indexedRank]
      omega
    | succ i =>
      have head := ordered 0
      have tail := ih (fun i => f i.succ) (fun i => g i.succ)
        (fun i => ordered i.succ) ⟨i, h⟩
      simp only [indexedRank]
      omega

/-- Finite pointwise lattices. A relation is `table (d^arity) truth`;
    an arrow adds a table covering EVERY semantic input. Supplying that width
    from the concrete type cardinality requires an enumeration/encoding bridge. -/
inductive FiniteShape where
  | truth
  | table (width : Nat) (output : FiniteShape)

namespace FiniteShape

def Value : FiniteShape → Type
  | .truth => Bool
  | .table width output => Fin width → Value output

def height : FiniteShape → Nat
  | .truth => 1
  | .table width output => width * height output

def bottom : (shape : FiniteShape) → Value shape
  | .truth => false
  | .table _ output => fun _ => bottom output

def included : (shape : FiniteShape) → Value shape → Value shape → Prop
  | .truth, f, g => (f : Bool) = true → (g : Bool) = true
  | .table _ output, f, g => ∀ i, included output (f i) (g i)

def rank : (shape : FiniteShape) → Value shape → Nat
  | .truth, f => match (f : Bool) with | false => 0 | true => 1
  | .table _ output, f => indexedRank (rank output) f

theorem rank_bounded (shape : FiniteShape) (f : Value shape) : rank shape f ≤ height shape := by
  induction shape with
  | truth => cases f <;> simp [rank, height]
  | table width output ih => exact indexed_rank_bounded (rank output) (height output) ih f

theorem rank_mono (shape : FiniteShape) (f g : Value shape)
    (ordered : included shape f g) : rank shape f ≤ rank shape g := by
  induction shape with
  | truth =>
    change ((f : Bool) = true → (g : Bool) = true) at ordered
    cases f <;> cases g
    · simp [rank]
    · simp [rank]
    · exact False.elim (Bool.noConfusion (ordered rfl))
    · simp [rank]
  | table width output ih => exact indexed_rank_mono (rank output) f g (fun i => ih (f i) (g i) (ordered i))

theorem rank_strict (shape : FiniteShape) (f g : Value shape)
    (ordered : included shape f g) (different : f ≠ g) : rank shape f < rank shape g := by
  induction shape with
  | truth =>
    change ((f : Bool) = true → (g : Bool) = true) at ordered
    change (f : Bool) ≠ (g : Bool) at different
    cases f <;> cases g
    · exact False.elim (different rfl)
    · simp [rank]
    · exact False.elim (Bool.noConfusion (ordered rfl))
    · exact False.elim (different rfl)
  | table width output ih =>
    apply indexed_rank_strict (rank output) f g (fun i => rank_mono output (f i) (g i) (ordered i))
    classical
    have changed : ∃ i, f i ≠ g i := by
      apply Classical.byContradiction
      intro h
      apply different
      funext i
      exact Classical.byContradiction (fun hi => h ⟨i, hi⟩)
    obtain ⟨i, hi⟩ := changed
    exact ⟨i, ih (f i) (g i) (ordered i) hi⟩

theorem bottom_least (shape : FiniteShape) (f : Value shape) : included shape (bottom shape) f := by
  induction shape with
  | truth => simp [included, bottom]
  | table width output ih => exact fun i => ih (f i)

/-- Discharges the abstract bounded-rank/progress premises for every nested
    finite table. Concrete descriptor interpretation and rule execution remain
    distinct refinement obligations. No resource budget is a semantic premise. -/
theorem full_height_least_fixed (shape : FiniteShape) (step : Value shape → Value shape)
    (mono : ∀ f g, included shape f g → included shape (step f) (step g)) :
    step (iterateStep step (bottom shape) (height shape)) = iterateStep step (bottom shape) (height shape) ∧
      ∀ f, step f = f → included shape (iterateStep step (bottom shape) (height shape)) f := by
  apply bounded_bottom_least_fixed (included shape) step (bottom shape) (rank shape) (height shape)
    (bottom_least shape) mono
  · exact fun n => rank_bounded shape (iterateStep step (bottom shape) n)
  · intro n different
    apply rank_strict shape _ _
    · exact bottom_orbit_ascending (included shape) step (bottom shape) (bottom_least shape) mono n
    · change iterateStep step (bottom shape) n ≠ step (iterateStep step (bottom shape) n)
      exact Ne.symm different

end FiniteShape

/-- Exhaustive tables over a complete finite codomain list. -/
def enumerateTables {α : Type} (outputs : List α) : (n : Nat) → List (Fin n → α)
  | 0 => [fun i => Fin.elim0 i]
  | n + 1 => outputs.flatMap (fun head =>
      (enumerateTables outputs n).map (fun tail => fun i => Fin.cases head tail i))

theorem table_product_length {α β γ : Type} (heads : List α) (tails : List β)
    (combine : α → β → γ) :
    (heads.flatMap (fun head => tails.map (combine head))).length = heads.length * tails.length := by
  induction heads with
  | nil => simp
  | cons x xs ih => simp only [List.flatMap_cons, List.length_append, List.length_map, List.length_cons, ih, Nat.succ_mul]; omega

theorem enumerate_tables_length {α : Type} (outputs : List α) (n : Nat) :
    (enumerateTables outputs n).length = outputs.length ^ n := by
  induction n with
  | zero => simp [enumerateTables]
  | succ n ih =>
    rw [enumerateTables, table_product_length, ih, Nat.pow_succ, Nat.mul_comm]

theorem enumerate_tables_complete {α : Type} (outputs : List α)
    (complete : ∀ x, x ∈ outputs) (n : Nat) (f : Fin n → α) :
    f ∈ enumerateTables outputs n := by
  induction n with
  | zero =>
    have eq : f = (fun i => Fin.elim0 i) := by funext i; exact Fin.elim0 i
    simp [enumerateTables, eq]
  | succ n ih =>
    apply List.mem_flatMap.mpr
    refine ⟨f 0, complete (f 0), ?_⟩
    apply List.mem_map.mpr
    refine ⟨(fun i => f i.succ), ih (fun i => f i.succ), ?_⟩
    funext i
    cases i using Fin.cases <;> rfl

/-- All admitted tuples, including the single empty tuple when arity is zero. -/
theorem tuple_enumeration_length (atoms arity : Nat) :
    (enumerateTables (List.finRange atoms) arity).length = atoms ^ arity := by
  rw [enumerate_tables_length, List.length_finRange]

theorem tuple_enumeration_complete (atoms arity : Nat) (row : Fin arity → Fin atoms) :
    row ∈ enumerateTables (List.finRange atoms) arity :=
  enumerate_tables_complete (List.finRange atoms) List.mem_finRange arity row

theorem empty_domain_positive_arity (arity : Nat) :
    (enumerateTables (List.finRange 0) (arity + 1)).length = 0 := by
  rw [tuple_enumeration_length]
  simp

namespace FiniteShape

def cardinality : FiniteShape → Nat
  | .truth => 2
  | .table width output => cardinality output ^ width

def enumerate : (shape : FiniteShape) → List (Value shape)
  | .truth => [false, true]
  | .table width output => enumerateTables (enumerate output) width

theorem enumeration_length (shape : FiniteShape) : (enumerate shape).length = cardinality shape := by
  induction shape with
  | truth => rfl
  | table width output ih =>
    change (enumerateTables (enumerate output) width).length = cardinality output ^ width
    rw [enumerate_tables_length, ih]

theorem enumeration_complete (shape : FiniteShape) (f : Value shape) : f ∈ enumerate shape := by
  induction shape with
  | truth =>
    cases f
    · exact .head ..
    · exact .tail _ (.head ..)
  | table width output ih => exact enumerate_tables_complete (enumerate output) ih width f

/-- An arrow's complete-input table is indexed by a covering enumeration,
    rather than a sampled argument list. Completeness makes this encoding
    injective; duplicate entries, if any, only make the bound conservative. -/
def encodeArrow (input output : FiniteShape) (f : Value input → Value output) :
    Fin (cardinality input) → Value output :=
  fun i => f ((enumerate input).get ⟨i.val, by rw [enumeration_length]; exact i.isLt⟩)

theorem arrow_encoding_injective (input output : FiniteShape) (f g : Value input → Value output)
    (equal : encodeArrow input output f = encodeArrow input output g) : f = g := by
  funext x
  obtain ⟨i, hi⟩ := List.mem_iff_get.mp (enumeration_complete input x)
  have index : i.val < cardinality input := by rw [← enumeration_length]; exact i.isLt
  have atIndex := congrFun equal (⟨i.val, index⟩ : Fin (cardinality input))
  simpa only [encodeArrow, hi] using atIndex

end FiniteShape

/-- Abstract descriptor signatures. Native scalar/domain-list interpretation
    and compiler translation still need their own representation relation. -/
inductive FiniteSignature where
  | relation (distinctAtoms arity : Nat)
  | arrow (input output : FiniteSignature)

namespace FiniteSignature

def cardinality : FiniteSignature → Nat
  | .relation atoms arity => 2 ^ (atoms ^ arity)
  | .arrow input output => cardinality output ^ cardinality input

def height : FiniteSignature → Nat
  | .relation atoms arity => atoms ^ arity
  | .arrow input output => cardinality input * height output

def shape : FiniteSignature → FiniteShape
  | .relation atoms arity => .table (atoms ^ arity) .truth
  | .arrow input output => .table (FiniteShape.cardinality (shape input)) (shape output)

theorem shape_cardinality (signature : FiniteSignature) :
    FiniteShape.cardinality (shape signature) = cardinality signature := by
  induction signature with
  | relation atoms arity => rfl
  | arrow input output ihInput ihOutput => simp only [shape, FiniteShape.cardinality, cardinality, ihInput, ihOutput]

theorem shape_height (signature : FiniteSignature) :
    FiniteShape.height (shape signature) = height signature := by
  induction signature with
  | relation atoms arity => simp [shape, FiniteShape.height, height]
  | arrow input output ihInput ihOutput => simp only [shape, FiniteShape.height, height, shape_cardinality, ihOutput]

/-- The native exact height formula suffices for monotone steps on the
    exhaustively represented signature semantics, including nested arrows. -/
theorem signature_height_least_fixed (signature : FiniteSignature)
    (step : FiniteShape.Value (shape signature) → FiniteShape.Value (shape signature))
    (mono : ∀ f g, FiniteShape.included (shape signature) f g →
      FiniteShape.included (shape signature) (step f) (step g)) :
    step (iterateStep step (FiniteShape.bottom (shape signature)) (height signature)) =
      iterateStep step (FiniteShape.bottom (shape signature)) (height signature) ∧
    ∀ f, step f = f → FiniteShape.included (shape signature)
      (iterateStep step (FiniteShape.bottom (shape signature)) (height signature)) f := by
  rw [← shape_height]
  exact FiniteShape.full_height_least_fixed (shape signature) step mono

end FiniteSignature

end Ascent
