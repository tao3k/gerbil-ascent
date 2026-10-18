-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import DescriptorKeys

def main (args : List String) : IO Unit := do
  match args with
  | ["scheme"] => IO.print Ascent.DescriptorKeys.schemeSource
  | ["rust"] => IO.print Ascent.DescriptorKeys.rustSource
  | _ => throw (IO.userError "expected scheme or rust")
