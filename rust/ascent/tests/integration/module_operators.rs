use gerbil_ascent::{Engine, GraphItem, ModuleValue, ObjectInput as Input, ObjectNode};
use std::collections::BTreeMap;
fn n(n: i64) -> Input {
    Input::Integer(n.into())
}
fn symbol(name: &str) -> Input {
    Input::Symbol(name.into())
}
fn rows(values: &[[i64; 2]]) -> Input {
    Input::List(
        values
            .iter()
            .map(|r| Input::List(r.iter().map(|v| n(*v)).collect()))
            .collect(),
    )
}
fn reference(value: &ModuleValue) -> Input {
    Input::Reference(value.reference(None).unwrap())
}
fn decode(value: &ModuleValue) -> Vec<Vec<i64>> {
    fn list(root: &GraphItem, nodes: &BTreeMap<usize, ObjectNode>) -> Vec<GraphItem> {
        let mut item = root.clone();
        let mut out = Vec::new();
        loop {
            match item {
                GraphItem::Null => return out,
                GraphItem::Reference(id) => {
                    let ObjectNode::Pair(a, b) = &nodes[&id] else {
                        panic!("list expected")
                    };
                    out.push(a.clone());
                    item = b.clone();
                }
                _ => panic!("list expected"),
            }
        }
    }
    let graph = value.graph().unwrap();
    list(&graph.root, &graph.nodes)
        .iter()
        .map(|row| {
            list(row, &graph.nodes)
                .iter()
                .map(|v| {
                    let GraphItem::Number(n) = v else {
                        panic!("number")
                    };
                    n.parse().unwrap()
                })
                .collect()
        })
        .collect()
}
fn malformed_rows() -> Input {
    Input::List(vec![Input::List(vec![n(1)])])
}
fn assert_query(query: &ModuleValue, solution: &ModuleValue, expected: &[Vec<i64>]) {
    assert_eq!(
        decode(&query.apply(&[reference(solution)]).unwrap()),
        expected
    );
}
#[test]
fn library_operators_compose_query_replace_and_preserve_failed_update() {
    let engine = Engine::new(1).unwrap();
    let module = engine.module(":gerbil-ascent/program/interface").unwrap();
    let source = module
        .call(
            "relational-op-source",
            &[symbol("edge"), n(2), rows(&[[0, 1], [1, 2]])],
            None,
        )
        .unwrap();
    let project = module
        .call(
            "relational-op-project",
            &[reference(&source), Input::List(vec![n(1)])],
            None,
        )
        .unwrap();
    let fragment = module
        .call(
            "relational-op-fragment",
            &[reference(&project), symbol("targets")],
            None,
        )
        .unwrap();
    let program = module
        .call(
            "relational-compose",
            &[
                Input::List(vec![reference(&fragment)]),
                n(16),
                n(64),
                n(128),
            ],
            None,
        )
        .unwrap();
    let session = module
        .call("relational-open-session", &[reference(&program)], None)
        .unwrap();
    let solution = module
        .call("relational-session-run", &[reference(&session)], None)
        .unwrap();
    let output = module
        .call(
            "relational-query",
            &[
                reference(&solution),
                reference(&fragment),
                symbol("targets"),
            ],
            None,
        )
        .unwrap();
    assert_eq!(decode(&output), vec![vec![1], vec![2]]);
    let query = module
        .call(
            "relational-prepare-query",
            &[reference(&fragment), symbol("targets")],
            None,
        )
        .unwrap();
    assert_query(&query, &solution, &[vec![1], vec![2]]);
    module
        .call(
            "relational-session-replace-source!",
            &[
                reference(&session),
                reference(&fragment),
                symbol("edge"),
                rows(&[[7, 8]]),
            ],
            None,
        )
        .unwrap();
    let updated = module
        .call("relational-session-run", &[reference(&session)], None)
        .unwrap();
    assert_query(&query, &updated, &[vec![8]]);
    assert!(
        module
            .call(
                "relational-session-replace-source!",
                &[
                    reference(&session),
                    reference(&fragment),
                    symbol("edge"),
                    malformed_rows()
                ],
                None
            )
            .is_err()
    );
    assert_query(&query, &updated, &[vec![8]]);
    assert!(module.call("identity", &[n(1)], None).is_err());
}
#[test]
fn registered_native_module_imports_constructor_and_scoped_export_bindings() {
    let engine = Engine::new(1).unwrap();
    engine.register_module(":consumer/targets",r"
      (import :gerbil-ascent/evidence/interface)
      (export make)
      (def (make inputs)
        (let (fragment (relational-op-fragment (relational-op-project (relational-op-source 'edge 2 inputs) '(1)) 'targets))
          (ascent-evidence-module (relational-compose (list fragment) 32 64 96) #f
            (list (cons 'targets (relational-export fragment 'targets)) (cons 'edge (relational-export fragment 'edge))))))").unwrap();
    let module = engine.module(":consumer/targets").unwrap();
    let constructor = module
        .call("make", &[rows(&[[0, 1], [1, 2]])], None)
        .unwrap();
    let session = constructor
        .open_session(gerbil_ascent::FactLimits::default())
        .unwrap();
    module.close();
    let limits = gerbil_ascent::SourceSession::default_limits();
    let cancel = gerbil_ascent::Cancellation::default();
    let observed = session.run(None, &limits, &cancel).unwrap();
    assert_eq!(
        observed.relations["targets"],
        vec![vec![1.into()].into(), vec![2.into()].into()]
    );
    session
        .replace(
            BTreeMap::from([("edge".into(), vec![vec![n(3), n(4)]])]),
            &limits,
            &cancel,
        )
        .unwrap();
    let observed = session.run(None, &limits, &cancel).unwrap();
    assert_eq!(observed.relations["targets"], vec![vec![4.into()].into()]);
    let proof = session
        .provenance(
            observed.result_handle,
            "targets",
            &gerbil_ascent::ProvenanceLimits::default(),
            &cancel,
        )
        .unwrap();
    assert!(
        proof
            .verify(
                &proof.graph().unwrap(),
                &gerbil_ascent::ProvenanceLimits::default(),
                &cancel
            )
            .unwrap()
    );
}
