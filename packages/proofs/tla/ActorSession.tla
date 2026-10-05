---- MODULE ActorSession ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Actor Session publication/drain safety. Complete outcome assumes solver
\* correctness; finite cut and generation enumeration is TLC exploration only.
EXTENDS Naturals
CONSTANTS Cuts, TLCGenerationCutoff, Mutation
VARIABLES generation, epoch, pending, committed, published, publishedCut,
          frozen, phase, assigned, closing, stalePublish, earlyClose
vars == <<generation, epoch, pending, committed, published, publishedCut,
          frozen, phase, assigned, closing, stalePublish, earlyClose>>
Result(cut) == {cut}
Init == /\ generation = 0 /\ epoch = 0 /\ pending = 0 /\ committed = 0
        /\ published = Result(0) /\ publishedCut = 0 /\ frozen = 0
        /\ phase = "idle" /\ assigned = FALSE /\ closing = FALSE
        /\ stalePublish = FALSE /\ earlyClose = FALSE
Update == /\ phase = "idle" /\ ~closing
          /\ \E cut \in Cuts : pending' = cut
          /\ generation' = generation + 1
          /\ UNCHANGED <<epoch, committed, published, publishedCut, frozen, phase,
                         assigned, closing, stalePublish, earlyClose>>
Start == /\ phase = "idle" /\ ~closing
         /\ generation' = generation + 1 /\ epoch' = generation + 1
         /\ frozen' = pending /\ phase' = "running" /\ assigned' = TRUE
         /\ UNCHANGED <<pending, committed, published, publishedCut, closing, stalePublish, earlyClose>>
Cancel == /\ phase \in {"running", "draining"}
          /\ generation' = generation + 1 /\ phase' = "draining"
          /\ UNCHANGED <<epoch, pending, committed, published, publishedCut, frozen,
                         assigned, closing, stalePublish, earlyClose>>
Finish(success) ==
  /\ assigned /\ phase \in {"running", "draining"}
  /\ IF success /\ (epoch = generation \/ Mutation = "stale")
       THEN /\ published' = Result(frozen) /\ publishedCut' = frozen
            /\ committed' = frozen /\ pending' = pending
            /\ stalePublish' = (stalePublish \/ epoch # generation)
       ELSE /\ pending' = committed
            /\ UNCHANGED <<published, publishedCut, committed, stalePublish>>
  /\ assigned' = FALSE /\ phase' = "idle"
  /\ UNCHANGED <<generation, epoch, frozen, closing, earlyClose>>
RequestClose == /\ phase # "closed" /\ ~closing /\ closing' = TRUE
                /\ generation' = IF assigned THEN generation + 1 ELSE generation
                /\ phase' = IF assigned THEN "draining" ELSE phase
                /\ UNCHANGED <<epoch, pending, committed, published, publishedCut,
                               frozen, assigned, stalePublish, earlyClose>>
Close == /\ closing /\ phase # "closed" /\ (~assigned \/ Mutation = "early")
         /\ phase' = "closed" /\ earlyClose' = (earlyClose \/ assigned)
         /\ UNCHANGED <<generation, epoch, pending, committed, published, publishedCut,
                        frozen, assigned, closing, stalePublish>>
Next == Update \/ Start \/ Cancel \/ Finish(TRUE) \/ Finish(FALSE) \/ RequestClose \/ Close
Spec == Init /\ [][Next]_vars
ConsistentPublication == published = Result(publishedCut) /\ committed = publishedCut
NoStalePublication == ~stalePublish
DrainedClose == ~earlyClose /\ (phase = "closed" => ~assigned)
Exploration == generation <= TLCGenerationCutoff
====
