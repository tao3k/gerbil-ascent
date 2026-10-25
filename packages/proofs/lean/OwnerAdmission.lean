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

-- These costs count resource files visited/copied, not elapsed time or bytes
-- allocated by the SDK, compiler, filesystem, SHA implementation or VM itself.
-- A captured package never authorizes a subsequent VM without current checks.
def snapshotAdmission (sameProcess currentBytes : Bool) : Bool :=
  sameProcess && currentBytes

theorem changed_snapshot_refuses (sameProcess : Bool) :
    snapshotAdmission sameProcess false = false := by simp [snapshotAdmission]

theorem inherited_snapshot_refuses (currentBytes : Bool) :
    snapshotAdmission false currentBytes = false := by simp [snapshotAdmission]

def releaseResources (sameProcess hostLease nativeLease : Bool) : Bool :=
  sameProcess && !hostLease && !nativeLease

theorem host_lease_retains_files (sameProcess nativeLease : Bool) :
    releaseResources sameProcess true nativeLease = false := by simp [releaseResources]

theorem native_lease_retains_files (sameProcess hostLease : Bool) :
    releaseResources sameProcess hostLease true = false := by simp [releaseResources]

theorem inherited_lease_cannot_delete (hostLease nativeLease : Bool) :
    releaseResources false hostLease nativeLease = false := by simp [releaseResources]

-- One capture plus additional independent pools, each with a fresh full check.
def uncapturedCopies (additional files : Nat) : Nat := (additional + 1) * files
def capturedCopies (files : Nat) : Nat := files
def capturedChecks (additional files : Nat) : Nat := 3 * files + (additional + 1) * files

theorem file_copy_savings (additional files : Nat) :
    uncapturedCopies additional files = capturedCopies files + additional * files := by
  simp [uncapturedCopies, capturedCopies, Nat.add_mul, Nat.add_comm]

theorem every_pool_retains_full_check (additional files : Nat) :
    capturedChecks additional files = 3 * files + uncapturedCopies additional files := by rfl

-- Exact source bindings below detect drift; they are not a proof of the Rust,
-- Scheme, MOP, atomic memory model or host compiler semantics.
def controlRustSource : String :=
  "//! One admission transition shared by linked and exec-isolated Rust owners.\n#[derive(Clone, Copy, Debug, Eq, PartialEq)]\npub(crate) struct State {\n    pub(crate) work: usize,\n    pub(crate) maximum: usize,\n    pub(crate) accepted: bool,\n    pub(crate) suspended: bool,\n}\nimpl State {\n    // BEGIN EXECUTION ADMISSION\n    pub(crate) fn advance(&mut self, work: i64, interruption: impl FnOnce(bool) -> i32) -> i32 {\n        if work == -2 {\n            self.suspended = true;\n            return 0;\n        }\n        if work == -3 {\n            self.suspended = false;\n            return 0;\n        }\n        if self.suspended {\n            return 0;\n        }\n        let interrupted = interruption(self.accepted);\n        if interrupted != 0 {\n            return interrupted;\n        }\n        if self.accepted {\n            return 0;\n        }\n        if work == -1 {\n            self.accepted = true;\n            return 0;\n        }\n        let Ok(work) = usize::try_from(work) else {\n            return 3;\n        };\n        let Some(work) = self.work.checked_add(work) else {\n            return 3;\n        };\n        if work > self.maximum {\n            return 3;\n        }\n        self.work = work;\n        0\n    }\n    // END EXECUTION ADMISSION\n}\n#[cfg(test)]\n#[path = \"../tests/unit/control_state.rs\"]\nmod tests;\n"

def projectionSchemeSource : String :=
  ";;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later\n;;; Reuse only private projection object graphs, never a validation result or wire value.\n(import (only-in :clan/poo/object .ref)\n        (only-in :gerbil-ascent/program/objects gerbil-ascent-program)\n        (only-in :gerbil-ascent/program/types gerbil-ascent-relation-with-rows\n                 gerbil-ascent-projection-tree-current? gerbil-ascent-check-projection-program))\n(export ascent-projection-program)\n(defstruct projection-cache (generation relations rules handles limits program) final: #t)\n(def (same-references? left right)\n  (cond ((null? left) (null? right))\n        ((null? right) #f)\n        (else (and (eq? (car left) (car right))\n                   (same-references? (cdr left) (cdr right))))))\n(def (fresh-program original sources)\n  (gerbil-ascent-program\n    (map (lambda (relation)\n      (let (source (assq (.ref relation 'name) sources))\n        (if source (gerbil-ascent-relation-with-rows relation (cdr source)) relation)))\n      (.ref original 'relations))\n    (.ref original 'rules) (.ref original 'max-input-facts)\n    (.ref original 'max-derived-facts) (.ref original 'max-output-facts)\n    (.ref original 'source-handles)))\n(def (ascent-projection-program original sources generation previous)\n  (if (not (gerbil-ascent-projection-tree-current? original))\n    (values (fresh-program original sources) #f)\n    (let ((relations (.ref original 'relations)) (rules (.ref original 'rules))\n          (handles (.ref original 'source-handles))\n          (limits (list (.ref original 'max-input-facts) (.ref original 'max-derived-facts)\n                        (.ref original 'max-output-facts))))\n      (if (and previous (= generation (projection-cache-generation previous))\n               (same-references? relations (projection-cache-relations previous))\n               (eq? rules (projection-cache-rules previous))\n               (equal? handles (projection-cache-handles previous))\n               (equal? limits (projection-cache-limits previous)))\n        (values (gerbil-ascent-check-projection-program (projection-cache-program previous)) previous)\n        (let (program (fresh-program original sources))\n          (values program (make-projection-cache generation (map identity relations) rules\n                            (map identity handles) limits program)))))))\n"

def packageRustSource : String :=
  "//! Caller-owned immutable input bytes; every new VM admission still reverifies.\nuse gerbil_ascent::Result;\nuse gerbil_scheme_python::{PackageManifest, VerifiedPackage};\nuse std::{path::Path, sync::Arc};\n\n/// Captured library resources shared by independent VM pools, never Scheme state.\n/// The caller and actual native owners jointly retain the private resource lease.\n#[derive(Clone)]\npub struct InstancePackage {\n    resources: Option<Arc<tempfile::TempDir>>,\n    parent: u32,\n    manifest: Arc<PackageManifest>,\n}\nimpl InstancePackage {\n    /// Capture the library-built package without compiling user code.\n    /// # Errors\n    /// Rejects changed, missing or aliased resources before capturing any VM.\n    pub fn bundled() -> Result<Self> {\n        Self::open(env!(\"ASCENT_INSTANCE_PACKAGE\"))\n    }\n    /// Capture an installed package matching this library's compiled manifest.\n    /// # Errors\n    /// Rejects invalid resources and any source change during the verified copy.\n    pub fn open(root: impl AsRef<Path>) -> Result<Self> {\n        Self::capture(root.as_ref()).map(|(package, _)| package)\n    }\n    pub(super) fn capture(root: &Path) -> Result<(Self, VerifiedPackage)> {\n        let manifest = Arc::new(\n            PackageManifest::from_json(include_bytes!(concat!(\n                env!(\"OUT_DIR\"),\n                \"/instance_inventory.json\"\n            )))\n            .map_err(|e| crate::failure(&e.to_string()))?,\n        );\n        let package = manifest\n            .verify(root)\n            .map_err(|e| crate::failure(&e.to_string()))?;\n        let resources = Arc::new(\n            tempfile::Builder::new()\n                .prefix(&format!(\"ascent-resources-{}-\", std::process::id()))\n                .tempdir()\n                .map_err(|e| crate::failure(&e.to_string()))?,\n        );\n        let verified = package\n            .copy_to(resources.path())\n            .map_err(|e| crate::failure(&e.to_string()))?;\n        Ok((\n            Self {\n                resources: Some(resources),\n                parent: std::process::id(),\n                manifest,\n            },\n            verified,\n        ))\n    }\n    pub(super) fn resources(&self) -> Result<&Arc<tempfile::TempDir>> {\n        if self.parent != std::process::id() {\n            return Err(crate::failure(\n                \"forked package resources require exec before initialization\",\n            ));\n        }\n        self.resources.as_ref().ok_or(gerbil_ascent::Error::Closed)\n    }\n    pub(super) fn verify(&self) -> Result<VerifiedPackage> {\n        self.manifest\n            .verify(self.resources()?.path())\n            .map_err(|e| crate::failure(&e.to_string()))\n    }\n}\n\nimpl Drop for InstancePackage {\n    fn drop(&mut self) {\n        // A child inherited a process-local lease, not ownership of the parent's\n        // files. Never remove those files while the parent may still use them.\n        if self.parent == std::process::id() {\n            return;\n        }\n        if let Some(resources) = self.resources.take() {\n            std::mem::forget(resources);\n        }\n    }\n}\n\n#[cfg(test)]\n#[path = \"../../tests/unit/instance_package.rs\"]\nmod tests;\n"

def packageLifecycleRustSource : String :=
  "//! Initialize the canonical upstream image; all bindings execute on its owner.\nuse super::{InstancePackage, bridge_error};\nuse gerbil_ascent::Result;\nuse gerbil_scheme::instances::{\n    InstanceConfig, InstanceDispatcher, InstanceError, IsolatedProgram,\n};\nuse std::{\n    path::{Path, PathBuf},\n    sync::Arc,\n    time::Duration,\n};\npub(super) fn start(\n    owners: usize,\n    root: &Path,\n) -> Result<(gerbil_scheme::instances::InstancePool, PathBuf)> {\n    let (snapshot, package) = InstancePackage::capture(root)?;\n    start_verified(owners, &package, snapshot.resources()?)\n}\npub(super) fn start_snapshot(\n    owners: usize,\n    snapshot: &InstancePackage,\n) -> Result<(gerbil_scheme::instances::InstancePool, PathBuf)> {\n    // The snapshot retains bytes, not a previous verification decision.\n    start_verified(owners, &snapshot.verify()?, snapshot.resources()?)\n}\nfn start_verified(\n    owners: usize,\n    package: &gerbil_scheme_python::VerifiedPackage,\n    resources: &Arc<tempfile::TempDir>,\n) -> Result<(gerbil_scheme::instances::InstancePool, PathBuf)> {\n    // SAFETY: the build-owned image contains this exact Scheme archive and upstream adapter.\n    let program = unsafe {\n        IsolatedProgram::from_image(\n            package.root().join(\"_owners/ascent-instance.dylib\"),\n            c\"ascent_hybrid_call\",\n        )\n        .map_err(bridge_error)?\n        .with_exports(&[c\"ascent_hybrid_bind\", c\"ascent_hybrid_table\"])\n    };\n    let mut runtime = gerbil_scheme::instances::InstancePool::start(\n        &program,\n        InstanceConfig {\n            owners,\n            queue_capacity: 64,\n            maximum_request_bytes: 64 * 1024 * 1024,\n            maximum_reply_bytes: 64 * 1024 * 1024,\n            startup_timeout: Duration::from_mins(1),\n        },\n    )\n    .map_err(bridge_error)?;\n    if runtime.owners().iter().any(|r| r.processors != 1) {\n        return Err(crate::failure(\n            \"each instance VM must have exactly one processor\",\n        ));\n    }\n    runtime\n        .retain_owner_resource(resources)\n        .map_err(bridge_error)?;\n    Ok((runtime, package.root().join(\"_owners/lib\")))\n}\npub(super) fn bind(dispatcher: &InstanceDispatcher, index: usize, library: &Path) -> Result<()> {\n    let library = library\n        .to_str()\n        .ok_or_else(|| crate::failure(\"non-UTF8 instance resource path\"))?\n        .to_owned();\n    let bound = dispatcher\n        .submit_native_on(index, move |vm| {\n            let address = crate::ascent_hybrid_checkpoint as *const () as usize;\n            let (_, bytes) = num_bigint::BigInt::from(address).to_bytes_le();\n            let address = vm.big_integer(\n                &gerbil_scheme::BinaryInteger::new(false, bytes)\n                    .map_err(|_| InstanceError::InvalidConfig(\"callback address\"))?,\n            )?;\n            let library = vm.string(&library)?;\n            let input = vm.vector(&[&address, &library])?;\n            drop(vm.call_export(c\"ascent_hybrid_bind\", &input)?);\n            Ok(())\n        })\n        .map_err(bridge_error)?;\n    bound.wait(Duration::from_mins(1)).map_err(bridge_error)?;\n    Ok(())\n}\n"

end Ascent.OwnerAdmission
#print axioms Ascent.OwnerAdmission.local_cannot_publish
#print axioms Ascent.OwnerAdmission.original_cancel_refuses_even_with_delayed_mirror
#print axioms Ascent.OwnerAdmission.original_deadline_refuses
#print axioms Ascent.OwnerAdmission.accepted_publication_is_stable
#print axioms Ascent.OwnerAdmission.retired_notification_cannot_cancel_new_lease
#print axioms Ascent.OwnerAdmission.validation_and_wire_cost_retained
#print axioms Ascent.OwnerAdmission.reuse_removes_only_construction

#print axioms Ascent.OwnerAdmission.changed_snapshot_refuses
#print axioms Ascent.OwnerAdmission.inherited_snapshot_refuses
#print axioms Ascent.OwnerAdmission.host_lease_retains_files
#print axioms Ascent.OwnerAdmission.native_lease_retains_files
#print axioms Ascent.OwnerAdmission.inherited_lease_cannot_delete
#print axioms Ascent.OwnerAdmission.file_copy_savings
#print axioms Ascent.OwnerAdmission.every_pool_retains_full_check
