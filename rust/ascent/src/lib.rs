//! Scheme-defined relational composition lowered to Rust and caller-owned Rayon pools.
//! The supported boundary is finite typed sets and stratified negation.
mod catalog;
mod clues;
pub use clues::{ClueExchange, ClueProjection, ClueSelector, clue_sexpr, read_clue_request};
mod computational;
mod data;
mod derivations;
mod domain;
mod error;
pub mod evidence_graph;
mod evidence_store;
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
mod observations;
mod operators;
mod provenance;
mod reachability;
mod relational_graph;
mod session;
mod source;
mod trajectory;

// Group the stable public surface by ownership without changing public paths.
pub use {
    catalog::Catalog,
    data::Data,
    error::{Error, Result},
    fact_limits::FactLimits,
    loaded::{
        EvidenceExplanation, EvidenceProgram, RowValue, SourceObservation, SourceResult,
        SourceSession, allocate_source_identity,
    },
    model::{Atom, Clause, Program, Relation, Row, Rule, Snapshot, Term, Type, Value},
    module_input::{Component, Dependency, ObjectInput, ValueReference},
};
pub use {
    computational::{ComputationalEvidence, ObservationRequest},
    derivations::EvidenceChain,
    domain::{domain_check, domain_contract},
    evidence_store::EvidenceStore,
    observations::{compact_observation, expand_observation},
    provenance::{
        Provenance, ProvenanceEdge, ProvenanceGraph, ProvenanceLimits, ProvenanceNode,
        ProvenanceStatus, ProvenanceWitness,
    },
    reachability::{Reachability, ReachabilitySnapshot},
    trajectory::Trajectory,
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
    session::{Engine, Session},
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

mod conversation;
pub use conversation::{ResponseHistory, ToolCallId};

mod review;
pub use review::{EvidenceReview, review_sources};

mod domain_memory;
pub use domain_memory::{DomainEvidence, domain_checker_version};

mod datalog;
pub use datalog::{DatalogGraph, DatalogRequest, evaluate_datalog, read_datalog};

mod interaction;
pub use interaction::{
    BranchEvaluation, EvidenceInteraction, EvidenceOperation, compact_feedback, expand_feedback,
};

#[cfg(feature = "provider-protocol")]
mod provider;
#[cfg(feature = "provider-protocol")]
pub use provider::read_provider_arguments;

mod rows;
pub use rows::rows_equal;

#[cfg(feature = "artifacts")]
pub mod artifacts;
