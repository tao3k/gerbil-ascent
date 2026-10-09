-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import CertificateMaterial
open Ascent.CertificateMaterial
def cap : Limits := ⟨2, 3, 2⟩
example : reserveAll cap ⟨0, 0⟩ [1, 2] = some ⟨2, 3⟩ := by decide
example : reserveAll cap ⟨0, 0⟩ [1, 2, 0] = none := by decide
example : reserveAll cap ⟨0, 0⟩ [2, 2] = none := by decide
example : reserveAll cap ⟨0, 0⟩ [3] = none := by decide
example : transition cap ⟨1, 2⟩ 2 = ⟨1, 2⟩ := by decide
-- Zero-width rows still consume a row slot.
example : reserveAll cap ⟨0, 0⟩ [0, 0, 0] = none := by decide
