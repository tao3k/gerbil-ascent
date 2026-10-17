-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import DescriptorKernel

def main (args : List String) : IO Unit := do
  match args with
  | ["scheme"] => IO.print Ascent.DescriptorKernel.schemeSource
  | ["rust"] => IO.print Ascent.DescriptorKernel.rustSource
  | _ => throw (IO.userError "expected scheme or rust")
