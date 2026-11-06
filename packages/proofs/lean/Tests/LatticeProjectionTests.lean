-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LatticeProjection
open Ascent.LatticeProjection

def minJoin : JoinLaws Nat := ⟨min,Nat.min_assoc,Nat.min_comm,Nat.min_self⟩
def seed : Store Bool Nat := fun key => some (if key then 8 else 9)
def events : List (Bool × Nat) := [(false,7),(false,2),(true,5),(false,4)]
example : stage min seed events false = some 2 := by decide
example : stage min seed events true = some 5 := by decide
example : stage min seed events.reverse false = some 2 := by decide
-- Abstract growth is not inclusion of currently materialized tuple observations.
example : Below minJoin 9 2 ∧ gamma seed (false,9) ∧
    ¬ gamma (stage min seed events) (false,9) := by
  unfold Below gamma
  decide
example : replaceRows [(false,9),(true,8)] [(false,2)] = [(false,2),(true,8)] := by decide
example : (false,9) ∉ replaceRows [(false,9)] [(false,2)] := by decide
example : (encode [false] true).dropLast = [false] ∧
    (encode [false] true).getLast? = some true := by decide

#print axioms update_hit
#print axioms update_other
#print axioms gamma_unique
#print axioms replaced_row_absent
#print axioms join_above_left
#print axioms below_trans
#print axioms update_inflationary
#print axioms update_twice
#print axioms store_below_trans
#print axioms stage_inflationary
#print axioms stage_untouched
#print axioms publish_exact
#print axioms publish_stage_exact
#print axioms replacement_member
#print axioms old_key_removed
#print axioms encode_key
#print axioms encode_value
