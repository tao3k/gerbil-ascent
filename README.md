<!-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors -->
<!-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later -->

# gerbil-ascent

Scheme-native ASCENT implementation built on Gerbil POO and POO Flow Foundation.
Each top-level directory is a Gerbil module namespace:

| Namespace | Current responsibility |
| --- | --- |
| `:gerbil-ascent/core/*` | Rule evaluation and fixed-point execution |
| `:gerbil-ascent/table/*` | Relation storage, indexes, and projections |
| `:gerbil-ascent/candidate/*` | Experimental candidate and support projection |
| `:gerbil-ascent/interface/*` | Inert request projection |

`t/` contains Scheme qualification; `rust/ascent-oracle/` contains the
test-only Rust Ascent differential oracle. The [parity matrix](docs/rust-parity.org)
tracks the unfinished Rust 0.8.0 feature surface. Complete Scheme parity is
the gate before new Agent-specific extensions. POO Flow consumes this package
as a pinned submodule. MRR owns the semantic adapter and admission of its
own evidence.

```sh
gerbil deps --install
gerbil build
just test
just oracle
```

The Rust oracle is a qualification dependency, not part of the Scheme runtime.
