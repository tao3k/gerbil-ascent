//! Scheme-defined relational composition lowered to Rust and caller-owned Rayon pools.
//! The supported boundary is finite typed sets and stratified negation.
mod catalog;
mod data;
mod derivations;
pub mod evidence_graph;
mod evidence_store;
pub use catalog::Catalog;
pub use derivations::EvidenceChain;
mod domain;
pub use domain::{domain_check, domain_contract};
mod observations;
pub use observations::{compact_observation, expand_observation};
mod computational;
pub use computational::{ComputationalEvidence, ObservationRequest};
mod reachability;
pub use evidence_store::EvidenceStore;
pub use reachability::{Reachability, ReachabilitySnapshot};
mod error;
mod trajectory;
pub use data::Data;
pub use trajectory::Trajectory;
mod fact_limits;
pub use fact_limits::FactLimits;
mod execution;
mod graph;
mod lattice;
mod loaded;
mod model;
mod numbers;
pub use lattice::LatticeJoin;
mod object_graph;
pub use object_graph::{GraphItem, ObjectGraph, ObjectNode, rows_graph};
mod frozen;
pub use frozen::FrozenValue;
mod modules;
pub use loaded::{RowValue, SourceObservation, SourceResult, SourceSession};
pub use modules::{
    Component, Dependency, Evidence, Explanation, Module, ModuleValue, ObjectInput, ValueReference,
};
mod provenance;
pub use provenance::{
    Provenance, ProvenanceEdge, ProvenanceGraph, ProvenanceLimits, ProvenanceNode,
    ProvenanceStatus, ProvenanceWitness,
};
mod operators;
pub use operators::{Expression, Operator, Reducer};
mod session;
mod source;
pub use error::{Error, Result};
pub use execution::{Cancellation, Limits};
pub use model::{Atom, Clause, Program, Relation, Row, Rule, Snapshot, Term, Type, Value};
pub use session::{Engine, Session};

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
