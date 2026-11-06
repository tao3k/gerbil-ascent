-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ActorEnvelope

def main (args : List String) : IO Unit := do
  if args != ["scheme"] then throw (IO.userError "expected scheme")
  IO.print Ascent.ActorEnvelope.source
