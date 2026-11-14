-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Init.Omega

/-! Projection of Gerbil raw-table-new: fresh backing storage, no entries,
retained hash/test/seed policy. Not extraction of the runtime table source. -/
namespace Ascent.EmptyTableFactory

structure Table where
  policy : Nat
  entries : Nat → Option Nat

def emptyFrom (owner : Table) : Table :=
  ⟨owner.policy, fun _ => none⟩

theorem empty_membership (owner : Table) (key : Nat) :
    (emptyFrom owner).entries key = none := rfl

theorem policy_preserved (owner : Table) :
    (emptyFrom owner).policy = owner.policy := rfl

def put (table : Table) (key value : Nat) : Table :=
  ⟨table.policy, fun k => if k = key then some value else table.entries k⟩

abbrev Store := Nat → Table

def allocate (store : Store) (fresh : Nat) (owner : Table) : Store :=
  fun address => if address = fresh then emptyFrom owner else store address

def write (store : Store) (address key value : Nat) : Store :=
  fun i => if i = address then put (store i) key value else store i

/-- Freshness is an explicit allocator obligation, checked against the real
public constructor by native storage-isolation controls. -/
theorem allocate_preserves_owner (store : Store) (owner fresh : Nat)
    (separate : owner ≠ fresh) :
    allocate store fresh (store owner) owner = store owner := by
  simp [allocate, separate]

theorem write_preserves_other (store : Store) (address other key value : Nat)
    (separate : other ≠ address) :
    write store address key value other = store other := by
  simp [write, separate]

/-- Replacing one empty extensional table by another does not change a
consumer that depends only on its membership map. This premise does not
claim the hash runtime or arbitrary callbacks are source-verified. -/
theorem empty_consumer_equivalence
    (consume : (Nat → Option Nat) → Nat) (first second : Table) :
    consume (emptyFrom first).entries = consume (emptyFrom second).entries := rfl

/-- Performance improvement requires measured constructor costs; it is not
a consequence of extensional table equivalence. -/
theorem three_factory_budget (ordinary reused rest : Nat)
    (cheaper : reused < ordinary) :
    rest + 3*reused < rest + 3*ordinary := by omega

end Ascent.EmptyTableFactory
