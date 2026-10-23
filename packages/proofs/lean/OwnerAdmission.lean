-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Caller publication authority is distinct from a child-local checkpoint.
The model assumes single-writer child state while the caller waits, and a
quiescent child while the caller publishes. Atomic/clock/FFI implementations
remain host premises; source render equality is checked separately. -/
namespace Ascent.OwnerAdmission
structure State where
  work : Nat
  maximum : Nat
  accepted : Bool
  suspended : Bool
  deriving DecidableEq, Repr

def advance (state : State) (delta : Int) (interruption wordMaximum : Nat) : Nat × State :=
  if delta = -2 then (0, { state with suspended := true })
  else if delta = -3 then (0, { state with suspended := false })
  else if state.suspended then (0, state)
  else if interruption ≠ 0 then (interruption, state)
  else if state.accepted then (0, state)
  else if delta = -1 then (0, { state with accepted := true })
  else if delta < 0 then (3, state)
  else if state.work + delta.toNat > state.maximum ∨ state.work + delta.toNat > wordMaximum then (3, state)
  else (0, { state with work := state.work + delta.toNat })

-- Interruption is supplied as zero once accepted, exactly as the runtime callback.
def childCheck (state : State) (delta : Int) (interruption wordMaximum : Nat) : Nat × State :=
  let answer := advance state delta interruption wordMaximum
  if !state.accepted && answer.2.accepted then (4, state) else answer

theorem local_cannot_publish (state : State) (delta : Int) (code cap : Nat)
    (notAccepted : state.accepted = false) :
    (childCheck state delta code cap).2.accepted = false := by
  simp only [childCheck, notAccepted, Bool.not_false, Bool.true_and]
  split <;> simp_all

def publish (originalCanceled originalExpired : Bool) (state : State) : Nat × State :=
  if state.accepted then (0, state)
  else if originalCanceled then (1, state)
  else if originalExpired then (2, state)
  else (0, { state with accepted := true })

theorem original_cancel_refuses_even_with_delayed_mirror (state : State)
    (notAccepted : state.accepted = false) (expired : Bool) :
    publish true expired state = (1, state) := by simp [publish, notAccepted]

theorem original_deadline_refuses (state : State) (notAccepted : state.accepted = false) :
    publish false true state = (2, state) := by simp [publish, notAccepted]

theorem accepted_publication_is_stable (state : State) (accepted : state.accepted = true)
    (canceled expired : Bool) : publish canceled expired state = (0, state) := by
  simp [publish, accepted]

-- The old notification retains its old lease identity. Delivery is serialized
-- against retirement by CancelWake's armed mutex, not a cross-process lock.
def notify (notification current : Nat) (canceled : Bool) : Bool :=
  if notification = current then true else canceled

theorem retired_notification_cannot_cancel_new_lease (old current : Nat)
    (different : old ≠ current) : notify old current false = false := by
  simp [notify, different]

-- Both paths run a new root check and wire projection. Only construction differs.
def projectionCost (reuse : Bool) (construction validation wire : Nat) : Nat :=
  (if reuse then 0 else construction) + validation + wire

theorem validation_and_wire_cost_retained (construction validation wire : Nat) :
    projectionCost true construction validation wire = validation + wire := by
  simp [projectionCost]

theorem reuse_removes_only_construction (construction validation wire : Nat) :
    projectionCost false construction validation wire =
      projectionCost true construction validation wire + construction := by
  simp [projectionCost]; omega

-- Exact source bindings below detect drift; they are not a proof of the Rust,
-- Scheme, MOP, atomic memory model or host compiler semantics.
def controlRustSource : String :=
  "//! One admission transition shared by linked and exec-isolated Rust owners.\n#[derive(Clone, Copy, Debug, Eq, PartialEq)]\npub(crate) struct State {\n    pub(crate) work: usize,\n    pub(crate) maximum: usize,\n    pub(crate) accepted: bool,\n    pub(crate) suspended: bool,\n}\nimpl State {\n    // BEGIN EXECUTION ADMISSION\n    pub(crate) fn advance(&mut self, work: i64, interruption: impl FnOnce(bool) -> i32) -> i32 {\n        if work == -2 {\n            self.suspended = true;\n            return 0;\n        }\n        if work == -3 {\n            self.suspended = false;\n            return 0;\n        }\n        if self.suspended {\n            return 0;\n        }\n        let interrupted = interruption(self.accepted);\n        if interrupted != 0 {\n            return interrupted;\n        }\n        if self.accepted {\n            return 0;\n        }\n        if work == -1 {\n            self.accepted = true;\n            return 0;\n        }\n        let Ok(work) = usize::try_from(work) else {\n            return 3;\n        };\n        let Some(work) = self.work.checked_add(work) else {\n            return 3;\n        };\n        if work > self.maximum {\n            return 3;\n        }\n        self.work = work;\n        0\n    }\n    // END EXECUTION ADMISSION\n}\n#[cfg(test)]\n#[path = \"../tests/unit/control_state.rs\"]\nmod tests;\n"

def projectionSchemeSource : String :=
  ";;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later\n;;; Reuse only private projection object graphs, never a validation result or wire value.\n(import (only-in :clan/poo/object .ref)\n        (only-in :gerbil-ascent/program/objects gerbil-ascent-program)\n        (only-in :gerbil-ascent/program/types gerbil-ascent-relation-with-rows\n                 gerbil-ascent-projection-tree-current? gerbil-ascent-check-projection-program))\n(export ascent-projection-program)\n(defstruct projection-cache (generation relations rules handles limits program) final: #t)\n(def (same-references? left right)\n  (cond ((null? left) (null? right))\n        ((null? right) #f)\n        (else (and (eq? (car left) (car right))\n                   (same-references? (cdr left) (cdr right))))))\n(def (fresh-program original sources)\n  (gerbil-ascent-program\n    (map (lambda (relation)\n      (let (source (assq (.ref relation 'name) sources))\n        (if source (gerbil-ascent-relation-with-rows relation (cdr source)) relation)))\n      (.ref original 'relations))\n    (.ref original 'rules) (.ref original 'max-input-facts)\n    (.ref original 'max-derived-facts) (.ref original 'max-output-facts)\n    (.ref original 'source-handles)))\n(def (ascent-projection-program original sources generation previous)\n  (if (not (gerbil-ascent-projection-tree-current? original))\n    (values (fresh-program original sources) #f)\n    (let ((relations (.ref original 'relations)) (rules (.ref original 'rules))\n          (handles (.ref original 'source-handles))\n          (limits (list (.ref original 'max-input-facts) (.ref original 'max-derived-facts)\n                        (.ref original 'max-output-facts))))\n      (if (and previous (= generation (projection-cache-generation previous))\n               (same-references? relations (projection-cache-relations previous))\n               (eq? rules (projection-cache-rules previous))\n               (equal? handles (projection-cache-handles previous))\n               (equal? limits (projection-cache-limits previous)))\n        (values (gerbil-ascent-check-projection-program (projection-cache-program previous)) previous)\n        (let (program (fresh-program original sources))\n          (values program (make-projection-cache generation (map identity relations) rules\n                            (map identity handles) limits program)))))))\n"

end Ascent.OwnerAdmission
#print axioms Ascent.OwnerAdmission.local_cannot_publish
#print axioms Ascent.OwnerAdmission.original_cancel_refuses_even_with_delayed_mirror
#print axioms Ascent.OwnerAdmission.original_deadline_refuses
#print axioms Ascent.OwnerAdmission.accepted_publication_is_stable
#print axioms Ascent.OwnerAdmission.retired_notification_cannot_cancel_new_lease
#print axioms Ascent.OwnerAdmission.validation_and_wire_cost_retained
#print axioms Ascent.OwnerAdmission.reuse_removes_only_construction
