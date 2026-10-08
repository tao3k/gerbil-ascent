---- MODULE ComponentIndex ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Finite private shared-root extension/install exploration, not native hashes.
EXTENDS Integers, Sequences
CONSTANTS Owners, Mutation, Inputs, DeclaredColumns
VARIABLES rows, cache, version, cacheVersion, stage, published, remaining, held, heldTruth, cacheColumns, heldColumns, heldColumnsTruth, viewRows, viewValid
vars == <<rows, cache, version, cacheVersion, stage, published, remaining, held, heldTruth, cacheColumns, heldColumns, heldColumnsTruth, viewRows, viewValid>>
\* Configurations supply finite input data, never a runtime generation bound.
\* TLC config uses operator substitution for sequence-valued constants.
\* Protocol actions depend only on Inputs, never on this selected fixture.
TwoBatchInputs == <<<<3, 2>>, <<4, 3>>>>
TwoColumnLayout == <<0, 1>>
Batch(o) == Head(remaining[o])
Reverse(xs) == [i \in 1..Len(xs) |-> xs[Len(xs) - i + 1]]
Init == /\ rows = [o \in Owners |-> <<0, 1>>]
        /\ cache = rows /\ published = rows
        /\ version = [o \in Owners |-> 0] /\ cacheVersion = version
        /\ stage = [o \in Owners |-> 0]
        /\ remaining = [o \in Owners |-> Inputs]
        /\ held = rows /\ heldTruth = rows
        /\ cacheColumns = [o \in Owners |-> DeclaredColumns]
        /\ heldColumns = cacheColumns /\ heldColumnsTruth = cacheColumns
        /\ viewRows = rows /\ viewValid = [o \in Owners |-> FALSE]
Extend(o) == /\ stage[o] = 0 /\ Len(remaining[o]) > 0
             /\ cache' = IF Mutation = "foreign" THEN
                   [p \in Owners |-> (IF p = o THEN cache[p] ELSE Batch(o) \o cache[p])]
                 ELSE [cache EXCEPT ![o] =
                   (IF Mutation = "order" THEN Reverse(Batch(o))
                    ELSE IF Mutation = "alias" THEN Batch(o) \o Batch(o)
                    ELSE Batch(o)) \o (IF Mutation = "reset" /\ version[o] > 0 THEN <<>> ELSE @)]
             /\ cacheColumns' = [cacheColumns EXCEPT ![o] =
                   IF Mutation = "columns" THEN Reverse(DeclaredColumns) ELSE DeclaredColumns]
             /\ cacheVersion' = [cacheVersion EXCEPT ![o] = version[o] + 1]
             /\ stage' = [stage EXCEPT ![o] = 1]
             /\ viewValid' = [viewValid EXCEPT ![o] = IF Mutation = "extend-view" THEN @ ELSE FALSE]
             /\ UNCHANGED <<rows, version, published, remaining, held, heldTruth, heldColumns, heldColumnsTruth, viewRows>>
Install(o) == /\ Len(remaining[o]) > 0
              /\ (stage[o] = 1 \/ (stage[o] = 0 /\ Mutation = "early"))
              /\ rows' = [rows EXCEPT ![o] = Batch(o) \o @]
              /\ version' = [version EXCEPT ![o] = @ + 1]
              /\ published' = [published EXCEPT ![o] = rows'[o]]
              /\ stage' = [stage EXCEPT ![o] = IF Len(remaining[o]) = 1 THEN 2 ELSE 0]
              /\ remaining' = [remaining EXCEPT ![o] = Tail(@)]
              /\ held' = IF Mutation = "held" THEN [held EXCEPT ![o] = cache[o]] ELSE held
              /\ heldColumns' = IF Mutation = "held-columns" THEN
                   [heldColumns EXCEPT ![o] = Reverse(DeclaredColumns)] ELSE heldColumns
              /\ UNCHANGED <<cache, cacheVersion, heldTruth, cacheColumns, heldColumnsTruth, viewRows, viewValid>>
\* Logical aliases resolve to one root; extending once per alias is rejected.
\* Foreign-owner extension is rejected before that owner installs any rows.
\* Failed provider mutation is unreadable until rebuilding from committed rows.
FailExtend(o) == /\ stage[o] = 0 /\ Len(remaining[o]) > 0
                 /\ cache' = [cache EXCEPT ![o] = <<3>> \o @]
                 /\ cacheVersion' = [cacheVersion EXCEPT ![o] =
                       IF Mutation = "failed" THEN version[o] ELSE -1]
                 /\ stage' = [stage EXCEPT ![o] = 3]
                 /\ viewValid' = [viewValid EXCEPT ![o] = IF Mutation = "failed-view" THEN @ ELSE FALSE]
                 /\ UNCHANGED <<rows, version, published, remaining, held, heldTruth, cacheColumns, heldColumns, heldColumnsTruth, viewRows>>
Rebuild(o) == /\ stage[o] = 3
              /\ cache' = [cache EXCEPT ![o] = rows[o]]
              /\ cacheColumns' = [cacheColumns EXCEPT ![o] =
                    IF Mutation = "rebuild-columns" THEN Reverse(DeclaredColumns) ELSE DeclaredColumns]
              /\ cacheVersion' = [cacheVersion EXCEPT ![o] = version[o]]
              /\ stage' = [stage EXCEPT ![o] = 0]
              /\ viewValid' = [viewValid EXCEPT ![o] = Mutation = "rebuild-view"]
              /\ viewRows' = [viewRows EXCEPT ![o] = IF Mutation = "rebuild-view" THEN cache[o] ELSE rows[o]]
              /\ UNCHANGED <<rows, version, published, remaining, held, heldTruth, heldColumns, heldColumnsTruth>>
\* A cold all-row prefix query constructs a private cached spine, not a held reader.
ReadView(o) == /\ stage[o] \in {0, 2} /\ cacheVersion[o] = version[o]
               /\ viewRows' = [viewRows EXCEPT ![o] = rows[o]]
               /\ viewValid' = [viewValid EXCEPT ![o] = TRUE]
               /\ UNCHANGED <<rows, cache, version, cacheVersion, stage, published, remaining,
                              held, heldTruth, cacheColumns, heldColumns, heldColumnsTruth>>
Next == \E o \in Owners : Extend(o) \/ Install(o) \/ FailExtend(o) \/ Rebuild(o) \/ ReadView(o)
Spec == Init /\ [][Next]_vars
Consistent == \A o \in Owners : stage[o] # 1 =>
                (cacheVersion[o] = version[o] =>
                   cache[o] = rows[o] /\ cacheColumns[o] = DeclaredColumns)
                /\ (stage[o] = 2 => cacheVersion[o] = version[o])
                /\ published[o] = rows[o]
HeldStable == held = heldTruth /\ heldColumns = heldColumnsTruth
PrivateExtension == \A o \in Owners : stage[o] = 1 => published[o] = rows[o]
ViewConsistent == \A o \in Owners : viewValid[o] =>
                   /\ stage[o] \in {0, 2} /\ cacheVersion[o] = version[o]
                   /\ viewRows[o] = rows[o]
====
