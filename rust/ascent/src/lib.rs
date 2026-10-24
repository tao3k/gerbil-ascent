//! Scheme-defined relational composition lowered to Rust and caller-owned Rayon pools.
//! The supported boundary is finite typed sets and stratified negation.
mod catalog;
mod data;
mod error;
mod execution;
mod fact_limits;
mod frozen;
mod graph;
mod lattice;
mod loaded;
mod model;
mod module_input;
mod numbers;
mod object_graph;
mod operators;
mod provenance;
mod reachability;
mod relational_graph;
mod session;
mod source;

// Group the stable public surface by ownership without changing public paths.
pub use {
    catalog::Catalog,
    data::Data,
    error::{Error, Result},
    fact_limits::FactLimits,
    loaded::{
        RowValue, RuleExplanation, RuleProgram, SourceObservation, SourceResult, SourceSession,
        allocate_source_identity,
    },
    model::{Atom, Clause, Program, Relation, Row, Rule, Snapshot, Term, Type, Value},
    module_input::{Component, Dependency, ObjectInput, ValueReference},
};
pub use {
    execution::{
        Cancellation, Limits, compose_graphs, make_projection_graph, make_transitive_graph,
    },
    frozen::FrozenValue,
    lattice::LatticeJoin,
    object_graph::{GraphItem, ObjectGraph, ObjectNode, rows_graph},
    operators::{Expression, Operator, Reducer},
    relational_graph::RelationalGraph,
    session::{Engine, Session, WorkDistribution},
};
pub use {
    provenance::{
        Provenance, ProvenanceEdge, ProvenanceGraph, ProvenanceLimits, ProvenanceNode,
        ProvenanceStatus, ProvenanceWitness,
    },
    reachability::{Reachability, ReachabilitySnapshot},
};

#[cfg(test)]
asp_rust::asp_rust_cargo_test_gate!(
    config = {
        asp_rust::default_asp_rust_config().with_verification_profile_hint(
        asp_rust::RustVerificationProfileHint::new("src/session.rs", [asp_rust::RustOwnerResponsibility::PublicApi])
            .with_rationale("Rust tests cover typed admission, rollback, budgets, immutable snapshots and independent Scheme/Rust oracle parity"),
    )
    }
);

pub(crate) use data::invalid as invalid_data;

mod datalog;
pub use datalog::{DatalogGraph, DatalogRequest, evaluate_datalog, read_datalog};

mod rows;
pub use rows::rows_equal;

#[cfg(feature = "artifacts")]
pub mod artifacts;

/// Bounded inert Scheme datum decoding; no evaluation or authority admission.
pub mod syntax;

#[doc(hidden)]
pub use execution::cancellation::CancellationSubscription;
