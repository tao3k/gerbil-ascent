use gerbil_ascent::{
    Component, Dependency, Engine, GraphItem, Module, ObjectInput as Input, ObjectNode,
};
fn number(value: i64) -> Input {
    Input::Integer(value.into())
}
fn scalar(module: &Module, name: &str, args: &[Input]) -> String {
    let value = module.call(name, args, None).unwrap();
    match value.graph().unwrap().root.clone() {
        GraphItem::Number(value) => value,
        _ => panic!("numeric result expected"),
    }
}
#[test]
fn lexical_closures_keep_locations_and_module_exports_resolve_each_call() {
    let engine = Engine::new(1).unwrap();
    let module=engine.load_definitions("(def (make n) (lambda (x) (set! n (+ n x)) n)) (def (answer) 1) (def (change) (set! answer (lambda () 2)))").unwrap();
    let closure = module.call("make", &[number(7)], None).unwrap();
    assert!(
        matches!(closure.apply(&[number(5)]).unwrap().graph().unwrap().root.clone(),GraphItem::Number(value) if value=="12")
    );
    assert!(
        matches!(closure.apply(&[number(1)]).unwrap().graph().unwrap().root.clone(),GraphItem::Number(value) if value=="13")
    );
    assert_eq!(scalar(&module, "answer", &[]), "1");
    module.call("change", &[], None).unwrap();
    assert_eq!(scalar(&module, "answer", &[]), "2");
    let independent = engine.load_definitions("(def (answer) 9)").unwrap();
    assert_eq!(scalar(&independent, "answer", &[]), "9");
    assert!(module.call("identity", &[number(1)], None).is_err());
    engine.shutdown();
    assert!(closure.graph().is_err());
    assert!(module.call("answer", &[], None).is_err());
}
#[test]
fn graph_observations_preserve_cycles_sharing_exact_values_and_reference_authority() {
    let engine = Engine::new(1).unwrap();
    let module=engine.load_definitions(r#"(def (cycle) (let (v (make-vector 1)) (vector-set! v 0 v) v)) (def (shared) (let (v (vector 17)) (vector v v))) (def (echo v) v) (def (number) (/ 2 6)) (def (symbols) (list (string->uninterned-symbol "s") (string->uninterned-symbol "s")))"#).unwrap();
    let cycle = module.call("cycle", &[], None).unwrap();
    let graph = cycle.graph().unwrap();
    let GraphItem::Reference(root) = graph.root else {
        panic!("cycle root")
    };
    assert!(
        matches!(&graph.nodes[&root],ObjectNode::Vector(items) if matches!(items.as_slice(),[GraphItem::Reference(id)] if *id==root))
    );
    let shared = module.call("shared", &[], None).unwrap();
    let graph = shared.graph().unwrap();
    let GraphItem::Reference(root) = graph.root else {
        panic!("shared root")
    };
    assert!(
        matches!(&graph.nodes[&root],ObjectNode::Vector(items) if matches!(items.as_slice(),[GraphItem::Reference(a),GraphItem::Reference(b)] if a==b))
    );
    assert_eq!(scalar(&module, "number", &[]), "1/3");
    let rational = module
        .call(
            "echo",
            &[Input::Rational(num_rational::BigRational::new_raw(
                2.into(),
                6.into(),
            ))],
            None,
        )
        .unwrap();
    assert_eq!(scheme_scalar(&rational), "1/3");
    assert!(
        module
            .call(
                "echo",
                &[Input::Rational(num_rational::BigRational::new_raw(
                    1.into(),
                    0.into()
                ))],
                None
            )
            .is_err()
    );
    let reference = cycle.reference(None).unwrap();
    let foreign = engine.load_definitions("(def (echo v) v)").unwrap();
    assert!(
        foreign
            .call("echo", &[Input::Reference(reference.clone())], None)
            .is_err()
    );
    assert!(cycle.reference(Some(usize::MAX)).is_err());
    cycle.close();
    assert!(
        module
            .call("echo", &[Input::Reference(reference)], None)
            .is_err()
    );
    module.close();
    assert!(shared.graph().is_err());
}
#[test]
fn component_linkage_uses_shared_locations_and_checks_unselected_dependencies() {
    let engine = Engine::new(1).unwrap();
    let mut components = vec![
        Component {
            id: "base".into(),
            source: "(def n 1) (def (answer) n) (def (bump) (set! n (+ n 1))) (def (private) 99)"
                .into(),
            exports: Some(vec!["answer".into(), "bump".into()]),
            dependencies: vec![],
        },
        Component {
            id: "entry".into(),
            source: "(def (build) (bump) (answer))".into(),
            exports: Some(vec!["build".into()]),
            dependencies: vec![Dependency {
                component: "base".into(),
                bindings: vec!["answer".into(), "bump".into()],
            }],
        },
        Component {
            id: "unused".into(),
            source: "(def (ignored) (missing))".into(),
            exports: Some(vec!["ignored".into()]),
            dependencies: vec![],
        },
    ];
    let module = engine.load_components(&components, "entry").unwrap();
    assert_eq!(scalar(&module, "build", &[]), "2");
    assert_eq!(scalar(&module, "build", &[]), "3");
    assert!(module.call("private", &[], Some("base")).is_err());
    assert!(module.call("ignored", &[], Some("unused")).is_err());
    components[2].dependencies.push(Dependency {
        component: "unused".into(),
        bindings: vec!["ignored".into()],
    });
    assert!(engine.load_components(&components, "entry").is_err());
    assert_eq!(scalar(&module, "build", &[]), "4");
}
#[test]
fn released_lease_capacity_and_lexical_arena_collection_remain_usable() {
    let engine = Engine::new(1).unwrap();
    let module = engine
        .load_definitions("(def (id x) x) (def (many . xs) (apply values xs))")
        .unwrap();
    let mut retained = (0..64)
        .map(|_| module.call("id", &[number(1)], None).unwrap())
        .collect::<Vec<_>>();
    assert!(module.call("id", &[number(2)], None).is_err());
    retained.pop();
    assert_eq!(scalar(&module, "id", &[number(2)]), "2");
    drop(retained);
    for _ in 0..1000 {
        assert_eq!(scalar(&module, "id", &[number(3)]), "3");
    }
    let multiple = module.call("many", &[number(3), number(5)], None).unwrap();
    assert_eq!(multiple.value_count().unwrap(), 2);
    let graph = multiple.graph().unwrap();
    assert!(matches!(graph.root, GraphItem::Reference(_)));
    assert!(module.call("id", &[], None).is_err());
    assert_eq!(scalar(&module, "id", &[number(4)]), "4");
}
#[test]
fn constructor_macro_free_bindings_resolve_in_definition_scope() {
    let module=Engine::new(1).unwrap().load_definitions("(defrules plus () ((_ x) (+ x 1))) (def (answer) (let ((+ (lambda (a b) 99))) (plus 2)))").unwrap();
    assert_eq!(scalar(&module, "answer", &[]), "3");
}

#[test]
fn native_scheme_object_and_lexical_observations_match_rust() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = std::process::Command::new("gxi")
        .arg(root.join("tests/fixtures/module-values.ss"))
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let expected = String::from_utf8(output.stdout).unwrap();
    let engine = Engine::new(1).unwrap();
    let module = engine
        .load_definitions(include_str!("../fixtures/module-values-source.ss"))
        .unwrap();
    let mut actual = Vec::new();
    for name in [
        "lexical-shadow",
        "rational",
        "same-cycle",
        "shared",
        "distinct-symbols",
        "table-key",
        "pair-value",
        "macro-definition-scope",
        "macro-number-case",
    ] {
        actual.push(scheme_scalar(&module.call(name, &[], None).unwrap()));
    }
    let counter = module.call("make-counter", &[number(7)], None).unwrap();
    actual.push(scheme_scalar(&counter.apply(&[number(5)]).unwrap()));
    actual.push(scheme_scalar(&counter.apply(&[number(1)]).unwrap()));
    assert_eq!(actual.join("\n") + "\n", expected);
}
fn scheme_scalar(value: &gerbil_ascent::ModuleValue) -> String {
    match value.graph().unwrap().root.clone() {
        GraphItem::Number(value) => value,
        GraphItem::Boolean(value) => if value { "#t" } else { "#f" }.into(),
        _ => panic!("scalar expected"),
    }
}
#[test]
fn engine_module_owner_quota_is_shared_and_failed_loads_release_their_permit() {
    let engine = Engine::new(1).unwrap();
    let clone = engine.clone();
    for _ in 0..100 {
        assert!(engine.load_definitions("(import :gerbil/core)").is_err());
    }
    let modules = (0..64)
        .map(|_| engine.load_definitions("(def (answer) 1)").unwrap())
        .collect::<Vec<_>>();
    assert!(clone.load_definitions("(def (answer) 1)").is_err());
    modules[0].close();
    modules[0].close();
    let replacement = clone.load_definitions("(def (answer) 2)").unwrap();
    assert_eq!(scalar(&replacement, "answer", &[]), "2");
    assert!(engine.load_definitions("(def (answer) 3)").is_err());
    drop(replacement);
    assert!(engine.load_definitions("(def (answer) 4)").is_ok());
}

#[test]
fn lazy_observation_is_shared_and_keeps_observed_child_reference_authority() {
    let engine = Engine::new(1).unwrap();
    let module=engine.load_definitions("(def (make) (vector (vector 1))) (def (mutate v) (vector-set! v 0 (vector 2))) (def (read v) (vector-ref v 0)) (def (echo x) x)").unwrap();
    let outer = module.call("make", &[], None).unwrap();
    // Passing the root handle does not need a graph observation.
    let root = outer.reference(None).unwrap();
    let before = outer.graph().unwrap();
    let repeated = outer.graph().unwrap();
    assert!(std::sync::Arc::ptr_eq(&before, &repeated));
    let GraphItem::Reference(id) = before.root else {
        panic!("vector root")
    };
    let ObjectNode::Vector(items) = &before.nodes[&id] else {
        panic!("vector")
    };
    let GraphItem::Reference(child) = items[0] else {
        panic!("shared child")
    };
    let child_reference = outer.reference(Some(child)).unwrap();
    module
        .call("mutate", &[Input::Reference(root.clone())], None)
        .unwrap();
    for _ in 0..1500 {
        module.call("echo", &[number(0)], None).unwrap();
    }
    assert!(std::sync::Arc::ptr_eq(&before, &outer.graph().unwrap()));
    let old = module
        .call("echo", &[Input::Reference(child_reference.clone())], None)
        .unwrap();
    assert!(
        matches!(&old.graph().unwrap().nodes[&child],ObjectNode::Vector(items) if matches!(&items[0],GraphItem::Number(v) if v=="1"))
    );
    let updated = module
        .call("read", &[Input::Reference(root)], None)
        .unwrap();
    let graph = updated.graph().unwrap();
    let GraphItem::Reference(updated_id) = graph.root else {
        panic!("updated child")
    };
    assert!(
        matches!(&graph.nodes[&updated_id],ObjectNode::Vector(items) if matches!(&items[0],GraphItem::Number(v) if v=="2"))
    );
    outer.close();
    assert!(
        module
            .call("echo", &[Input::Reference(child_reference)], None)
            .is_err()
    );
    assert!(old.graph().is_ok());
}

#[test]
fn lexical_bindings_shadow_syntax_and_component_macro_imports_preserve_definition_scope() {
    let engine = Engine::new(1).unwrap();
    let module=engine.load_definitions("(defrules outer () ((_ x) (inner x))) (defrules inner () ((_ x) (+ x 1))) (def (answer) (outer 2)) (def (shadow) (let ((outer (lambda (x) 99))) (outer 2)))").unwrap();
    assert_eq!(scalar(&module, "answer", &[]), "3");
    assert_eq!(scalar(&module, "shadow", &[]), "99");
    let components = vec![
        Component {
            id: "base".into(),
            source: "(defrules plus () ((_ x) (+ x 1)))".into(),
            exports: Some(vec!["plus".into()]),
            dependencies: vec![],
        },
        Component {
            id: "entry".into(),
            source: "(def (answer) (let ((+ (lambda (a b) 99))) (plus 2)))".into(),
            exports: Some(vec!["answer".into()]),
            dependencies: vec![Dependency {
                component: "base".into(),
                bindings: vec!["plus".into()],
            }],
        },
    ];
    let component = engine.load_components(&components, "entry").unwrap();
    assert_eq!(scalar(&component, "answer", &[]), "3");
}

#[test]
fn failed_recursive_macro_expansion_is_bounded_and_preserves_owned_values() {
    let engine = Engine::new(1).unwrap();
    let module=engine.load_definitions("(defrules explode () ((_ x) (explode (list x x)))) (def (fail) (explode 1)) (def (answer) 7)").unwrap();
    let retained = module.call("answer", &[], None).unwrap();
    assert!(module.call("fail", &[], None).is_err());
    assert_eq!(scheme_scalar(&retained), "7");
    assert_eq!(scalar(&module, "answer", &[]), "7");
}

#[test]
fn unsupported_native_literals_cannot_be_misread_as_successful_symbol_values() {
    let engine = Engine::new(1).unwrap();
    for source in [
        "(def (value) '+NAN.0)",
        "(def (value) '#(begin 1 2))",
        r"(def (value) '#\x61)",
        "(def (value) 'field:)",
    ] {
        let owner = engine.load_definitions(source).unwrap();
        assert!(owner.call("value", &[], None).is_err(), "{source}");
    }
    let owner = engine
        .load_definitions(
            "(defrules choose () ((_ 1/3) 7) ((_ other) 9)) (def (value) (choose 2/6))",
        )
        .unwrap();
    assert_eq!(scalar(&owner, "value", &[]), "7");
    assert!(
        engine
            .load_definitions("(defrules improper () ((_ a . rest) 1))")
            .is_err()
    );
}

#[test]
fn decimal_literals_are_native_inexact_numbers_including_quoted_data() {
    let engine = Engine::new(1).unwrap();
    for (literal, expected) in [("1.5", 1.5_f64), ("+.5", 0.5_f64)] {
        for prefix in ["", "'"] {
            let owner = engine
                .load_definitions(&format!("(def (value) {prefix}{literal})"))
                .unwrap();
            let value = owner.call("value", &[], None).unwrap();
            let graph = value.graph().unwrap();
            let gerbil_ascent::GraphItem::Number(value) = &graph.root else {
                panic!("numeric literal was not a native number");
            };
            assert_eq!(value.parse::<f64>().unwrap().to_bits(), expected.to_bits());
        }
    }
}
