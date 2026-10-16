<!-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors -->
<!-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later -->

# ASCENT Workbench

An independent Python project that consumes the public `ascent` Library.
It owns research experiments, provider byte IO, process supervision, formal
qualification and native consumer tests. It does not implement relational truth
or distribute the Library's bindings.

The two projects have separate package metadata:

| Project | Package | Responsibility |
| --- | --- | --- |
| `python/` | `gerbil-ascent` | Public Python bindings and Library artifacts |
| `workbench/` | `ascent-workbench` | Downstream experiments and qualification |

For a local checkout, install both projects independently:

```console
python3 -m pip install -e ./python -e ./workbench
```

The workbench declares `gerbil-ascent` as a dependency. Its uv source declaration
selects the adjacent Library project for local development. The Library has no
dependency on the workbench.

Run from the checkout root, using installed packages:

```console
ascent-workbench formal all
python3 -m unittest discover -s workbench/tests -v
ascent-workbench native-tests
```

Formal qualification retains all models, exploration constants and original
fault checks. The finite accounting observations have Lean simulation and safety
equivalence laws. Every TLC check still executes; only source-bound compilation
artifacts can be reused. Processes share the original whole-run deadlines, and
native capacity determines independent checker concurrency.

Native consumer tests use the installed Rust/PyO3 wheel and matching Gerbil
syntax resources. The consumer verifies build-frozen source/resource identities.
The original Scheme implementation owns DSL loading and host evaluation; Rust
owns finite execution, resource admission and checked provenance.
Run logs and checker outputs stay under `.cache/ascent/`.

Research records and archived source snapshots retain their original bytes,
paths and hashes. Moving the active producer does not transfer a frozen plan's
authorization or qualify an old receipt against the new producer.

## Benchmark orchestration

Rust owns Cargo `benches/` targets in each crate. Python measurement drivers
are workbench modules (`python3 -m ascent_workbench.benchmark_run_hybrid`,
`benchmark_run_comparison`, `benchmark_run_paired`, and `benchmark_run_multivm`).
Run from the checkout root with the workbench installed. Pass output directories
under `.cache/ascent/`; raw samples, stdout/stderr and generated receipts are
local artifacts, not versioned source. Historical reports live in
`docs/performance/rust/`. Moving a producer does not requalify historical timings.


## Qualification responsibilities

| Directory | Required environment | Responsibility |
| --- | --- | --- |
| `tests/` | Python and installed public bindings | Host orchestration, inventory and admission unit tests |
| `source_tests/` | Maintainer checkout with installed Gerbil SDK | Independent Scheme-source API oracle and compiler/linker environment controls |
| `engine_tests/` | Installed wheel and its declared runtime resources | Complete downstream consumer matrix; no external SDK or `gxi` requirement |

CI runs `python3 -m unittest discover -s workbench/source_tests -v` in the
Scheme maintenance job. Installed-wheel consumers retain their complete native
inventory, original whole-matrix deadline, source checks and SDK-hidden controls.
Source-dependent tests remain mandatory in their separate qualification domain;
no unavailable-SDK skip or downstream SDK installation is introduced.
