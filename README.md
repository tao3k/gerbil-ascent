<!-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors -->
<!-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later -->

# ASCENT

ASCENT is a [Gerbil Scheme](https://cons.io/) library for relational and logical
programming. It brings checked rule declarations, fixed-point evaluation,
versioned sessions, and derivation evidence into Scheme. Its research asks how
an engine can reuse work across changes while keeping the meaning and evidence
of each result explicit.

## Research directions

- **Language and semantics.** The Scheme DSL supports recursive rules,
  stratified negation, aggregates, and lattices. Its positive finite-choice
  fragment adds dynamic grounding and bounded search inspired by Dusa.
  [Finite-choice semantics and implementation](dev/finite-choice/README.org)
- **Evaluation and change.** Semi-naive evaluation uses new facts to drive
  recursive joins. Retained Actor sessions can reuse state across source edits.
  Specialized reachability queries use strongly connected components and
  versioned integer adjacency. Ordered integer results can be delivered into
  caller-owned buffers. [Reachability and edit costs](docs/development/bound-reachability.org)
  | [Result delivery](docs/development/source-row-transport.org)
- **Evidence and time.** Bounded derivation witnesses and replay are tied to
  a source version. Temporal queries use an explicit event cut. Verification
  of a derivation establishes support under the admitted rules and source
  facts. Application policies and agent workflows belong to
  [Agentic AI Lab](https://github.com/tao3k/agentic-ai-lab).
- **Validation and cost.** Lean checks mathematical obligations, Quint
  explores protocol behavior, and native tests compare execution with
  independent oracles. Benchmarks distinguish construction, updates, first
  queries, and result delivery. Each check has its documented scope.
  [Semantic and performance acceptance](docs/library-acceptance.org)

## Try it in Scheme

From a checkout with Gerbil, a C toolchain, and OpenSSL discoverable by
`pkg-config`, install the declared dependencies and build the library.

```sh
gerbil deps --install
just build
gerbil test t/qualification/ascent-condensed-session-test.ss
```

`just build` invokes `gerbil build` with the project's compiler environment.
The example below can be evaluated in Gerbil once the library is on its load
path.

```scheme
(import :gerbil-ascent/program/api)

(def graph
  (relational-program
    (relation edge (from to) '((0 1) (1 2)))
    (relation reach (from to))
    (rule (reach ?x ?y) (edge ?x ?y))
    (rule (reach ?x ?z) (reach ?x ?y) (edge ?y ?z))
    (limits 32 64 128)))

(def result (relational-solve (relational-admit graph)))
(relational-query-name result 'reach)
;; The result includes (0 2), inferred from (0 1) and (1 2).
```

## Execution and reproducibility

Scheme owns the DSL and host callbacks. Rust/PyO3 exposes the library to Python,
and supported finite projections can run on the Rayon backend. Downstream
callers load Scheme DSL at runtime. Upstream Rust Ascent serves as an independent
development and benchmark reference.
[Rust integration](rust/README.md) | [Python bindings](python/README.org)

Use the [benchmark guide](benchmarks/README.org) for workload definitions,
commands, and measurement boundaries. The maintained
[related-work matrix](docs/related-work-matrix.org) records the broader research
questions and the corresponding implementation and evidence.

## Selected papers

- Arash Sahebolamri, Thomas Gilray, and Kristopher Micinski. [Seamless Deductive Inference via Macros](https://s-arash.github.io/ascent/cc22main-p95-seamless-deductive-inference-via-macros.pdf), CC 2022.
- Chris Martens, Robert J. Simmons, and Michael Arntzenius. [Finite-Choice Logic Programming](https://arxiv.org/abs/2405.19040v3), POPL 2025.
- Ashish Gupta, Inderpal Singh Mumick, and V. S. Subrahmanian. [Maintaining Views Incrementally](https://sigmodrecord.org/1993/06/03/maintaining-views-incrementally/), SIGMOD 1993.
- Todd J. Green, Grigoris Karvounarakis, and Val Tannen. [Provenance Semirings](https://www.cs.ucdavis.edu/~green/papers/pods07.pdf), PODS 2007.
