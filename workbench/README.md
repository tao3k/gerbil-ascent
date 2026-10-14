<!-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors -->
<!-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later -->

# ASCENT Workbench

An independent Python project that consumes the public `ascent_engine` Library.
It owns research experiments, provider byte IO, process supervision, formal
qualification and native consumer tests. It does not implement relational truth
or distribute the Library's bindings.

The two projects have separate package metadata:

| Project | Package | Responsibility |
| --- | --- | --- |
| `python/` | `ascent-engine` | Public Python bindings and Library artifacts |
| `workbench/` | `ascent-workbench` | Downstream experiments and qualification |

For a local checkout, install both projects independently:

```console
python3 -m pip install -e ./python -e ./workbench
```

The workbench declares `ascent-engine` as a dependency. Its uv source declaration
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

Native consumer tests require an explicitly prepared Library, API backend and
wire fixture. Scheme owns compilation, source admission and query semantics.
Run logs and checker outputs stay under `.cache/ascent/`.

Research records and archived source snapshots retain their original bytes,
paths and hashes. Moving the active producer does not transfer a frozen plan's
authorization or qualify an old receipt against the new producer.
