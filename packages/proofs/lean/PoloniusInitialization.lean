-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Polonius initialization uses two instances of the same finite-path law:
assigned seeds blocked by moves, and moved seeds blocked by assignments.
The blocker is tested at the successor, not at the seed. These theorems concern
relation semantics; they do not prove native index extraction or memory bounds. -/
namespace Ascent.PoloniusInitialization

inductive Flow (seed : P → Prop) (edge : P → P → Prop) (blocked : P → Prop) : P → Prop
  | seed {p} : seed p → Flow seed edge blocked p
  | step {p q} : Flow seed edge blocked p → edge p q → ¬ blocked q → Flow seed edge blocked q

inductive ReachAvoid (edge : P → P → Prop) (blocked : P → Prop) (start : P) : P → Prop
  | refl : ReachAvoid edge blocked start start
  | step {p q} : ReachAvoid edge blocked start p → edge p q → ¬ blocked q →
      ReachAvoid edge blocked start q

/-- Every derived exit fact has a finite CFG witness beginning at a seed.
Only propagated successors must avoid the blocker. Cycles create no facts
without a seed, and do not require an artificial generation bound. -/
theorem flow_iff_seed_path {seed : P → Prop} {edge : P → P → Prop}
    {blocked : P → Prop} {q : P} :
    Flow seed edge blocked q ↔ ∃ p, seed p ∧ ReachAvoid edge blocked p q := by
  constructor
  · intro h
    induction h with
    | seed h => exact ⟨_, h, .refl⟩
    | step _ edge absent ih =>
      obtain ⟨p, initial, path⟩ := ih
      exact ⟨p, initial, .step path edge absent⟩
  · rintro ⟨p, initial, path⟩
    induction path with
    | refl => exact .seed initial
    | step _ edge absent ih => exact .step ih edge absent

/-- A blocker at the target stops propagation, but does not erase a seed
at that same target. Assignment and move seeds are independent may facts. -/
theorem blocked_target_iff_seed {seed : P → Prop} {edge : P → P → Prop}
    {blocked : P → Prop} {q : P} (block : blocked q) :
    Flow seed edge blocked q ↔ seed q := by
  constructor
  · intro h
    cases h with
    | seed initial => exact initial
    | step _ _ absent => exact False.elim (absent block)
  · exact Flow.seed

/-- Seed-free strongly connected regions cannot invent initialization. -/
theorem no_seeds_no_flow {edge : P → P → Prop} {blocked : P → Prop} {q : P} :
    ¬ Flow (fun _ => False) edge blocked q := by
  intro h
  obtain ⟨_, impossible, _⟩ := flow_iff_seed_path.mp h
  exact impossible

/-- Enlarging the move/assignment blocker can only remove propagated facts.
This direction is essential when source transactions add kill facts. -/
theorem blockers_antitone {seed : P → Prop} {edge : P → P → Prop}
    {small large : P → Prop} (includes : ∀ p, small p → large p) {q : P}
    (h : Flow seed edge large q) : Flow seed edge small q := by
  induction h with
  | seed initial => exact .seed initial
  | step _ edge absent ih =>
    exact .step ih edge (fun blocked => absent (includes _ blocked))
end Ascent.PoloniusInitialization
