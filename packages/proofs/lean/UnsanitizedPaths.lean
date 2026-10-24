-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std
/-! IRIS section 3.1 finite graph transfer. Source/sink labels and graph
extraction are caller premises; no program-security or CodeQL equivalence claim. -/
namespace Ascent.UnsanitizedPaths
variable {Vertex : Type}
inductive Walk (edge : Vertex → Vertex → Prop) : Vertex → Vertex → Prop
  | refl (v) : Walk edge v v
  | step {s x y} : Walk edge s x → edge x y → Walk edge s y
inductive CleanPath (edge : Vertex → Vertex → Prop) (allowed : Vertex → Prop) : Vertex → Vertex → Prop
  | refl {v} : allowed v → CleanPath edge allowed v v
  | step {s x y} : CleanPath edge allowed s x → edge x y → allowed y → CleanPath edge allowed s y
def filtered (edge : Vertex → Vertex → Prop) (allowed : Vertex → Prop) :=
  fun x y => edge x y ∧ allowed x ∧ allowed y

theorem endpoints (edge : Vertex → Vertex → Prop) (allowed : Vertex → Prop)
    (s t : Vertex) (h : CleanPath edge allowed s t) : allowed s ∧ allowed t := by
  induction h with
  | refl hv => exact ⟨hv,hv⟩
  | step path link target ih => exact ⟨ih.1,target⟩
theorem clean_to_filtered (edge : Vertex → Vertex → Prop) (allowed : Vertex → Prop)
    (s t : Vertex) (h : CleanPath edge allowed s t) : Walk (filtered edge allowed) s t := by
  induction h with
  | refl hv => exact .refl _
  | step path link target ih => exact .step ih ⟨link,(endpoints edge allowed _ _ path).2,target⟩
theorem filtered_to_clean (edge : Vertex → Vertex → Prop) (allowed : Vertex → Prop)
    (s t : Vertex) (start : allowed s) (h : Walk (filtered edge allowed) s t) : CleanPath edge allowed s t := by
  induction h with
  | refl => exact .refl start
  | step path link ih => exact .step ih link.1 link.2.2
theorem filtered_equivalence (edge : Vertex → Vertex → Prop) (allowed : Vertex → Prop)
    (s t : Vertex) : CleanPath edge allowed s t ↔ allowed s ∧ Walk (filtered edge allowed) s t := by
  constructor
  · intro h; exact ⟨(endpoints edge allowed s t h).1, clean_to_filtered edge allowed s t h⟩
  · rintro ⟨start,path⟩; exact filtered_to_clean edge allowed s t start path
-- More sanitizers mean fewer allowed vertices, hence fewer admitted paths.
theorem sanitizer_antitone (edge : Vertex → Vertex → Prop) (before after : Vertex → Prop)
    (restrict : ∀ v, after v → before v) (s t : Vertex)
    (h : CleanPath edge after s t) : CleanPath edge before s t := by
  induction h with
  | refl hv => exact .refl (restrict _ hv)
  | step path link target ih => exact .step ih link (restrict _ target)
theorem edge_monotone (before after : Vertex → Vertex → Prop) (allowed : Vertex → Prop)
    (grow : ∀ x y, before x y → after x y) (s t : Vertex)
    (h : CleanPath before allowed s t) : CleanPath after allowed s t := by
  induction h with
  | refl hv => exact .refl hv
  | step path link target ih => exact .step ih (grow _ _ link) target
end Ascent.UnsanitizedPaths
