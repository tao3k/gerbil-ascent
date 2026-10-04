<!-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors -->
<!-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later -->

# gerbil-ascent

gerbil-ascent is a research implementation of relational reasoning in Gerbil.
It studies how checked Scheme programs can derive finite relations, retain
results across source changes, and return bounded evidence tied to exact
snapshots. Rust Ascent is a comparison oracle; Gerbil POO and POO Flow Core
provide the native foundation.

## Research directions

- **Language and semantics:** first-class relational programs and fragments,
  checked composition, finite higher-order operators, and the link from the
  Scheme compiler to formal models.
- **Evaluation and change:** fixed-point execution, indexes and storage,
  retained Sessions, source replacement, and measured update costs.
- **Reasoning evidence:** inert candidate rules, admission diagnostics,
  finite closure, founded support, and bounded ground nonmembership.
- **Time and context:** valid time, knowledge time, named causal cuts, and
  snapshot-bound temporal answers.

The checked Scheme language, evaluator, candidate boundary, and finite
temporal lens are implemented. Formal results cover selected abstract laws;
they do not yet prove the native compiler or runtime correct. Full Rust
replication, general deletion deltas, exhaustive provenance, and external
source or causal authority remain open research gates.

## Read the work

- [Native Library contract](docs/native-library-acceptance.org) — implemented
  language, admission, and result boundaries.
- [Research and proof audit](docs/scheme-research-proof-audit.org) — papers,
  code, formal results, and remaining obligations.
- [Agent inference research](docs/research/agent-inference/index.org) —
  candidate reasoning and model evaluation questions.
- [Temporal design](docs/temporal-causality-module-design.org) — implemented
  finite lens and broader temporal questions.
- [Rust parity matrix](docs/rust-parity.org) — differential qualification and
  the separate replication claim.

## Run

```sh
gerbil deps --install
just build
just test
```

`just oracle` runs the Rust comparison; `just performance` runs the
benchmark suite. See `just --list` for focused checks.

The project is licensed under `Apache-2.0 AND LGPL-2.1-or-later`; see
[LICENSE](LICENSE). It builds on the
[Ascent](https://doi.org/10.1145/3497776.3517779) and
[BYODS](https://doi.org/10.1145/3622840) research.
