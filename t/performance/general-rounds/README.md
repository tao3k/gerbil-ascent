# Prepared general binary rules and per-round delta indexes

This commit optimizes the complete general binary fixed point: immutable rule
preparation, recursive execution, delta index lifecycle, and result publication.
The exact preceding committed source is recorded in `baseline.txt`; its table
and binary evaluator are frozen under renamed exports and redirected imports.
No new query type or compatibility layer is introduced.

## Execution changes

The previous general evaluator resolved rule kinds, relation names and filter
predicates during every round. It also allocated a new adjacency index for
every relation appearing as a join right input in every round, including
unchanged source relations and empty derived relations.

The candidate prepares positional instructions once, after validation and
specialized dispatch. Instructions preserve declaration order and retain the
validated predicate. It creates the next delta index only for an indexed
relation with pending new facts. The accumulated all-index remains available
for left-delta joins. An empty right delta needs no delta-index; if that right
input becomes active later, its index is created when new facts commit.

Filtering keeps its existing two-phase behavior: finish all predicate calls
for the delta before emitting accepted facts. This preserves observable guard
traces and budget error timing. The join traversal order, pending epochs,
commit order, positive path semantics, budgets and canonical result rows are
unchanged. Specialized closure queries do not prepare general instructions.
Persistent publication uses the preceding commit's implementation.

## Qualification contract

`criteria.json` fixes 20 warmups, two runs of 1,000 alternating paired samples,
strictly lower p50 and at least 900 strict paired wins in both runs for timing
qualification. Controls are single copy/join/filter and two specialized closure
queries; no control may regress by more than 10 percent p50 in either run.
No allocation claim is made. Equality of full canonical outputs is checked
outside timing; timers include evaluation and complete pair-list publication.

The seeded chain/cycle profiles force general execution. The many-right-input
profiles have 8 or 32 independent seeded heads extending along read-only
19-edge chains, at radix 32, 128, or sparse radix 513. They exercise repeated
rounds where source deltas become empty after initialization. Input programs
and immutable source sets are constructed outside timers.

The oracle forces general execution for exhaustive 512 three-node graph
closures at radix 3 and 32, including seeded heads and budget errors. It also
checks dense/sparse boundaries, guard traces, native set snapshots and public
list edits against the preceding reference. Two new permanent regressions
cover a dormant indexed right input becoming active after several rounds and
completion of filter callbacks before a budget failure. Existing multi-head
and two-changing-input join cases remain in the full suite.

A benchmark script's initial missing closing parenthesis is preserved in
`probe-syntax-error-*`. That run did not execute performance samples and is
not successful qualification evidence.

## Reproduction

```sh
GERBIL_PATH=/private/tmp/ascent-asp-v0122-gerbil GERBIL_BUILD_CORES=12 \
  python3 tools/test_execution.py run -- \
  python3 t/performance/general-rounds/qualify.py
python3 t/performance/general-rounds/report.py
GERBIL_PATH=/private/tmp/ascent-asp-v0122-gerbil GERBIL_BUILD_CORES=12 \
  python3 t/performance/general-rounds/production.py
GERBIL_PATH=/private/tmp/ascent-asp-v0122-gerbil \
  python3 t/performance/general-rounds/verify.py
```

Run the production collector after the paired collector releases its lease.
Performance collection uses one exclusive lease; the functional suite starts
outside it and uses the configured native module scheduler. Four comparison
imports must resolve to compiled modules. Source hashes, native artifacts,
frozen reference identity and the full external dependency artifact set are
checked. These are bounded local receipts; they do not establish remote CI.

## Native matched results

Both runs completed on the same unchanged compiled source/dependency snapshot.
Three profiles meet the predeclared timing qualification. Five control
profiles have equal or lower p50 in both runs and meet the regression bound.

| Profile | First p50 old → new (µs) | Repeat p50 old → new (µs) | Strict wins / 1000 | Timing qualified |
| --- | ---: | ---: | --- | --- |
| seeded-chain-20 | 54 → 42 | 54 → 42 | 961, 958 | yes |
| seeded-chain-32 | 100 → 82 | 100 → 81 | 903, 924 | yes |
| seeded-chain-48 | 193 → 163 | 193 → 164 | 863, 868 | no |
| seeded-degree-2-16 | 60 → 54 | 61 → 55 | 930, 880 | no |
| seeded-degree-2-32 | 174 → 163 | 173 → 163 | 819, 840 | no |
| right-inputs-8-32 | 195 → 128 | 196 → 129 | 960, 917 | yes |
| right-inputs-32-32 | 783 → 505 | 753 → 487 | 864, 910 | no |
| right-inputs-32-128 | 920 → 577 | 866 → 555 | 849, 882 | no |
| right-inputs-8-513 | 291 → 192 | 280 → 186 | 853, 940 | no |
| general-copy-32 | 232 → 230 | 231 → 230 | 522, 573 | no |
| general-join-32 | 51 → 51 | 52 → 52 | 433, 450 | no |
| general-guard-32 | 257 → 225 | 256 → 223 | 811, 964 | no |
| specialized-chain-20 | 40 → 40 | 39 → 39 | 460, 363 | no |
| specialized-degree-31-32 | 596 → 595 | 607 → 605 | 440, 577 | no |

Qualified seeded chains improve by about 22 percent (20 nodes) and 18 percent
(32 nodes). Eight independent right inputs at radix 32 improve by about
34 percent. The 32-right-input profiles, sparse radix-513 profile, larger
chain/cycle profiles and the single filter profile improve median timing but
miss the required 900 strict paired wins in at least one run. They are **not
timing qualified**. The same unchanged snapshot is not rerun to alter these
classifications. Raw arrays, independently recomputed p50/p95 and strict wins
are retained in `first.sexp`, `repeat.sexp` and `report.json`.

## Original production gate boundary

Policy, original membership, closure and binary-program gates pass. The
unchanged table-expression gate fails: first p50 300 µs / p95 6,178 µs; its
one permitted exact-snapshot recheck has p50 311 µs / p95 7,907 µs. Both p95
values exceed the original 2,000 µs maximum. `projection-failures.json`
independently recomputes both values from each raw 1,000-sample receipt.

The table-expression source is byte-identical to the preceding commit, and
the recheck reused the same compiled production snapshot. `host-load.log`
records a high observed host load; that observation does not establish the
cause of the percentile failures. This gate remains **unpassed**. Neither
the admission threshold nor sampling count is changed, and there is no
second recheck. Both failed logs and the initial collector failure are kept.
The full functional suite runs after releasing the performance lease even
though the aggregate performance qualification remains incomplete.

## Final functional and native audit

All 41 production modules resolve to one newly compiled snapshot. External
ASP v0.1.2.2 / POO dependency pins and 1,080 native external artifacts remain
unchanged. The full functional suite passes **48 modules / 378 Cases** in
491.5 seconds, including both new regressions, under the unchanged per-module
deadlines and 600-second aggregate collector bound. It schedules 33 shared
modules with the configured 12-worker pool, followed by 15 isolated modules.
Every Case, module, harness and final OK marker is checked, with exit 0 and no
overflow/error markers. Per-module logs and complete coverage are retained.

The three passing original performance gates report p95: membership 32 µs
(maximum 500 µs), closure 101 µs (maximum 1,000 µs), binary program 100 µs
(maximum 2,000 µs). Policy reports zero findings and zero errors. **Aggregate
original performance qualification remains incomplete** because table
expression fails its original 2,000 µs p95 gate, including its one recheck.
Functional success and matched general-path qualification do not override
that failure.

`verify.py` rechecks the comparison/production source and native artifact
hashes, recomputes paired statistics, audits all functional receipts, and
records the failed gate separately in `final-audit.json`. It accepts only the
recorded unchanged table-expression budget failure as an outstanding gate;
it does not classify the failed performance logs as passes. Git blob identities
for production and permanent regression sources allow post-commit verification.
No remote CI or deployment claim is made.
