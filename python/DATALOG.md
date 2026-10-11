# Relational Datalog Binding

`ascent_engine.datalog` translates relational text into the existing native
declarative contract. It does not evaluate rules in Python. Joins, recursive
closure, stratified negation and completed-component reuse run through
`EvidenceChain` in the Scheme shared library via the CFFI API.

```python
from ascent_engine import Engine
from ascent_engine.datalog import evaluate

with Engine() as engine:
    answers, evidence = evaluate(
        engine,
        {"edge": [["a", "b"], ["b", "c"]], "blocked": [["c"]]},
        "path(X,Y) <= edge(X,Y)\n"
        "path(X,Y) <= edge(X,Z) & path(Z,Y)\n"
        "usable(X,Y) <= path(X,Y) & ~blocked(Y)",
        {"reachable": "path(X,Y)", "usable": "usable(X,Y)"},
    )
```

`compile_program` provides the native contract and named query mapping without
loading the runtime. It uses Python's AST parser, never `eval`. Demand slicing
retains every rule alternative and every positive/negative dependency of the
requested relations. It is not a filter over facts or unsuccessful derivations.
String/integer cells are JSON-tagged symbols, so integer `1` and string `"1"`
remain different. Variables must be bound in a positive relational atom.

Before native execution, `evaluate` interns every symbol through a
collision-checked SHA-256 token and decodes the answers without truncation.
This allows long evidence text and empty strings without widening the C ABI's
identifier bound. Numeric and boolean cells in typed mode are not interned.
Raw `compile_program` output keeps its original values; direct low-level callers
remain responsible for the native wire contract. No unknown returned token is
accepted as a new scalar.

`evaluate` checks a repeated query within the same retained evidence chain,
returns decoded answers and native source/path identities, and closes that
chain. Callers needing reuse across different queries or source replacement
can use the existing public `EvidenceChain` with `compile_program` contracts.

## Checked Operators

With an explicit `schema` mapping each relation to its column kinds (`symbol`,
`integer`, `boolean`), the text binding also accepts:

```python
answers, evidence = evaluate(
    engine, {"number": [[2], [5], [8]]},
    'selected(Y) <= number(X) & where("even?", X) & (X < 8) & bind(Y, X + 1)\n'
    'total(T) <= reduce(T, "sum", selected(Y), Y)',
    {"selected": "selected(Y)", "total": "total(T)"},
    schema={"number": ["integer"], "selected": ["integer"], "total": ["integer"]},
)
```

`bind(Y, X)` uses the checked identity operator. Reductions are `count`, `sum`,
`min` and `max`; count has no value input, e.g. `reduce(N, "count", number(X))`.
Bound variables in the aggregate relation select a group; unbound variables are
local to the aggregate. Empty count/sum yield zero; empty min/max yield no row.
Types, arity, unsafe bindings and recursive aggregation are checked by Scheme.
Typed mode preserves native integers/booleans instead of tagged string cells.

`ascent_engine.operators.where/compute/reduce` also build these same inert JSON
clauses directly for `Engine.open` and `EvidenceChain`. No arithmetic or reducer
is implemented in Python. The engine delegates to its existing closed
`relational-where`, `relational-compute` and `relational-reducer` constructors.
The component graph includes aggregate dependencies, excludes nonrelational
operators, and fingerprints operator names, literals, outputs and value inputs.
Changing a scalar operator invalidates its component while an unchanged completed
aggregate may be reused. Source replacement invalidates derived evidence.

## Deliberate Boundary

This exposes every operator in the existing **closed checked-operator surface**,
not every Scheme procedure. Arbitrary closures, unregistered operators,
floating-point reducers such as the general Scheme `mean`, custom lattices and
generators are not represented by this contract. They require their own typed
wire semantics and native qualification; labels must never authorize executable
Python/Scheme code. The reverse Scheme-to-wire serializer remains relational-only.
These are declared API boundaries, not claims of missing Scheme functionality.

## Native Qualification

Local Darwin qualification on 2026-10-11 used the normal `gerbil build`, a newly
linked AOT engine and a new CFFI extension compiled with GNU GCC 16.2.0.
`test_datalog`, `test_review` and `test_binding_modes` passed 29 tests in 21.077
seconds. This includes all advertised checked operators, grouped/empty
reductions, invalid type/arity/operator rejection, negative and aggregate cycles,
component reuse after operator changes, source withdrawal, error recovery and
C ABI lifecycle checks. The research consumer's 35 focused tests passed in
30.570 seconds, including actual query equivalence and retry-denial cases.

The first library link failed because the SDK referenced an absent OpenSSL
Cellar version. Already-built objects were retained; explicit `LDFLAGS` selected
the installed compatible library and `ascent_engine.build --relink` succeeded.
This option refuses missing/stale generated C, link and object artifacts using
dependency modification times, and records hashes of the linked inputs. It is
not a compiler/source proof or a replacement for the normal Gerbil build.

The qualified extension hash is
`3534343ae0f915cb2ad007ad02513dfaea9941fa4501c78fac6e33e6de3dcb8d`;
its bundled library hash is
`7cb0b4265ea88c2fe91a7fe401b2b127d329e7262b009d5bb743dba9cc1ddaa1`.
These are local interface checks, not a portable-wheel, Linux, full ASCENT-suite
or Gambit three-flags/GC/bootstrap qualification. No remote publication occurred.

Unsupported syntax on a requested dependency slice raises an error. Native
errors propagate; there is no pyDatalog fallback. These results concern only
the supplied facts and rules, not the authenticity/completeness of evidence,
permission to execute a candidate, or Gambit SMP correctness.
# Inferred Column Types

`compile_program` and `evaluate` also accept `schema="infer"`. Column kinds
are constrained by source scalar types, constants, rule-local variable joins
and checked operator signatures. Empty unconstrained columns default to symbol;
numeric operator inputs are integer even when their source is empty. A mixed
column or incompatible join fails rather than coercing a string to a number.
Default untyped mode still preserves heterogeneous scalar identity through its
existing tagged symbols. This is static wire typing, not Python evaluation of
filters, arithmetic or aggregate results; those remain Scheme operations.
