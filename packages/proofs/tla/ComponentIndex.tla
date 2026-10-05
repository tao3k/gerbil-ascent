---- MODULE ComponentIndex ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Finite private single-bucket extension/install exploration, not native hashes.
EXTENDS Naturals, Sequences
CONSTANTS Owners, Mutation
VARIABLES rows, cache, version, cacheVersion, stage, published
vars == <<rows, cache, version, cacheVersion, stage, published>>
Batch == <<3, 2>>
Reverse(xs) == [i \in 1..Len(xs) |-> xs[Len(xs) - i + 1]]
Init == /\ rows = [o \in Owners |-> <<0, 1>>]
        /\ cache = rows /\ published = rows
        /\ version = [o \in Owners |-> 0] /\ cacheVersion = version
        /\ stage = [o \in Owners |-> 0]
Extend(o) == /\ stage[o] = 0
             /\ cache' = [cache EXCEPT ![o] = (IF Mutation = "order" THEN Reverse(Batch) ELSE Batch) \o @]
             /\ cacheVersion' = [cacheVersion EXCEPT ![o] = version[o] + 1]
             /\ stage' = [stage EXCEPT ![o] = 1]
             /\ UNCHANGED <<rows, version, published>>
Install(o) == /\ (stage[o] = 1 \/ (stage[o] = 0 /\ Mutation = "early"))
              /\ rows' = [rows EXCEPT ![o] = Batch \o @]
              /\ version' = [version EXCEPT ![o] = @ + 1]
              /\ published' = [published EXCEPT ![o] = rows'[o]]
              /\ stage' = [stage EXCEPT ![o] = 2]
              /\ UNCHANGED <<cache, cacheVersion>>
Next == \E o \in Owners : Extend(o) \/ Install(o)
Spec == Init /\ [][Next]_vars
Consistent == \A o \in Owners : stage[o] # 1 =>
                cache[o] = rows[o] /\ cacheVersion[o] = version[o] /\ published[o] = rows[o]
PrivateExtension == \A o \in Owners : stage[o] = 1 => published[o] = rows[o]
====
