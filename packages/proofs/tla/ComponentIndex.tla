---- MODULE ComponentIndex ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Finite private shared-root extension/install exploration, not native hashes.
EXTENDS Integers, Sequences
CONSTANTS Owners, Mutation, Inputs
VARIABLES rows, cache, version, cacheVersion, stage, published, remaining, held, heldTruth
vars == <<rows, cache, version, cacheVersion, stage, published, remaining, held, heldTruth>>
\* Configurations supply finite input data, never a runtime generation bound.
\* TLC config uses operator substitution for sequence-valued constants.
\* Protocol actions depend only on Inputs, never on this selected fixture.
TwoBatchInputs == <<<<3, 2>>, <<4, 3>>>>
Batch(o) == Head(remaining[o])
Reverse(xs) == [i \in 1..Len(xs) |-> xs[Len(xs) - i + 1]]
Init == /\ rows = [o \in Owners |-> <<0, 1>>]
        /\ cache = rows /\ published = rows
        /\ version = [o \in Owners |-> 0] /\ cacheVersion = version
        /\ stage = [o \in Owners |-> 0]
        /\ remaining = [o \in Owners |-> Inputs]
        /\ held = rows /\ heldTruth = rows
Extend(o) == /\ stage[o] = 0 /\ Len(remaining[o]) > 0
             /\ cache' = IF Mutation = "foreign" THEN
                   [p \in Owners |-> (IF p = o THEN cache[p] ELSE Batch(o) \o cache[p])]
                 ELSE [cache EXCEPT ![o] =
                   (IF Mutation = "order" THEN Reverse(Batch(o))
                    ELSE IF Mutation = "alias" THEN Batch(o) \o Batch(o)
                    ELSE Batch(o)) \o (IF Mutation = "reset" /\ version[o] > 0 THEN <<>> ELSE @)]
             /\ cacheVersion' = [cacheVersion EXCEPT ![o] = version[o] + 1]
             /\ stage' = [stage EXCEPT ![o] = 1]
             /\ UNCHANGED <<rows, version, published, remaining, held, heldTruth>>
Install(o) == /\ Len(remaining[o]) > 0
              /\ (stage[o] = 1 \/ (stage[o] = 0 /\ Mutation = "early"))
              /\ rows' = [rows EXCEPT ![o] = Batch(o) \o @]
              /\ version' = [version EXCEPT ![o] = @ + 1]
              /\ published' = [published EXCEPT ![o] = rows'[o]]
              /\ stage' = [stage EXCEPT ![o] = IF Len(remaining[o]) = 1 THEN 2 ELSE 0]
              /\ remaining' = [remaining EXCEPT ![o] = Tail(@)]
              /\ held' = IF Mutation = "held" THEN [held EXCEPT ![o] = cache[o]] ELSE held
              /\ UNCHANGED <<cache, cacheVersion, heldTruth>>
\* Logical aliases resolve to one root; extending once per alias is rejected.
\* Foreign-owner extension is rejected before that owner installs any rows.
\* Failed provider mutation is unreadable until rebuilding from committed rows.
FailExtend(o) == /\ stage[o] = 0 /\ Len(remaining[o]) > 0
                 /\ cache' = [cache EXCEPT ![o] = <<3>> \o @]
                 /\ cacheVersion' = [cacheVersion EXCEPT ![o] =
                       IF Mutation = "failed" THEN version[o] ELSE -1]
                 /\ stage' = [stage EXCEPT ![o] = 3]
                 /\ UNCHANGED <<rows, version, published, remaining, held, heldTruth>>
Rebuild(o) == /\ stage[o] = 3
              /\ cache' = [cache EXCEPT ![o] = rows[o]]
              /\ cacheVersion' = [cacheVersion EXCEPT ![o] = version[o]]
              /\ stage' = [stage EXCEPT ![o] = 0]
              /\ UNCHANGED <<rows, version, published, remaining, held, heldTruth>>
Next == \E o \in Owners : Extend(o) \/ Install(o) \/ FailExtend(o) \/ Rebuild(o)
Spec == Init /\ [][Next]_vars
Consistent == \A o \in Owners : stage[o] # 1 =>
                (cacheVersion[o] = version[o] => cache[o] = rows[o])
                /\ (stage[o] = 2 => cacheVersion[o] = version[o])
                /\ published[o] = rows[o]
HeldStable == held = heldTruth
PrivateExtension == \A o \in Owners : stage[o] = 1 => published[o] = rows[o]
====
