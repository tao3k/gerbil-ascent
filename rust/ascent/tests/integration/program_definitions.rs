//! Declarative bindings and withdrawal use the Rust engine, not Scheme services.
use gerbil_ascent::{Cancellation, Engine, Limits, Row, RuleProgram, Value};

const HISTORY: &str = "
(def shared (ascent-fragment
  ((added X) <-- (current X) (not (previous X)))
  ((removed X) <-- (previous X) (not (current X)))))
(define-program (history)
 (sources current previous) (outputs added removed current)
 (relation current ((x exact-integer?)))
 (relation previous ((x exact-integer?)))
 (relation added ((x exact-integer?)))
 (relation removed ((x exact-integer?)))
 (include shared))";

#[test]
fn output_aliases_keep_authority_identity_and_withdrawal() {
    let source = "(define-program (make) (sources input) (outputs (visible copied))
        (relation input ((x integer?)) ((2) (7)))
        (relation copied ((x integer?))) ((copied X) <-- (input X)))";
    let engine = Engine::new(1).unwrap();
    let mut session = engine
        .open_declaration_sources(&[source], None, gerbil_ascent::FactLimits::default())
        .unwrap();
    let initial = session
        .run(None, &Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(
        initial.relations["visible"],
        vec![Row::from(vec![2.into()]), Row::from(vec![7.into()])]
    );
    let proof = session
        .provenance(
            initial.result_handle,
            "visible",
            &gerbil_ascent::ProvenanceLimits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    assert_eq!(proof.graph().unwrap().query, "visible");
    assert!(
        session
            .replace(
                std::collections::BTreeMap::from([("visible".into(), vec![])]),
                &Limits::default(),
                &Cancellation::default()
            )
            .is_err()
    );
    session
        .replace(
            std::collections::BTreeMap::from([("input".into(), vec![])]),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    assert!(proof.graph().is_err());
    let current = session
        .run(None, &Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(
        current.relations["visible"],
        Vec::<gerbil_ascent::Row>::new()
    );
    for source in [
        "(define-program (make) (sources (public input)) (outputs input) (relation input (x)))",
        "(define-program (make) (sources input) (outputs (input copied)) (relation input (x)) (relation copied (x)))",
        "(define-program (make) (sources input) (outputs (a copied) (b copied)) (relation input (x)) (relation copied (x)))",
    ] {
        assert!(RuleProgram::read_sources(&[source], None).is_err());
    }
}

#[test]
fn inline_fragment_macros_keep_budget_and_duplicate_admission() {
    let source = "(ascent
        (macro emit! ((n expr)) (fact (Seed (lit n))))
        (relation Seed ((n integer?))) (emit! 7)
        (include (ascent-fragment (relation Included ((n integer?)) '((5)))))
        (bounds 32 64 96))";
    let program = gerbil_ascent::Program::read_sources(&[source]).unwrap();
    assert_eq!(program.fact_limits.input, Some(32));
    let engine = Engine::new(1).unwrap();
    let mut session = engine.open(program).unwrap();
    let observed = session
        .run(&Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(
        observed.relations["Seed"],
        vec![Row::from(vec![Value::from(7)])]
    );
    assert_eq!(
        observed.relations["Included"],
        vec![Row::from(vec![Value::from(5)])]
    );
    for source in [
        "(ascent (macro emit! ((n expr) (n expr)) (fact (Seed (lit n)))))",
        "(ascent (include (ascent-fragment (relation R (x)) ((R X) <-- (S X)))) ((R X) <-- (S X)))",
        "(ascent (include (ascent-fragment (relation R (x)))) (bounds 0 64 96))",
    ] {
        assert!(gerbil_ascent::Program::read_sources(&[source]).is_err());
    }
}

#[test]
fn rayon_guard_answers_preserve_large_input_cancellation_and_rollback() {
    let source = "(define-program (checked) (sources input) (outputs selected)
        (relation input ((x exact-integer?)))
        (relation selected ((x exact-integer?)))
        ((selected X) <-- (input X) (if (X) (odd? X))))";
    let mut expected = None;
    for workers in [1, 4] {
        let engine = Engine::new(workers).unwrap();
        let mut session = engine
            .open_declaration_sources(&[source], None, gerbil_ascent::FactLimits::default())
            .unwrap();
        session
            .replace(
                std::collections::BTreeMap::from([(
                    "input".into(),
                    (0..16384)
                        .map(|x| Row::from(vec![Value::from(x)]))
                        .collect(),
                )]),
                &Limits::default(),
                &Cancellation::default(),
            )
            .unwrap();
        let observed = session
            .run(None, &Limits::default(), &Cancellation::default())
            .unwrap();
        assert_eq!(observed.relations["selected"].len(), 8192);
        if let Some(expected) = &expected {
            assert_eq!(&observed.relations, expected);
        } else {
            expected = Some(observed.relations.clone());
        }
        let canceled = Cancellation::default();
        canceled.cancel();
        assert!(
            session
                .replace(
                    std::collections::BTreeMap::from([("input".into(), vec![])]),
                    &Limits::default(),
                    &canceled
                )
                .is_err()
        );
        assert_eq!(
            session
                .run(None, &Limits::default(), &Cancellation::default())
                .unwrap()
                .relations,
            observed.relations
        );
        session.close();
        engine.shutdown();
    }
}

#[test]
fn declarative_graph_values_preserve_cycles_sharing_and_opaque_identity() {
    let source = "(define-program (graphs) (sources) (outputs objects)
      (relation objects (value)
        (((object-graph (ref 0) ((0 vector (ref 0)))))
         ((object-graph (ref 0) ((0 vector (ref 1) (ref 1)) (1 vector 17))))
         ((object-graph (ref 0) ((0 table ((ref 1) (ref 2))) (1 symbol \"same\" #t) (2 opaque \"external-resource\")))))))";
    let entry = RuleProgram::read_sources(&[source], None).unwrap();
    assert!(gerbil_ascent::Catalog::encode(&entry.program, &entry.outputs).is_err());
    let observed = gerbil_ascent::Catalog::observe(&entry.program, &entry.outputs).unwrap();
    assert_eq!(
        observed.field("relations").unwrap().list().unwrap().len(),
        1
    );
    let engine = Engine::new(1).unwrap();
    let mut session = engine.open(entry.program).unwrap();
    let snapshot = session
        .run(&Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(snapshot.relations["objects"].len(), 3);
    let graphs = snapshot.relations["objects"]
        .iter()
        .map(|row| {
            let Value::Object(value) = &row[0] else {
                panic!("graph value lost");
            };
            value.graph()
        })
        .collect::<Vec<_>>();
    assert!(graphs.iter().any(
        |g| matches!(&g.nodes[&0], gerbil_ascent::ObjectNode::Vector(v)
        if matches!(v.as_slice(), [gerbil_ascent::GraphItem::Reference(0)]))
    ));
    assert!(graphs.iter().any(|g| matches!(&g.nodes[&0], gerbil_ascent::ObjectNode::Vector(v)
        if matches!(v.as_slice(), [gerbil_ascent::GraphItem::Reference(a), gerbil_ascent::GraphItem::Reference(b)] if a == b))));
    assert!(
        graphs
            .iter()
            .any(|g| matches!(&g.nodes[&0], gerbil_ascent::ObjectNode::Table(_)))
    );
    session.close();
    engine.shutdown();
    for invalid in [
        source.replace("(0 vector (ref 0))", "(0 vector (ref 999))"),
        source.replace("(0 vector (ref 0))", "(0 vector) (0 vector)"),
    ] {
        assert!(RuleProgram::read_sources(&[&invalid], None).is_err());
    }
}

#[test]
fn first_class_relation_graphs_preserve_composition_and_withdrawal() {
    use gerbil_ascent::RelationalGraph;
    let row = |a: i32, b: i32| Row::from(vec![Value::from(a), Value::from(b)]);
    let edge = RelationalGraph::source("edge", 2, vec![row(1, 2), row(2, 3)]).unwrap();
    let graph = edge
        .join(&edge, 1, 0)
        .unwrap()
        .project(vec![0, 3])
        .unwrap()
        .union(&edge)
        .unwrap();
    let engine = Engine::new(2).unwrap();
    let declaration = graph.program("path").unwrap();
    assert_eq!(declaration.sources, ["edge".to_owned()].into());
    let mut session = engine
        .open_rule_program(declaration, gerbil_ascent::FactLimits::default())
        .unwrap();
    let before = session
        .run(None, &Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(
        before.relations["path"],
        vec![row(1, 2), row(1, 3), row(2, 3)]
    );
    session
        .replace(
            std::collections::BTreeMap::from([("edge".into(), vec![])]),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    assert_eq!(
        session
            .run(None, &Limits::default(), &Cancellation::default())
            .unwrap()
            .relations["path"],
        Vec::<gerbil_ascent::Row>::new()
    );
    assert!(edge.project(vec![2]).is_err());
    assert!(edge.program("edge").is_err());
    let changed = RelationalGraph::source("edge", 2, vec![row(8, 9)]).unwrap();
    assert!(edge.union(&changed).unwrap().program("path").is_err());
    session.close();
    engine.shutdown();
}

#[test]
fn pattern_rules_expand_recursive_relations_without_capturing_caller_variables() {
    let source = "(defrules closure () ((_ edge path) (ascent-fragment
        (relation path (from to))
        ((path from to) <-- (edge from to))
        ((path from to) <-- (edge from middle) (path middle to)))))
      (define-program (check) (sources edge other) (outputs path alternate)
        (relation edge (from to)) (relation other (from to))
        (include (closure edge path)) (include (closure other alternate)))";
    let entry = RuleProgram::read_sources(&[source], None).unwrap();
    let engine = Engine::new(1).unwrap();
    let mut session = engine.open(entry.program).unwrap();
    let row = |a: i32, b: i32| Row::from(vec![Value::from(a), Value::from(b)]);
    session.replace("edge", vec![row(1, 2), row(2, 3)]).unwrap();
    session.replace("other", vec![row(7, 8)]).unwrap();
    let result = session
        .run(&Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(
        result.relations["path"],
        vec![row(1, 2), row(1, 3), row(2, 3)]
    );
    assert_eq!(result.relations["alternate"], vec![row(7, 8)]);
    session.close();
    engine.shutdown();
    assert!(
        RuleProgram::read_sources(
            &[&source.replace("closure edge path", "closure edge")],
            None
        )
        .is_err()
    );
    assert!(
        RuleProgram::read_sources(&[&source.replace("middle", "__ascent_macro_fake")], None)
            .is_err()
    );
}

#[test]
fn relational_projection_export_and_declaration_bridge_preserve_source_authority() {
    let source = "(def projection (relational-op-fragment
        (relational-op-project (relational-op-source 'contracts 3 []) '(0 1)) 'edges))
      (def (copy-rule from to)
        (let (terms (list (gerbil-ascent-variable 'x) (gerbil-ascent-variable 'y)))
          (gerbil-ascent-rule (list (gerbil-ascent-atom to terms))
                            (list (gerbil-ascent-atom from terms)))))
      (define-program (check)
        (sources (contracts (relational-export projection 'contracts)))
        (outputs answer (edges (relational-export projection 'edges)))
        (relation answer (x y)) (include projection)
        (include (gerbil-ascent-fragment []
            (list (copy-rule (relational-export projection 'edges) 'answer)))))";
    let engine = Engine::new(1).unwrap();
    let mut session = engine
        .open_declaration_sources(&[source], None, gerbil_ascent::FactLimits::default())
        .unwrap();
    let row =
        |values: &[i32]| Row::from(values.iter().copied().map(Value::from).collect::<Vec<_>>());
    session
        .replace(
            std::collections::BTreeMap::from([(
                "contracts".into(),
                vec![row(&[1, 2, 3]), row(&[1, 2, 4])],
            )]),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    let result = session
        .run(None, &Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(result.relations["answer"], vec![row(&[1, 2])]);
    assert_eq!(result.relations["edges"], vec![row(&[1, 2])]);
    session
        .replace(
            std::collections::BTreeMap::from([("contracts".into(), vec![])]),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    assert_eq!(
        session
            .run(None, &Limits::default(), &Cancellation::default())
            .unwrap()
            .relations["answer"],
        Vec::<gerbil_ascent::Row>::new()
    );
    session.close();
    engine.shutdown();
    for invalid in [
        source.replace("'(0 1)", "'(0 3)"),
        source.replace("projection 'edges", "projection 'missing"),
    ] {
        assert!(RuleProgram::read_sources(&[&invalid], None).is_err());
    }
}

#[test]
fn actual_investigation_links_rules_operator_sources_and_explanation() {
    let sources = [
        include_str!("../fixtures/evidence/dependency.ss"),
        include_str!("../fixtures/evidence/investigation.ss"),
    ];
    let program = RuleProgram::read_sources(&sources, Some("make-investigation")).unwrap();
    assert!(program.sources.contains("contracts"));
    assert!(!program.sources.contains("contract_dependencies"));
    let engine = Engine::new(1).unwrap();
    let mut session = engine
        .open_declaration_sources(
            &sources,
            Some("make-investigation"),
            gerbil_ascent::FactLimits::default(),
        )
        .unwrap();
    let row =
        |values: &[&str]| Row::from(values.iter().map(|s| Value::from(*s)).collect::<Vec<_>>());
    session
        .replace(
            std::collections::BTreeMap::from([(
                "contracts".into(),
                vec![row(&["a", "b", "one"]), row(&["b", "c", "two"])],
            )]),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    let run = session
        .run(None, &Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(
        run.relations["ancestry"],
        vec![row(&["a", "b"]), row(&["a", "c"]), row(&["b", "c"])]
    );
    assert!(
        session
            .explanation_metadata(run.result_handle, "ancestry")
            .is_ok()
    );
    session
        .replace(
            std::collections::BTreeMap::from([("contracts".into(), vec![row(&["a", "b", "one"])])]),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    let run = session
        .run(None, &Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(run.relations["ancestry"], vec![row(&["a", "b"])]);
    session.close();
    engine.shutdown();
}

#[test]
fn structured_datum_constants_keep_shape_and_catalog_roundtrip() {
    let program = gerbil_ascent::Program::read_sources(&["(ascent
        (relation packed (value) '((#(2 \"text\" (a b))) (#()) ((a b)) (())))
        (relation answer (value)) ((answer value) <-- (packed value)))"])
    .unwrap();
    assert_eq!(program.relations[0].rows.len(), 4);
    for row in &program.relations[0].rows {
        assert!(matches!(row.first(), Some(Value::Object(_))));
    }
    let encoded = gerbil_ascent::Catalog::encode(&program, &["answer".into()]).unwrap();
    let engine = Engine::new(1).unwrap();
    let decoded = gerbil_ascent::Catalog::read(&encoded).unwrap();
    let mut session = engine
        .open_catalog(
            decoded.program,
            std::collections::BTreeMap::default(),
            decoded.queries,
            gerbil_ascent::FactLimits::default(),
        )
        .unwrap();
    let run = session
        .run(None, &Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(run.relations["answer"].len(), 4);
    let graph = gerbil_ascent::rows_graph(&run.relations["answer"]).unwrap();
    let lengths = graph
        .nodes
        .values()
        .filter_map(|node| match node {
            gerbil_ascent::ObjectNode::Vector(values) => Some(values.len()),
            _ => None,
        })
        .collect::<std::collections::BTreeSet<_>>();
    assert_eq!(lengths, std::collections::BTreeSet::from([0, 3]));
    session.close();
    engine.shutdown();
}

#[test]
fn rust_owned_graph_pool_preserves_cycles_sharing_and_local_opaque_identity() {
    use gerbil_ascent::{Catalog, Data, GraphItem as Item, ObjectGraph, ObjectNode as Node};
    let graph = ObjectGraph {
        root: Item::Reference(0),
        nodes: std::collections::BTreeMap::from([
            (
                0,
                Node::Vector(vec![
                    Item::Reference(1),
                    Item::Reference(1),
                    Item::Reference(2),
                    Item::Reference(3),
                ]),
            ),
            (1, Node::Pair(Item::Number("1".into()), Item::Reference(1))),
            (
                2,
                Node::Table(vec![(Item::Reference(1), Item::Reference(3))]),
            ),
            (3, Node::Opaque("owned-token".into())),
        ])
        .into(),
    };
    let data = Data::object([
        (
            "relations",
            Data::List(vec![Data::object([
                ("name", "input".into()),
                ("source", false.into()),
                (
                    "columns",
                    Data::List(vec![Data::object([("kind", "value".into())])]),
                ),
                (
                    "rows",
                    Data::List(
                        (0..4usize)
                            .map(|i| {
                                Data::List(vec![Data::object([
                                    ("type", "pool".into()),
                                    ("value", Data::from(i)),
                                ])])
                            })
                            .collect(),
                    ),
                ),
            ])]),
        ),
        ("rules", Data::List(vec![])),
        ("values", graph.to_scheme()),
    ]);
    let first = Catalog::read(&data).unwrap();
    let second = Catalog::read(&data).unwrap();
    assert!(Catalog::encode(&first.program, &["input".into()]).is_err());
    let rows = &first.program.relations[0].rows;
    assert_eq!(rows[0], rows[1]);
    assert_eq!(rows[0], second.program.relations[0].rows[0]);
    assert_ne!(rows[3], second.program.relations[0].rows[3]);
    let observed = gerbil_ascent::rows_graph(rows).unwrap();
    assert!(observed.nodes.values().any(|n| matches!(n, Node::Table(_))));
    assert!(
        observed
            .nodes
            .values()
            .any(|n| matches!(n, Node::Opaque(_)))
    );
    let rebuilt = ObjectGraph::read_scheme(&observed.to_scheme()).unwrap();
    assert_eq!(rebuilt.to_scheme(), observed.to_scheme());
}

#[test]
fn quoted_digit_prefixed_symbols_and_recorded_source_authority_are_not_coerced() {
    let source = "(def (case) (make-recorded-module (ascent-fragment
      (relation input ((scope symbol?))) (relation answer ((scope symbol?)))
      ((answer '11-network) <-- (input '11-network))
      ((answer '13-modules/prim_port.scm) <-- (input '13-modules/prim_port.scm))) '(input)))";
    let engine = Engine::new(1).unwrap();
    let mut session = engine
        .open_declaration_sources(
            &[source],
            Some("case"),
            gerbil_ascent::FactLimits::default(),
        )
        .unwrap();
    session
        .replace(
            std::collections::BTreeMap::from([(
                "input".into(),
                vec![
                    Row::from(vec![Value::Symbol("11-network".into())]),
                    Row::from(vec![Value::Symbol("13-modules/prim_port.scm".into())]),
                ],
            )]),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    let run = session
        .run(None, &Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(run.relations["answer"].len(), 2);
    assert!(
        session
            .replace(
                std::collections::BTreeMap::from([("answer".into(), vec![])]),
                &Limits::default(),
                &Cancellation::default()
            )
            .is_err()
    );
    session.close();
    engine.shutdown();
}

#[test]
fn typed_string_and_immediate_comparisons_do_not_coerce_values() {
    let source = "(define-program (compare) (sources input) (outputs answer)
      (relation input ((text string?) (tag symbol?)))
      (relation answer ((text string?)))
      ((answer Text) <-- (input Text Tag)
        (if (Text Tag) (and (string=? Text \"selected\") (eq? Tag 'selected)))))";
    let engine = Engine::new(1).unwrap();
    let mut session = engine
        .open_declaration_sources(&[source], None, gerbil_ascent::FactLimits::default())
        .unwrap();
    let rows = vec![
        Row::from(vec![
            Value::Text("selected".into()),
            Value::Symbol("selected".into()),
        ]),
        Row::from(vec![
            Value::Text("other".into()),
            Value::Symbol("selected".into()),
        ]),
    ];
    session
        .replace(
            std::collections::BTreeMap::from([("input".into(), rows)]),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    let run = session
        .run(None, &Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(
        run.relations["answer"],
        vec![Row::from(vec![Value::Text("selected".into())])]
    );
    session.close();
    engine.shutdown();
}

#[test]
fn unavailable_result_explanation_does_not_fabricate_metadata_or_block_execution() {
    let source = "(define-program (check) (sources input) (outputs input)
       (relation input ((x exact-integer?)))
       (explain (lambda (program result query scope) (hash (\"result\" result)))))";
    let engine = Engine::new(1).unwrap();
    let mut session = engine
        .open_declaration_sources(&[source], None, gerbil_ascent::FactLimits::default())
        .unwrap();
    let run = session
        .run(None, &Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(run.relations["input"], Vec::<gerbil_ascent::Row>::new());
    let error = session
        .explanation_metadata(run.result_handle, "input")
        .unwrap_err();
    assert!(
        error
            .to_string()
            .contains("result object explanation binding")
    );
    session.close();
    engine.shutdown();
}

#[test]
fn definitions_preserve_sources_outputs_and_withdrawal() {
    let entry = RuleProgram::read_sources(&[HISTORY], None).unwrap();
    assert_eq!(entry.constructor, "history");
    assert_eq!(entry.outputs, ["added", "removed", "current"]);
    let engine = Engine::new(1).unwrap();
    let mut session = engine.open(entry.program).unwrap();
    let rows = |n: i32| vec![Row::from(vec![Value::Integer(n.into())])];
    session.replace("previous", rows(1_i32)).unwrap();
    session.replace("current", rows(2_i32)).unwrap();
    let snapshot = session
        .run(&Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(snapshot.relations["added"], rows(2));
    assert_eq!(snapshot.relations["removed"], rows(1));
    session.replace("current", rows(1)).unwrap();
    let replaced = session
        .run(&Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(
        replaced.relations["added"],
        Vec::<gerbil_ascent::Row>::new()
    );
    assert_eq!(
        replaced.relations["removed"],
        Vec::<gerbil_ascent::Row>::new()
    );
    assert_eq!(snapshot.relations["added"], rows(2));
    session.close();
    engine.shutdown();
}

#[test]
fn invalid_bindings_and_executable_forms_never_fallback() {
    for source in [
        HISTORY.replace("(outputs added removed current)", "(outputs missing)"),
        HISTORY.replace("(include shared)", "(include absent)"),
        HISTORY.replace("(sources current previous)", "(sources current current)"),
        HISTORY.replace("(history)", "(history argument)"),
        "(def answer (lambda () 1))".into(),
        "(def x (ascent-fragment (include x))) (define-program (e) (sources) (outputs) (include x))".into(),
    ] {
        assert!(RuleProgram::read_sources(&[&source], None).is_err());
    }
}

#[test]
fn production_catalog_review_history_compile_in_rust() {
    let files = |names: &[&str]| {
        names
            .iter()
            .map(|name| {
                std::fs::read_to_string(
                    std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                        .join("tests/fixtures/evidence")
                        .join(name),
                )
                .unwrap()
            })
            .collect::<Vec<_>>()
    };
    for (names, constructor) in [
        (
            vec![
                "catalog.ss",
                "catalog/reports.ss",
                "catalog/observations.ss",
                "catalog/protocols.ss",
            ],
            "make-catalog",
        ),
        (vec!["review.ss", "review/receipts.ss"], "make-review"),
        (vec!["history.ss"], "make-history"),
    ] {
        let sources = files(&names);
        let entry = RuleProgram::read_sources(
            &sources.iter().map(String::as_str).collect::<Vec<_>>(),
            Some(constructor),
        )
        .unwrap();
        assert_ne!(entry.sources, std::collections::BTreeSet::<String>::new());
        assert_ne!(entry.outputs, Vec::<String>::new());
        let engine = Engine::new(1).unwrap();
        let mut session = engine.open(entry.program).unwrap();
        session
            .run(&Limits::default(), &Cancellation::default())
            .unwrap();
        session.close();
        engine.shutdown();
    }
}

#[test]
fn production_review_requires_matching_identity_and_withdraws_support() {
    let source = include_str!("../fixtures/evidence/review.ss");
    let receipts = include_str!("../fixtures/evidence/review/receipts.ss");
    let entry = RuleProgram::read_sources(&[source, receipts], None).unwrap();
    let engine = Engine::new(2).unwrap();
    let mut session = engine.open(entry.program).unwrap();
    let row = |names: &[&str]| {
        Row::from(
            names
                .iter()
                .map(|n| Value::Symbol((*n).into()))
                .collect::<Vec<_>>(),
        )
    };
    session
        .replace("Candidate", vec![row(&["candidate", "gc", "new-sha"])])
        .unwrap();
    session
        .replace("Requires", vec![row(&["candidate", "gc-correct"])])
        .unwrap();
    let denied = session
        .run(&Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(
        denied.relations["Decision"],
        vec![row(&["candidate", "DENY"])]
    );
    session
        .replace("Passed", vec![row(&["receipt", "gc-correct"])])
        .unwrap();
    session
        .replace("ReceiptInput", vec![row(&["receipt", "source", "new-sha"])])
        .unwrap();
    session
        .replace("CurrentInput", vec![row(&["source", "new-sha"])])
        .unwrap();
    let reviewed = session
        .run(&Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(
        reviewed.relations["Decision"],
        vec![row(&["candidate", "REVIEW_REQUIRED"])]
    );
    session
        .replace("CurrentInput", vec![row(&["source", "different-sha"])])
        .unwrap();
    let withdrawn = session
        .run(&Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(
        withdrawn.relations["Reusable"],
        Vec::<gerbil_ascent::Row>::new()
    );
    assert_eq!(
        withdrawn.relations["Decision"],
        denied.relations["Decision"]
    );
    session.close();
    engine.shutdown();
}

#[test]
fn declarative_projection_roundtrips_the_complete_review_rules() {
    let sources = [
        include_str!("../fixtures/evidence/review.ss"),
        include_str!("../fixtures/evidence/review/receipts.ss"),
    ];
    let entry = RuleProgram::read_sources(&sources, None).unwrap();
    let packet = gerbil_ascent::Catalog::encode(&entry.program, &entry.outputs).unwrap();
    let decoded = gerbil_ascent::Catalog::read(&packet).unwrap();
    assert_eq!(decoded.program.relations, entry.program.relations);
    assert_eq!(decoded.queries, entry.outputs);
    assert_eq!(decoded.program.rules.len(), entry.program.rules.len());
}

#[test]
fn component_scopes_reject_hidden_and_cyclic_dependencies() {
    use gerbil_ascent::{Component, Dependency};
    let shared = Component {
        id: "shared".into(),
        source: "(def f (ascent-fragment ((answer X) <-- (input X))))".into(),
        exports: Some(vec!["f".into()]),
        dependencies: vec![],
    };
    let entry = Component { id: "entry".into(), source: "(define-program (make) (sources input) (outputs answer) (relation input ((x symbol?))) (relation answer ((x symbol?))) (include f))".into(), exports: Some(vec!["make".into()]), dependencies: vec![Dependency {component: "shared".into(),bindings:vec!["f".into()]}] };
    let linked =
        RuleProgram::read_components(&[entry.clone(), shared.clone()], "entry", Some("make"))
            .unwrap();
    assert_eq!(linked.program.rules.len(), 1);
    let mut hidden = shared.clone();
    hidden.exports = Some(vec![]);
    assert!(RuleProgram::read_components(&[entry.clone(), hidden], "entry", None).is_err());
    let mut cyclic = shared;
    cyclic.dependencies = vec![Dependency {
        component: "entry".into(),
        bindings: vec!["make".into()],
    }];
    assert!(RuleProgram::read_components(&[entry, cyclic], "entry", None).is_err());
}

#[test]
fn actual_actions_and_lifecycle_dsl_execute_without_vm() {
    for (source, constructor) in [
        (
            include_str!("../fixtures/evidence/actions.ss"),
            "make-actions",
        ),
        (
            include_str!("../fixtures/evidence/lifecycle.ss"),
            "make-lifecycle-review",
        ),
    ] {
        let program = RuleProgram::read_sources(&[source], Some(constructor)).unwrap();
        let engine = Engine::new(1).unwrap();
        let mut session = engine
            .open_rule_program(program, gerbil_ascent::FactLimits::default())
            .unwrap();
        session
            .run(None, &Limits::default(), &Cancellation::default())
            .unwrap();
        session.close();
        engine.shutdown();
    }
}

#[test]
fn computed_symbol_heads_and_number_predicates_preserve_values() {
    let source = "(def (label symbol suffix) (string->symbol (string-append (symbol->string symbol) suffix)))
      (define-program (make) (sources item sample) (outputs answer sample)
       (relation item ((name symbol?))) (relation sample ((value number?)))
       (relation answer ((name symbol?))) ((answer (expr (X) (label X \"-checked\"))) <-- (item X)))";
    let engine = Engine::new(1).unwrap();
    let mut session = engine
        .open_declaration_sources(&[source], None, gerbil_ascent::FactLimits::default())
        .unwrap();
    let samples = vec![Row::from(vec![Value::inexact(-0.0).unwrap()])];
    session
        .replace(
            std::collections::BTreeMap::from([
                (
                    "item".into(),
                    vec![Row::from(vec![Value::Symbol("source".into())])],
                ),
                ("sample".into(), samples.clone()),
            ]),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    let before = session
        .run(None, &Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(
        before.relations["answer"],
        vec![Row::from(vec![Value::Symbol("source-checked".into())])]
    );
    assert_eq!(
        before.relations["sample"][0][0]
            .as_binary64()
            .unwrap()
            .to_bits(),
        (-0.0_f64).to_bits()
    );
    assert!(
        session
            .replace(
                std::collections::BTreeMap::from([(
                    "sample".into(),
                    vec![Row::from(vec![Value::Boolean(false)])]
                )]),
                &Limits::default(),
                &Cancellation::default()
            )
            .is_err()
    );
    let after = session
        .run(None, &Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(after.source_generation, before.source_generation);
    session.close();
    engine.shutdown();
}
#[test]
fn registry_dependency_discovery_is_not_source_admission() {
    use gerbil_ascent::{Component, RuleProgram};
    let mut components = vec![
        Component {
            id: "chosen".into(),
            source: "(".into(),
            exports: None,
            dependencies: vec![],
        },
        Component {
            id: "unselected".into(),
            source: "(".into(),
            exports: None,
            dependencies: vec![],
        },
    ];
    assert_eq!(
        RuleProgram::component_dependencies(&components, "chosen").unwrap(),
        vec!["chosen"]
    );
    assert!(RuleProgram::component_ids(&components, "chosen").is_err());
    components[0].source =
        "(define-program (make) (sources) (outputs checked) (relation checked (x) '((1))))".into();
    assert_eq!(
        RuleProgram::component_ids(&components, "chosen").unwrap(),
        vec!["chosen"]
    );
    assert!(RuleProgram::read_components(&components, "chosen", Some("make")).is_ok());
}
