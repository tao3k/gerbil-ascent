<!-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors -->
<!-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later -->

# gerbil-ascent

Scheme-native ASCENT relation evaluation built on Gerbil POO and POO Flow Foundation.
The package owns binary relation rules, bounded closure, candidate projection,
unit and performance qualification, and a test-only differential oracle against
Rust Ascent. POO Flow consumes it as a pinned submodule. MRR owns the semantic
adapter and admission of its own evidence.

```sh
gerbil deps --install
gerbil build
just test
just oracle
```

The Rust oracle is a qualification dependency, not part of the Scheme runtime.
