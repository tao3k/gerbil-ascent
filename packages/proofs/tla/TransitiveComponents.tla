---- MODULE TransitiveComponents ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Three admitted nodes explore SCC edge insertion, remapping and budget refusal.
EXTENDS Naturals, FiniteSets
CONSTANTS Nodes, Mutation
VARIABLES inputs, parent, arcs, refused, saved
vars == <<inputs, parent, arcs, refused, saved>>
RECURSIVE Close(_)
Close(edges) == LET next == edges \cup
                  {p \in Nodes \X Nodes : \E b \in Nodes :
                    <<p[1], b>> \in edges /\ <<b, p[2]>> \in edges}
               IN IF next = edges THEN edges ELSE Close(next)
Expected(edges) == Close(edges \cup {<<n,n>> : n \in Nodes})
Concrete(par, links) == {p \in Nodes \X Nodes :
                         par[p[1]] = par[p[2]] \/ <<par[p[1]],par[p[2]]>> \in links}
Reach(r,s) == r = s \/ <<r,s>> \in arcs
Roots == {parent[n] : n \in Nodes}
Plan(edge) == LET a == parent[edge[1]]
                  b == parent[edge[2]]
                  pred == {r \in Roots : Reach(r,a)}
                  succ == {r \in Roots : Reach(b,r)}
                  cycle == IF Reach(b,a) THEN pred \cap succ ELSE {}
                  winner == IF cycle = {} THEN 0 ELSE CHOOSE m \in cycle : \A n \in cycle : m <= n
                  par == [n \in Nodes |-> IF parent[n] \in cycle THEN winner ELSE parent[n]]
                  links == arcs \cup (pred \X succ)
                  normalized == {<<par[p[1]],par[p[2]]>> : p \in links}
                  between == {p \in normalized : p[1] # p[2]}
              IN [par |-> par, links |-> between,
                  delta |-> Expected(inputs \cup {edge}) \ Concrete(parent,arcs)]
Init == /\ inputs = {} /\ parent = [n \in Nodes |-> n] /\ arcs = {}
        /\ refused = FALSE /\ saved = <<inputs,parent,arcs>>
Accept(edge) == LET plan == Plan(edge)
               IN /\ edge \notin inputs
                  /\ inputs' = inputs \cup {edge}
                  /\ parent' = (IF Mutation = "split" THEN parent ELSE plan.par)
                  /\ arcs' = (IF Mutation = "stale" THEN arcs \cup {<<parent[edge[1]],parent[edge[2]]>>}
                              ELSE plan.links)
                  /\ refused' = FALSE /\ UNCHANGED saved
Reject(edge) == /\ edge \notin inputs /\ Cardinality(Plan(edge).delta) > 0
               /\ saved' = <<inputs,parent,arcs>> /\ refused' = TRUE
               /\ arcs' = (IF Mutation = "reject" THEN Plan(edge).links ELSE arcs)
               /\ UNCHANGED <<inputs,parent>>
Next == \E edge \in Nodes \X Nodes : Accept(edge) \/ Reject(edge)
Spec == Init /\ [][Next]_vars
ReachExact == Concrete(parent,arcs) = Expected(inputs)
SCCExact == \A a,b \in Nodes : (parent[a] = parent[b]) <=>
              (<<a,b>> \in Expected(inputs) /\ <<b,a>> \in Expected(inputs))
ParentRoots == \A n \in Nodes : parent[parent[n]] = parent[n]
PrivateArcs == \A p \in arcs : p[1] # p[2] /\ p[1] \in Roots /\ p[2] \in Roots
RefusalAtomic == refused => <<inputs,parent,arcs>> = saved
====
