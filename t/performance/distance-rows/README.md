# Optional distance rows in the production relation engine

## Historical collector retirement (2026-10-07)

This directory records a historical measurement, not a current execution entry.
The one-shot Python collectors and continuation scheduler were removed after
the Scheme harness migration. Their original code remains in Git commit
0f20eb900d5a082e445d93e574c4d71eed0b29cb. Retained receipts and negative results
refer to their recorded source versions; they do not qualify current source.
Use `just test`, `just test-file <module>` and `just performance` through the
current Scheme harness for current acceptance. Scheme benchmark/reference
modules remain available. Collector names below describe historical work.


## Scope

This is the production integration of the distance-storage seam identified by
`row-propagation`. The production source is `table/expression.ss`, and the
preceding implementation is frozen from commit `b61e8f5` in `reference.ss` with
only two export names changed. The adjacency representation, frontier algorithm,
POO public slots, callback route, pair publication and closure budgets remain
under the existing relation engine.

Dense distance storage now contains `radix` optional rows. A row of `radix`
boxed entries is created only when that encoded origin discovers a result.
Absent rows and entries mean no positive path. Boxed depths avoid adding a
numeric bound on the general callback route. Radix above 512 retains hash
storage. Canonical native neighbors use row addressing in their existing target
order, so repeated candidate pair decoding is removed. General callbacks still
admit encoded pairs through the original semantic path. Discovery bookkeeping
is shared between both routes; public distance lookup validates its input and
returns a depth or false.

This improves a whole demand path rather than adding a separate strategy
selector. Empty dense queries reserve `radix` distance cells instead of
`radix squared`. With `r` reached origins, the distance vectors contain
`radix + r * radix` cells, plus row headers. This is a representation count,
not a measured heap or allocation reduction. Every expression owns its rows;
there is no global cache, new dependency, thread or test-scheduling change.

## Evidence and reproduction

The retired collector commands are available in the frozen Git commit above.

The native collector reconstructs the exact reference from Git, builds both
implementations privately, and retains source and compiled artifact hashes.
The benchmark verifies both actual SSI resolution paths, includes expression
construction and all demanded outputs in each timer, and compares equal outputs
outside measurement. Each of two runs uses 20 warmups and 1000 alternating
paired samples. Three primary controls are empty, sparse and single-origin
distance demands at radix 512. Other controls include complete demand, high
fanout, short/long chain distances, closure, projection, and sparse radix 513.
All original timing profiles and budgets remain unchanged.

Only time is collected here. Earlier allocation counter deltas had negative
values and allocation qualification remains withdrawn. This study neither
filters those earlier observations nor substitutes retained-memory numbers for
allocation. Timing qualification requires a lower median and at least 900
strict paired wins in both runs. Raw timings, p95s and every regression remain
in the receipts. The primary workloads must meet that criterion.

`oracle.ss` checks all 512 directed three-node graphs against independent
positive-path Floyd-Warshall, the preceding engine's projections, and closure
budget boundaries. Word/fixnum/dense-limit boundary queries include invalid
inputs. Long cycles at 512 and 513 check positive self-distances and all targets
from two extreme origins. Snapshot withdrawal/replacement happens after the
old distance result has been demanded. A custom callback checks exact output
and call sequence, including a target that aliases another origin under the
existing encoded-pair interpretation.

The initial native build caught a parallel `let` binding referencing `from` in
its sibling `depth` initializer. It was changed to `let*` before any passing
measurement. The failed build and collection logs remain preserved.

## Matched timing results

| Demand | First old / new us | Repeat old / new us | Wins / 1000, first / repeat | Qualified speedup |
|---|---:|---:|---:|---|
| complete-16 | 69 / 67 | 68 / 67 | 731 / 731 | False |
| complete-fanout-32 | 1168 / 979 | 1213 / 1015 | 752 / 723 | False |
| distance-chain-32 | 51 / 51 | 51 / 51 | 464 / 479 | False |
| distance-chain-128 | 453 / 445 | 444 / 439 | 623 / 667 | False |
| closure-chain-32 | 43 / 43 | 44 / 44 | 295 / 373 | False |
| projection-256 | 299 / 298 | 302 / 302 | 451 / 427 | False |
| empty-distances-512 | 111 / 15 | 111 / 16 | 986 / 984 | True |
| sparse-distances-512 | 112 / 18 | 113 / 19 | 984 / 978 | True |
| single-origin-512 | 113 / 19 | 115 / 21 | 985 / 981 | True |
| empty-distances-513 | 14 / 14 | 15 / 15 | 314 / 345 | False |
| sparse-distances-513 | 17 / 17 | 17 / 17 | 334 / 319 | False |

The three primary sparse-demand cases all qualify, with 978–986 strict paired
wins per run. Chain distance and unmodified closure/projection controls retain
similar medians; this is bounded local evidence rather than a universal
non-regression guarantee. Full fanout medians improve but their paired win counts
remain below 900, so a stable high-fanout speedup is not claimed. Sparse radix 513
is a control, not a new optimized storage regime.

## Production qualification

All 41 production modules were compiled into one private snapshot, and all
actual module resolution paths were verified. The policy build completed with
zero findings/errors. Original membership and closure performance gates passed
with p95 28 us and 120 us respectively. The original projection gate first hit
its unchanged 120-second runtime timeout without a completed benchmark receipt.
It then passed on an exact-snapshot recheck, without source, dependency, sample
count, fixture or budget changes. The timeout cause is unconfirmed. Original
and failed logs, initial gate statuses, the recheck and effective statuses are
all preserved; this is local qualification rather than a remote CI result.

The projection recheck produced candidate p95 914 us under the original 2000 us
budget, with equal projection results. The complete functional suite passed
48 modules and 373 native Cases in one zero-failure run. Every Case, Module,
Harness and final OK marker was checked, and error/overflow markers rejected.
The suite ran outside the exclusive measurement lease using the same production
snapshot. Paired sources/artifacts, all 41 production sources/artifacts and
installed dependency hashes still matched after completion. No dependency pin,
timing fixture or per-Case budget was changed.

A first final audit omitted GERBIL_PATH and compared the default user profile
to the pinned test profile. It was rejected; repeating with the snapshot's
explicit GERBIL_PATH verified all dependency hashes. No dependency artifacts
changed, and both suite-boundary checks already used the explicit profile.
