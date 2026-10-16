# Caller-Owned Cardinality And Transport Policy

ASCENT is a native Library for Agentic AI. Its ordinary Program constructor,
`ascent` form, operator compiler, operator reference evaluation and positive
insertion graphs now default to unlimited fact/row counts (`+inf.0` in Scheme).
This is not a large replacement integer. Existing explicit finite DSL bounds
are retained. Infinity is reported as `"unlimited"`, as a typed policy value.

Python callers can impose native ceilings without parsing or rewriting DSL:

```python
from ascent import Engine, FactLimits

source = """
(define-evidence (make-events)
  (gerbil-ascent-program
    (list (gerbil-ascent-relation 'event 1 [])) []
    +inf.0 +inf.0 +inf.0 '(event)))
"""

engine = Engine()  # No request-byte ceiling by default.
with engine.evidence(source, "make-events", trusted=True) as session:
    assert session.fact_limits["input"] == "unlimited"
    session.replace({"event": [[1], [2]]})
    result = session.run(queries=["event"])

with engine.evidence(source, "make-events", trusted=True,
                     limits=FactLimits(input=1000, derived=5000, output=6000)) as session:
    pass
engine.shutdown()
```

`None` fields mean no caller ceiling. Native Scheme validates positive exact
integers and enforces total source occurrences, derived facts and materialized
output, not merely per-relation unique rows. Caller limits may tighten explicit
DSL declarations, never loosen them. The native session's `fact_limits` receipt
reports effective limits. Ceilings are available on `Engine.open`, `open_sources`,
`open_module`, `evidence` and the existing `EvidenceStore`/`EvidenceChain` wrappers.
Retained-session identities include the caller count policy.

Load shared definitions once when constructing many independent sessions:

```python
with Engine() as engine:
    with engine.dsl(source, trusted=True) as definitions:
        for rows in ([[1]], [[2]]):
            with definitions.evidence("make-events", limits=FactLimits(input=1000)) as session:
                session.run(queries=[])
                session.replace({"event": rows})
                receipt = session.run(queries=["event"])
```

`Module.evidence` invokes the Scheme constructor anew but does not reread or
expand the already-loaded definitions. Programs, effective limits, sessions
and explanations remain independently owned. Closing the definition owner
prevents new construction; existing sessions retain their Program/explanation.
This is explicit ownership, not an implicit global cache or a reset of scope
accounting. Source identity and authorization must still be checked by the host.

Python executor threads may supervise independent child processes. They may
not enter a shared Engine: the C ABI runtime remains bound to its initializing
OS thread. Scheme Actor Session and Actor Round scheduling are internal public
Library capabilities with their own pure-graph/provider admission contracts;
green-thread availability does not establish C ABI thread safety or multi-core
speed. Arbitrary actor resources require an explicit Scheme close operation.

Request bytes are a separate transport policy. `Engine(max_request_bytes=...)`
checks the exact UTF-8 JSON request length; the default `None` has no ceiling.
The ABI retains allocation-overflow, UTF-8 and NUL validation. Trusted host code
can still exhaust memory. This interface is not a sandbox or an authorization
mechanism, and an unlimited count does not guarantee termination or completion.

DSL scopes have no default cumulative ceiling. `Engine(max_source_scopes=64)`
sets an optional ceiling on the shared runtime's cumulative admitted scopes,
not the caller's live owners. Failed expansions consume admissions; malformed
definitions rejected before expansion do not. Closing owners or constructing
another Engine does not reset this count. The policy travels with each source
or component request, so one caller cannot silently change another's policy.
Component closure admission is preflighted against the same total. `describe`
reports `sourceScopes`; unlimited admission is not expander-memory reclamation.

Independent structural and lifecycle constraints remain: DSL source/form/tree
bounds, component inventory/session/value limits, symbol codec constraints and native
graph projection limits. A projection failure retains native results; it must
not reduce executable semantics. Runtime deadlines and host watchdogs are
independent of cardinality. Cooperative run deadlines do not preempt arbitrary
Scheme callbacks or qualify every admission/extraction phase.

Consumers import Python only and supply ordinary DSL definitions. Scheme module
imports, hygienic expansion, inference, aggregation, lattice and incremental
state remain in the Library. Maintenance builds belong to Library `build.ss` /
`defbuild-script` / upstream `std/make`, not a downstream compilation workflow.
