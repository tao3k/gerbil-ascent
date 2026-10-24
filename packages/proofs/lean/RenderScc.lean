-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import SccState

def main (args : List String) : IO Unit :=
  if args == ["scheme"] then IO.print Ascent.SccState.source
  else throw (IO.userError "expected: scheme")
