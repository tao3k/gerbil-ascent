// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// External node/root spines only. Node semantics and identity are independent.
module ProofShapeAdmission {
  const Mutation: str
  type State = {nodes: int, roots: int, nodeProper: bool, rootProper: bool,
    cursor: int, stage: str, allocated: bool, refused: bool, published: bool}
  var q: State
  action init = {
    nondet ns = Set(0,1,2,3).oneOf();
    nondet rs = Set(0,1,2,3).oneOf();
    nondet np = Set(false,true).oneOf();
    nondet rp = Set(false,true).oneOf();
    q' = {nodes: ns, roots: rs, nodeProper: np, rootProper: rp,
      cursor: 0, stage: "nodes", allocated: Mutation == "early", refused: false, published: false}
  }
  pure def Reject(s: State): State = {...s, stage: "refused", refused: true,
    published: Mutation == "partial"}
  action scanNodes = all {q.stage == "nodes",
    q' = if (q.cursor == q.nodes)
      (if (q.nodeProper or Mutation == "improper") {...q, stage: "roots", cursor: 0} else Reject(q))
      else if (q.cursor == 2) Reject(q) else {...q, cursor: q.cursor + 1}}
  action scanRoots = all {q.stage == "roots",
    q' = if (q.cursor == q.roots)
      (if (q.rootProper or Mutation == "improper") {...q, stage: "admitted"} else Reject(q))
      else if (q.cursor == (if (Mutation == "roots") 2 else q.nodes)) Reject(q)
      else {...q, cursor: q.cursor + 1}}
  action index = all {q.stage == "admitted", q' = {...q, stage: "indexed", allocated: true}}
  // Publication additionally requires semantic validation, abstracted here.
  action finish = all {q.stage == "indexed", q' = {...q, stage: "complete", published: true}}
  action step = any {scanNodes, scanRoots, index, finish}
  pure def Shape(s: State): bool = s.nodes <= 2 and s.roots <= s.nodes and s.nodeProper and s.rootProper
  val AllocationAfterAdmission = q.allocated implies Shape(q) and Set("indexed","complete").contains(q.stage)
  val AdmittedShape = Set("admitted","indexed","complete").contains(q.stage) implies Shape(q)
  val RefusalUnpublished = q.refused implies q.stage == "refused" and not(q.allocated) and not(q.published)
  val PublicationAfterIndex = q.published implies q.stage == "complete" and q.allocated
}
