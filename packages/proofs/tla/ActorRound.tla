---- MODULE ActorRound ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Proposed single-owner, parallel positive-round protocol. Not a native
\* Gerbil refinement, fairness proof, or DBSP signed-change implementation.
EXTENDS Naturals, FiniteSets, TLC
CONSTANTS Workers, TLCGenerationCutoff, TLCRoundCutoff, Mutation
VARIABLES generation, round, seed, frozen, total, delta, done, outstanding,
          workGeneration, mailbox, history, accepted, phase,
          publishedSeed, published, badBarrier
vars == <<generation, round, seed, frozen, total, delta, done, outstanding,
          workGeneration, mailbox, history, accepted, phase,
          publishedSeed, published, badBarrier>>

Seeds == {{1}, {2}}
\* Two producer rules: 2 <- 1, then 3 <- 2. A later rule must see a
\* newly merged frontier on the next round, not an incomplete private batch.
Rows(worker, cut) == IF worker = 1 THEN (IF 1 \in cut THEN {2} ELSE {})
                    ELSE (IF 2 \in cut THEN {3} ELSE {})
Closure(input) == IF 1 \in input THEN {1,2,3} ELSE {2,3}
Message(worker) == [epoch |-> workGeneration, tick |-> round,
                    owner |-> worker, rows |-> Rows(worker, frozen)]
Init ==
  /\ generation = 0 /\ round = 0 /\ seed = {2}
  /\ frozen = seed /\ total = seed /\ delta = {}
  /\ done = {} /\ outstanding = {} /\ workGeneration = 0
  /\ mailbox = {} /\ history = {} /\ accepted = {}
  /\ phase = "idle" /\ publishedSeed = {2} /\ published = {2,3}
  /\ badBarrier = FALSE

Start ==
  /\ phase \in {"idle", "complete", "canceled"}
  /\ \E input \in Seeds : seed' = input /\ total' = input /\ frozen' = input
  /\ generation' = generation + 1 /\ workGeneration' = generation + 1
  /\ round' = 0 /\ done' = {} /\ delta' = {} /\ accepted' = {}
  /\ outstanding' = Workers /\ phase' = "running"
  /\ UNCHANGED <<mailbox, history, publishedSeed, published, badBarrier>>

Reply(worker) ==
  /\ phase \in {"running", "draining"} /\ worker \in outstanding
  /\ mailbox' = mailbox \cup {Message(worker)}
  /\ history' = history \cup {Message(worker)}
  /\ outstanding' = outstanding \ {worker}
  /\ UNCHANGED <<generation, round, seed, frozen, total, delta, done,
                 workGeneration, accepted, phase, publishedSeed, published, badBarrier>>

Replay ==
  /\ \E msg \in history : mailbox' = mailbox \cup {msg}
  /\ UNCHANGED <<generation, round, seed, frozen, total, delta, done,
                 outstanding, workGeneration, history, accepted, phase,
                 publishedSeed, published, badBarrier>>

Current(msg) == msg.epoch = generation /\ msg.tick = round
Accept ==
  /\ phase = "running"
  /\ \E msg \in mailbox :
       /\ (Current(msg) \/ Mutation = "stale") /\ msg.owner \notin done
       /\ done' = done \cup {msg.owner}
       /\ delta' = delta \cup msg.rows
       /\ accepted' = accepted \cup {msg}
       /\ mailbox' = mailbox \ {msg}
  /\ UNCHANGED <<generation, round, seed, frozen, total, outstanding,
                 workGeneration, history, phase, publishedSeed, published, badBarrier>>

Drop ==
  /\ \E msg \in mailbox :
       /\ (~Current(msg) \/ msg.owner \in done \/ phase # "running")
       /\ mailbox' = mailbox \ {msg}
  /\ UNCHANGED <<generation, round, seed, frozen, total, delta, done,
                 outstanding, workGeneration, history, accepted, phase,
                 publishedSeed, published, badBarrier>>

Barrier ==
  /\ phase = "running"
  /\ ((done = Workers /\ outstanding = {}) \/ Mutation = "early")
  /\ badBarrier' = badBarrier \/ done # Workers \/ outstanding # {}
  /\ IF delta \subseteq total
        THEN /\ published' = total /\ publishedSeed' = seed
             /\ phase' = "complete"
             /\ UNCHANGED <<round, frozen, total, delta, done, outstanding,
                            workGeneration, accepted>>
        ELSE /\ total' = total \cup delta /\ frozen' = total \cup delta
             /\ round' = round + 1 /\ delta' = {} /\ done' = {}
             /\ accepted' = {} /\ outstanding' = Workers
             /\ workGeneration' = generation /\ phase' = "running"
             /\ UNCHANGED <<published, publishedSeed>>
  /\ UNCHANGED <<generation, seed, mailbox, history>>

Cancel ==
  /\ phase = "running" /\ phase' = "draining"
  /\ generation' = generation + 1 /\ accepted' = {}
  /\ published' = IF Mutation = "cancel" THEN total ELSE published
  /\ publishedSeed' = IF Mutation = "cancel" THEN seed ELSE publishedSeed
  /\ UNCHANGED <<round, seed, frozen, total, delta, done, outstanding,
                 workGeneration, mailbox, history, badBarrier>>

CancelAck(worker) ==
  /\ phase = "draining" /\ worker \in outstanding
  /\ outstanding' = outstanding \ {worker}
  /\ UNCHANGED <<generation, round, seed, frozen, total, delta, done,
                 workGeneration, mailbox, history, accepted, phase,
                 publishedSeed, published, badBarrier>>
Drained ==
  /\ phase = "draining" /\ outstanding = {} /\ phase' = "canceled"
  /\ UNCHANGED <<generation, round, seed, frozen, total, delta, done,
                 outstanding, workGeneration, mailbox, history, accepted,
                 publishedSeed, published, badBarrier>>
Next == Start \/ Replay \/ Accept \/ Drop \/ Barrier \/ Cancel \/ Drained
        \/ (\E worker \in Workers : Reply(worker) \/ CancelAck(worker))
Spec == Init /\ [][Next]_vars
CompletePublication == published = Closure(publishedSeed)
NoStaleCompletion == \A msg \in accepted : Current(msg)
CompleteBarrier == ~badBarrier
\* Tool exploration only. Natural generations/rounds in Spec are unbounded.
Exploration == generation <= TLCGenerationCutoff /\ round <= TLCRoundCutoff
====
