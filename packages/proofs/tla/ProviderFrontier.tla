---- MODULE ProviderFrontier ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Finite eqrel injection/frontier/consumer exploration, not native refinement.
EXTENDS Naturals, FiniteSets
CONSTANTS Nodes, Mutation
VARIABLES inputs, total, delta, pending, delivered, phase
vars == <<inputs, total, delta, pending, delivered, phase>>
RECURSIVE Close(_)
Close(edges) == LET next == edges \cup
                 {p \in Nodes \X Nodes : \E b \in Nodes :
                    <<p[1], b>> \in edges /\ <<b, p[2]>> \in edges}
               IN IF next = edges THEN edges ELSE Close(next)
Concrete(edges) == LET members == {n \in Nodes : \E p \in edges : n = p[1] \/ n = p[2]}
                  IN Close(edges \cup {<<p[2], p[1]>> : p \in edges}
                           \cup {<<n, n>> : n \in members})
Init == /\ inputs = {} /\ total = {} /\ delta = {}
        /\ pending = {} /\ delivered = {} /\ phase = "idle"
Inject(edge) == /\ phase = "idle" /\ edge \notin inputs
                /\ inputs' = inputs \cup {edge}
                /\ pending' = Concrete(inputs')
                /\ delta' = IF Mutation = "raw" THEN {edge} \ total
                             ELSE pending' \ total
                /\ phase' = "pending"
                /\ UNCHANGED <<total, delivered>>
Consume == /\ phase = "pending"
           /\ delivered' = IF Mutation = "omit" THEN delivered ELSE delivered \cup delta
           /\ total' = pending /\ delta' = {} /\ phase' = "idle"
           /\ UNCHANGED <<inputs, pending>>
Next == (\E edge \in Nodes \X Nodes : Inject(edge)) \/ Consume
Spec == Init /\ [][Next]_vars
FrontierComplete == phase = "pending" =>
                      pending = total \cup delta /\ delta = pending \ total
DeliveredExact == phase = "idle" => delivered = total /\ total = Concrete(inputs)
====
