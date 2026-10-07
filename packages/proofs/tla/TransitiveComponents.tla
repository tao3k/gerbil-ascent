---- MODULE TransitiveComponents ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Three admitted nodes explore SCC edge insertion, remapping and budget refusal.
EXTENDS Naturals, FiniteSets
CONSTANTS Nodes, Mutation
VARIABLES inputs, parent, arcs, refused, saved, active, frontier, before, link, members, size
vars == <<inputs, parent, arcs, refused, saved, active, frontier, before, link, members, size>>
RECURSIVE Close(_)
Close(edges) == LET next == edges \cup
                  {p \in Nodes \X Nodes : \E b \in Nodes :
                    <<p[1], b>> \in edges /\ <<b, p[2]>> \in edges}
               IN IF next = edges THEN edges ELSE Close(next)
Expected(edges) == Close(edges \cup {<<n,n>> : n \in Nodes})
Concrete(par, links) == {p \in Nodes \X Nodes :
                         par[p[1]] = par[p[2]] \/ <<par[p[1]],par[p[2]]>> \in links}
Visible(par, links, live) == Concrete(par, links) \cap (live \X live)
Reach(r,s) == r = s \/ <<r,s>> \in arcs
Roots == {parent[n] : n \in Nodes}
\* link retains native parent chains; parent is its abstract root projection.
RECURSIVE Walk(_,_,_), Sum(_)
Walk(links,n,k) == IF k = 0 THEN n ELSE Walk(links,links[n],k-1)
Sum(roots) == IF roots = {} THEN 0 ELSE
               LET r == CHOOSE n \in roots : TRUE
               IN size[r] + Sum(roots \ {r})
Plan(edge) == LET a == parent[edge[1]]
                  b == parent[edge[2]]
                  pred == {r \in Roots : Reach(r,a)}
                  succ == {r \in Roots : Reach(b,r)}
                  cycle == IF Reach(b,a) THEN pred \cap succ ELSE {}
                  winner == IF cycle = {} THEN 0 ELSE CHOOSE m \in cycle : \A n \in cycle : size[m] >= size[n]
                  par == [n \in Nodes |-> IF parent[n] \in cycle THEN winner ELSE parent[n]]
                  links == arcs \cup {p \in pred \X succ : p[1] # p[2]}
                  surviving == {par[n] : n \in Nodes}
                  \* Native keeps winner's reach and removes absorbed target keys.
                  between == {p \in links : p[1] \in surviving /\
                    ~(p[2] \in cycle /\
                      (p[1] = winner \/ <<p[1],winner>> \in links) /\
                      (p[2] # winner \/ p[1] = winner))}
                  merged == UNION {members[r] : r \in cycle}
                  mem == [r \in Nodes |-> IF r = winner THEN merged
                          ELSE IF r \in cycle THEN {} ELSE members[r]]
                  sz == [r \in Nodes |-> IF r = winner THEN Sum(cycle)
                         ELSE IF r \in cycle THEN 0 ELSE size[r]]
                  chain == [r \in Nodes |-> IF r \in cycle \ {winner}
                            THEN winner ELSE link[r]]
                  missing == {p \in Nodes \X Nodes : parent[p[1]] \in pred /\
                               parent[p[2]] \in succ /\ ~Reach(parent[p[1]],parent[p[2]])}
                  newSelf == {<<n,n>> : n \in {edge[1],edge[2]} \ active}
              IN [par |-> par, links |-> between, pre |-> links, winner |-> winner,
                  mem |-> mem, sz |-> sz, chain |-> chain,
                  delta |-> missing \cup newSelf, raw |-> pred \X succ, missing |-> missing]
Init == /\ inputs = {} /\ parent = [n \in Nodes |-> n] /\ arcs = {}
        /\ refused = FALSE /\ active = {} /\ frontier = {} /\ before = {}
        /\ link = [n \in Nodes |-> n]
        /\ members = [n \in Nodes |-> {n}] /\ size = [n \in Nodes |-> 1]
        /\ saved = <<inputs,parent,arcs,active,link,members,size>>
Accept(edge) == LET plan == Plan(edge)
               IN /\ edge \notin inputs
                  /\ inputs' = inputs \cup {edge}
                  /\ before' = Visible(parent,arcs,active)
                  /\ active' = active \cup {edge[1],edge[2]}
                  /\ frontier' = IF Mutation = "raw" THEN {edge}
                                  ELSE IF Mutation = "diagonal" THEN plan.missing
                                  ELSE IF Mutation = "old" THEN
                                    {p \in Nodes \X Nodes : <<parent[p[1]],parent[p[2]]>> \in plan.raw} \cup plan.delta
                                  ELSE plan.delta
                  /\ parent' = (IF Mutation = "split" THEN parent ELSE plan.par)
                  /\ arcs' = (IF Mutation = "stale" THEN arcs \cup {<<parent[edge[1]],parent[edge[2]]>>}
                              ELSE IF Mutation = "adjacency" THEN
                                {p \in plan.pre : p[1] \in {plan.par[n] : n \in Nodes}}
                              ELSE plan.links)
                  /\ link' = (IF Mutation = "chain" /\ plan.winner # 0 THEN
                       [plan.chain EXCEPT ![plan.winner] = CHOOSE r \in Nodes : r # plan.winner]
                       ELSE plan.chain)
                  /\ members' = (IF Mutation = "members" THEN members ELSE plan.mem)
                  /\ size' = (IF Mutation = "size" THEN size ELSE plan.sz)
                  /\ refused' = FALSE /\ UNCHANGED saved
Reject(edge) == /\ edge \notin inputs /\ Cardinality(Plan(edge).delta) > 0
               /\ saved' = <<inputs,parent,arcs,active,link,members,size>> /\ refused' = TRUE
               /\ arcs' = (IF Mutation = "reject" THEN Plan(edge).links ELSE arcs)
               /\ UNCHANGED <<inputs,parent,active,frontier,before,link,members,size>>
Next == \E edge \in Nodes \X Nodes : Accept(edge) \/ Reject(edge)
Spec == Init /\ [][Next]_vars
ReachExact == Concrete(parent,arcs) = Expected(inputs)
SCCExact == \A a,b \in Nodes : (parent[a] = parent[b]) <=>
              (<<a,b>> \in Expected(inputs) /\ <<b,a>> \in Expected(inputs))
ParentRoots == \A n \in Nodes : parent[parent[n]] = parent[n]
PrivateArcs == \A p \in arcs : p[1] # p[2] /\ p[1] \in Roots /\ p[2] \in Roots
RefusalAtomic == refused => <<inputs,parent,arcs,active,link,members,size>> = saved
\* The emitted delta is constructed from the old root graph, never Expected.
\* Independent input closure is used only to check the accepted publication.
ActiveExact == active = {n \in Nodes : \E edge \in inputs : n \in {edge[1],edge[2]}}
DeltaExact == frontier = (Expected(inputs) \cap (active \X active)) \ before
\* Finite walk depth is the number of model nodes, not a runtime generation cap.
ParentChains == \A n \in Nodes :
  link[parent[n]] = parent[n] /\ Walk(link,n,Cardinality(Nodes)) = parent[n]
MemberPartition == \A r \in Nodes :
  members[r] = {n \in Nodes : parent[n] = r}
SizeExact == \A r \in Nodes : size[r] = Cardinality(members[r])
====
