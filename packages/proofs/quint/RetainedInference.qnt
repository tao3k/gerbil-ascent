// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module RetainedInference {
  pure def bit(id:int,n:int):bool = id / (if(n == 0) 1 else if(n == 1) 2 else if(n == 2) 4 else 8) % 2 == 1
  pure def current(id:int,phase:int):int = if(phase == 1 and bit(id,2)) id-4 else id
  // Positive-length reachability to actor 0 over all two-actor graphs.
  pure def answer(id:int):int = (if(bit(id,0) or (bit(id,1) and bit(id,2))) 1 else 0)
    + (if(bit(id,2)) 2 else 0)
  pure val conformance = range(0,32).foldl(List(),(rows,n) => {
    val id=n/2
    val phase=n%2
    val now=current(id,phase)
    rows.append(List(id,phase,now,answer(now),if(id == now) 1 else 0))
  })
}
