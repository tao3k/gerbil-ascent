// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Private shared-root publication protocol. Native hash semantics belong to Lean
// and Scheme conformance tests. Inputs are finite data, not a generation limit.
module ComponentIndex {
  const Owners: Set[int]
  const Mutation: str
  const Inputs: List[List[int]]
  const DeclaredColumns: List[int]

  type Owner = {
    rows: List[int], cache: List[int], version: int, cacheVersion: int,
    stage: int, published: List[int], remaining: List[List[int]],
    held: List[int], heldTruth: List[int], cacheColumns: List[int],
    heldColumns: List[int], heldColumnsTruth: List[int],
    viewRows: List[int], viewValid: bool
  }
  var owners: int -> Owner

  pure def reverse(xs: List[int]): List[int] =
    xs.foldl(List(), (acc, x) => List(x).concat(acc))

  action init = owners' = Owners.mapBy(o => {
    rows: List(0, 1), cache: List(0, 1), version: 0, cacheVersion: 0,
    stage: 0, published: List(0, 1), remaining: Inputs,
    held: List(0, 1), heldTruth: List(0, 1), cacheColumns: DeclaredColumns,
    heldColumns: DeclaredColumns, heldColumnsTruth: DeclaredColumns,
    viewRows: List(0, 1), viewValid: false
  })

  action extend(o: int): bool = {
    val x = owners.get(o)
    all {
      x.stage == 0, x.remaining.length() > 0,
      owners' = Owners.mapBy(p => {
        val old = owners.get(p)
        if (p == o) {
          val batch = x.remaining.head()
          val fresh = if (Mutation == "order") reverse(batch)
                      else if (Mutation == "alias") batch.concat(batch) else batch
          val prior = if (Mutation == "reset" and x.version > 0) List() else x.cache
          { ...x,
            cache: if (Mutation == "foreign") x.cache else fresh.concat(prior),
            cacheColumns: if (Mutation == "columns") reverse(DeclaredColumns) else DeclaredColumns,
            cacheVersion: x.version + 1, stage: 1,
            viewValid: if (Mutation == "extend-view") x.viewValid else false
          }
        } else if (Mutation == "foreign") {
          { ...old, cache: x.remaining.head().concat(old.cache) }
        } else old
      })
    }
  }

  action install(o: int): bool = {
    val x = owners.get(o)
    all {
      x.remaining.length() > 0,
      x.stage == 1 or (x.stage == 0 and Mutation == "early"),
      owners' = owners.set(o, { ...x,
        rows: x.remaining.head().concat(x.rows), version: x.version + 1,
        published: x.remaining.head().concat(x.rows),
        stage: if (x.remaining.length() == 1) 2 else 0,
        remaining: x.remaining.tail(),
        held: if (Mutation == "held") x.cache else x.held,
        heldColumns: if (Mutation == "held-columns") reverse(DeclaredColumns) else x.heldColumns
      })
    }
  }

  action failExtend(o: int): bool = {
    val x = owners.get(o)
    all {
      x.stage == 0, x.remaining.length() > 0,
      owners' = owners.set(o, { ...x,
        cache: List(3).concat(x.cache),
        cacheVersion: if (Mutation == "failed") x.version else -1,
        stage: 3, viewValid: if (Mutation == "failed-view") x.viewValid else false
      })
    }
  }

  action rebuild(o: int): bool = {
    val x = owners.get(o)
    all {
      x.stage == 3,
      owners' = owners.set(o, { ...x,
        cache: x.rows,
        cacheColumns: if (Mutation == "rebuild-columns") reverse(DeclaredColumns) else DeclaredColumns,
        cacheVersion: x.version, stage: 0, viewValid: Mutation == "rebuild-view",
        viewRows: if (Mutation == "rebuild-view") x.cache else x.rows
      })
    }
  }

  action readView(o: int): bool = {
    val x = owners.get(o)
    all {
      Set(0, 2).contains(x.stage), x.cacheVersion == x.version,
      owners' = owners.set(o, { ...x, viewRows: x.rows, viewValid: true })
    }
  }

  action step = {
    nondet o = Owners.oneOf()
    any { extend(o), install(o), failExtend(o), rebuild(o), readView(o) }
  }

  val Consistent = Owners.forall(o => {
    val x = owners.get(o)
    x.stage != 1 implies all {
      x.cacheVersion == x.version implies
        (x.cache == x.rows and x.cacheColumns == DeclaredColumns),
      x.stage == 2 implies x.cacheVersion == x.version,
      x.published == x.rows
    }
  })
  val HeldStable = Owners.forall(o => {
    val x = owners.get(o)
    x.held == x.heldTruth and x.heldColumns == x.heldColumnsTruth
  })
  val PrivateExtension = Owners.forall(o => {
    val x = owners.get(o)
    x.stage == 1 implies x.published == x.rows
  })
  val ViewConsistent = Owners.forall(o => {
    val x = owners.get(o)
    x.viewValid implies all {
      Set(0, 2).contains(x.stage), x.cacheVersion == x.version, x.viewRows == x.rows
    }
  })
  val safety = Consistent and HeldStable and PrivateExtension and ViewConsistent
}

module ComponentIndexFixture {
  const Fault: str
  import ComponentIndex(Owners = Set(1, 2), Mutation = Fault,
    Inputs = List(List(3, 2), List(4, 3)), DeclaredColumns = List(0, 1)).*
}
