---------------------------- MODULE ActorTestPool ----------------------------
EXTENDS Naturals, FiniteSets
CONSTANTS Tasks, Capacity, EarlyReturn
VARIABLES pending, active, waiting, terminal, canceled, failed, returned
vars == <<pending, active, waiting, terminal, canceled, failed, returned>>

Init == /\ pending = Tasks /\ active = {} /\ waiting = {}
        /\ terminal = {} /\ canceled = {} /\ failed = FALSE /\ returned = FALSE
Dispatch(t) == /\ ~returned /\ ~failed /\ t \in pending
               /\ Cardinality(active) < Capacity
               /\ pending' = pending \ {t} /\ active' = active \cup {t}
               /\ UNCHANGED <<waiting, terminal, canceled, failed, returned>>
Offer(t) == /\ ~returned /\ t \in active \ waiting
            /\ waiting' = waiting \cup {t}
            /\ UNCHANGED <<pending, active, terminal, canceled, failed, returned>>
Ack(t) == /\ ~returned /\ t \in waiting /\ waiting' = waiting \ {t}
          /\ UNCHANGED <<pending, active, terminal, canceled, failed, returned>>
Finish(t) == /\ ~returned /\ t \in active \ waiting
             /\ active' = active \ {t} /\ terminal' = terminal \cup {t}
             /\ UNCHANGED <<pending, waiting, canceled, failed, returned>>
Fail(t) == /\ ~returned /\ t \in active \ waiting
           /\ active' = active \ {t} /\ terminal' = terminal \cup {t}
           /\ canceled' = canceled \cup pending /\ pending' = {}
           /\ failed' = TRUE /\ UNCHANGED <<waiting, returned>>
SinkFault(t) == /\ ~returned /\ t \in waiting
                /\ waiting' = waiting \ {t}
                /\ canceled' = canceled \cup pending /\ pending' = {}
                /\ failed' = TRUE /\ UNCHANGED <<active, terminal, returned>>
Return == /\ ~returned /\ pending = {} /\ (active = {} \/ EarlyReturn)
          /\ returned' = TRUE
          /\ UNCHANGED <<pending, active, waiting, terminal, canceled, failed>>
Next == (\E t \in Tasks: Dispatch(t) \/ Offer(t) \/ Ack(t) \/ Finish(t) \/ Fail(t) \/ SinkFault(t)) \/ Return
Spec == Init /\ [][Next]_vars
Partition == /\ pending \cup active \cup terminal \cup canceled = Tasks
             /\ pending \cap active = {} /\ pending \cap terminal = {}
             /\ pending \cap canceled = {} /\ active \cap terminal = {}
             /\ active \cap canceled = {} /\ terminal \cap canceled = {}
BoundedCredits == waiting \subseteq active /\ Cardinality(active) <= Capacity
                  /\ Cardinality(waiting) <= Capacity
StoppedAdmission == failed => pending = {}
CompleteReturn == returned => (pending = {} /\ active = {} /\ waiting = {})
=============================================================================
