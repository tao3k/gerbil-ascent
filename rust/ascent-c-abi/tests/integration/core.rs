//! Real existing Core algorithms called through the fixed C ABI owner contract.
use gerbil_scheme_python::{OwnedValue as V, ValueLimits, c_abi::ForeignCallable};
use std::collections::BTreeMap;
const SOURCE: &str = "(define-program (history)
 (sources current previous) (outputs added removed current)
 (relation current ((x exact-integer?)) ((1) (2)))
 (relation previous ((x exact-integer?)) ((1)))
 (relation added ((x exact-integer?))) (relation removed ((x exact-integer?)))
 ((added X) <-- (current X) (not (previous X)))
 ((removed X) <-- (previous X) (not (current X))))";
fn text(v: &str) -> V {
    V::Text(v.into())
}
fn map<const N: usize>(fields: [(&str, V); N]) -> V {
    V::Map(fields.into_iter().map(|(k, v)| (k.into(), v)).collect())
}
fn captures(source: &str) -> V {
    map([
        ("sources", V::List(vec![text(source)])),
        ("constructor", V::Null),
        ("workers", V::Integer(1.into())),
        (
            "limits",
            map([
                ("input", V::Null),
                ("derived", V::Null),
                ("output", V::Null),
            ]),
        ),
    ])
}
fn run() -> V {
    map([
        ("method", text("run")),
        ("queries", V::Null),
        ("timeoutNanoseconds", V::Integer(1_000_000_000_u64.into())),
    ])
}
fn response(call: &ForeignCallable, input: &V) -> V {
    call.call(input)
        .unwrap()
        .decode(ValueLimits::default())
        .unwrap()
}
fn field<'a>(value: &'a V, key: &str) -> &'a V {
    let V::Map(value) = value else {
        panic!("map required");
    };
    &value[key]
}
fn ok(value: &V) -> &V {
    assert_eq!(field(value, "ok"), &V::Boolean(true));
    field(value, "value")
}
fn updates(rows: V) -> V {
    map([
        ("method", text("replace")),
        ("sources", map([("current", rows)])),
    ])
}

#[test]
fn fixed_closure_budget_rollback_and_retained_cut_lifetimes() {
    let call = ascent_c_abi::open_reachability(&map([])).unwrap();
    let insert = |a: i64, b: i64, budget: usize| {
        map([
            ("method", text("insert")),
            (
                "edge",
                V::List(vec![V::Integer(a.into()), V::Integer(b.into())]),
            ),
            ("budget", V::Integer(budget.into())),
        ])
    };
    assert_eq!(
        ok(&response(&call, &insert(0, 1, 3))),
        &V::Integer(3.into())
    );
    let cut = ok(&response(&call, &map([("method", text("freeze"))]))).clone();
    let resources = ok(&response(&call, &map([("method", text("resources"))]))).clone();
    assert_eq!(
        field(&response(&call, &insert(1, 2, 2)), "ok"),
        &V::Boolean(false)
    );
    assert_eq!(
        ok(&response(&call, &map([("method", text("resources"))]))),
        &resources
    );
    assert_eq!(
        ok(&response(&call, &insert(1, 2, 3))),
        &V::Integer(3.into())
    );
    let rows = map([
        ("method", text("rows")),
        ("cut", cut.clone()),
        ("columns", V::List(vec![])),
        ("key", V::List(vec![])),
        ("limit", V::Integer(3.into())),
    ]);
    let held = ok(&response(&call, &rows)).clone();
    ok(&response(&call, &map([("method", text("close-state"))])));
    assert_eq!(ok(&response(&call, &rows)), &held);
    assert_eq!(
        field(&response(&call, &insert(2, 3, 100)), "ok"),
        &V::Boolean(false)
    );
    ok(&response(
        &call,
        &map([("method", text("release-cut")), ("cut", cut)]),
    ));
    assert_eq!(field(&response(&call, &rows), "ok"), &V::Boolean(false));
}

#[test]
fn evidence_runs_withdraws_and_retains_immutable_results_through_c_abi() {
    let call = ascent_c_abi::open(&captures(SOURCE)).unwrap();
    let first = call.call(&run()).unwrap();
    let value = first.decode(ValueLimits::default()).unwrap();
    assert_eq!(field(ok(&value), "sourceGeneration"), &V::Integer(0.into()));
    let handle = field(ok(&value), "resultHandle").clone();
    let explanation = call
        .call(&map([
            ("method", text("explain")),
            ("handle", handle),
            ("query", text("added")),
        ]))
        .unwrap();
    let metadata = explanation.decode(ValueLimits::default()).unwrap();
    assert_eq!(field(ok(&metadata), "status"), &text("recorded-only"));
    let repeat = response(&call, &run());
    assert_eq!(field(ok(&repeat), "reused"), &V::Boolean(true));
    let before = ok(&response(&call, &map([("method", text("describe"))]))).clone();
    let invalid = response(
        &call,
        &updates(V::List(vec![V::List(vec![V::Boolean(true)])])),
    );
    assert_eq!(field(&invalid, "ok"), &V::Boolean(false));
    assert_eq!(
        ok(&response(&call, &map([("method", text("describe"))]))),
        &before
    );
    assert_eq!(
        ok(&response(&call, &updates(V::List(vec![])))),
        &V::Integer(1.into())
    );
    let changed = response(&call, &run());
    assert_eq!(
        field(ok(&changed), "sourceGeneration"),
        &V::Integer(1.into())
    );
    call.close().unwrap();
    assert!(call.call(&run()).is_err());
    assert_eq!(first.decode(ValueLimits::default()).unwrap(), value);
    assert_eq!(
        explanation.decode(ValueLimits::default()).unwrap(),
        metadata
    );
}

#[test]
fn fixed_export_matches_existing_core_non_scalar_algorithm() {
    let source = "(define-program (graphs) (sources) (outputs objects)
      (relation objects (value) (((object-graph (ref 0) ((0 vector (ref 0))))))))";
    let call = ascent_c_abi::open(&captures(source)).unwrap();
    let observed = response(&call, &run());
    let core = gerbil_ascent::Engine::new(1).unwrap();
    let mut session = core
        .open_declaration_sources(&[source], None, gerbil_ascent::FactLimits::default())
        .unwrap();
    let actual = session
        .run(
            None,
            &gerbil_ascent::SourceSession::default_limits(),
            &gerbil_ascent::Cancellation::default(),
        )
        .unwrap();
    let expected = gerbil_ascent::rows_graph(&actual.relations["objects"])
        .unwrap()
        .to_scheme();
    let V::Map(relations) = field(ok(&observed), "relations") else {
        panic!("relations required");
    };
    // Both paths use the same Core graph algorithm, preserving the cyclic edge.
    assert_eq!(relations["objects"], native(&expected));
    call.close().unwrap();
}
fn native(v: &gerbil_ascent::Data) -> V {
    use gerbil_ascent::Data as D;
    match v {
        D::Null => V::Null,
        D::Bool(v) => V::Boolean(*v),
        D::Integer(v) => V::Integer(v.clone()),
        D::Real(v) => V::Real(f64::from_bits(*v)),
        D::Text(v) => text(v),
        D::List(v) => V::List(v.iter().map(native).collect()),
        D::Map(v) => V::Map(
            v.iter()
                .map(|(k, v)| (k.clone(), native(v)))
                .collect::<BTreeMap<_, _>>(),
        ),
    }
}

#[test]
fn independent_fixed_owners_execute_on_parallel_host_threads() {
    let barrier = std::sync::Arc::new(std::sync::Barrier::new(2));
    std::thread::scope(|scope| {
        let handles = (0..2)
            .map(|_| {
                let barrier = barrier.clone();
                scope.spawn(move || {
                    let call = ascent_c_abi::open(&captures(SOURCE)).unwrap();
                    barrier.wait();
                    for _ in 0..5 {
                        ok(&response(&call, &run()));
                    }
                    call.close().unwrap();
                })
            })
            .collect::<Vec<_>>();
        for handle in handles {
            handle.join().unwrap();
        }
    });
}

#[test]
fn initialization_and_unknown_fixed_operations_fail_without_fallback() {
    assert!(ascent_c_abi::open(&captures("(import :gerbil/runtime)")).is_err());
    let call = ascent_c_abi::open(&captures(SOURCE)).unwrap();
    let denied = response(&call, &map([("method", text("evaluate-arbitrary-code"))]));
    assert_eq!(field(&denied, "ok"), &V::Boolean(false));
    assert_eq!(
        field(ok(&response(&call, &run())), "sourceGeneration"),
        &V::Integer(0.into())
    );
}

fn component_captures(exports: V) -> V {
    let mut input = captures(SOURCE);
    let V::Map(fields) = &mut input else {
        panic!("capture packet");
    };
    fields.remove("sources");
    fields.insert("entry".into(), text("entry"));
    fields.insert("constructor".into(), text("make"));
    fields.insert("components".into(), V::List(vec![
        map([
            ("id", text("shared")),
            ("source", text("(def f (ascent-fragment ((answer X) <-- (input X))))")),
            ("exports", exports),
            ("dependencies", V::List(vec![])),
        ]),
        map([
            ("id", text("entry")),
            ("source", text("(define-program (make) (sources input) (outputs answer) (relation input ((x exact-integer?)) ((3) (7))) (relation answer ((x exact-integer?))) (include f))")),
            ("exports", V::List(vec![text("make")])),
            ("dependencies", V::List(vec![map([
                ("component", text("shared")),
                ("bindings", V::List(vec![text("f")])),
            ])])),
        ]),
    ]));
    input
}

#[test]
fn components_link_and_withdraw_through_the_fixed_c_abi() {
    let call = ascent_c_abi::open(&component_captures(V::List(vec![text("f")]))).unwrap();
    let mut request = run();
    let V::Map(fields) = &mut request else {
        panic!("run packet");
    };
    fields.insert("resultFormat".into(), text("typed-rows"));
    let result = response(&call, &request);
    assert_eq!(
        field(field(ok(&result), "relations"), "answer"),
        &V::List(vec![
            V::List(vec![V::Integer(3.into())]),
            V::List(vec![V::Integer(7.into())])
        ])
    );
    let replacement = map([
        ("method", text("replace")),
        ("sources", map([("input", V::List(vec![]))])),
    ]);
    assert_eq!(ok(&response(&call, &replacement)), &V::Integer(1.into()));
    let withdrawn = response(&call, &request);
    assert_eq!(
        field(field(ok(&withdrawn), "relations"), "answer"),
        &V::List(vec![])
    );
    assert!(ascent_c_abi::open(&component_captures(V::List(vec![]))).is_err());
    let mut ambiguous = component_captures(V::List(vec![text("f")]));
    let V::Map(fields) = &mut ambiguous else {
        panic!("capture packet");
    };
    fields.insert("sources".into(), V::List(vec![text(SOURCE)]));
    assert!(ascent_c_abi::open(&ambiguous).is_err());
    call.close().unwrap();
    assert!(call.call(&request).is_err());
}

#[test]
fn explicit_typed_rows_preserve_native_answers_and_reject_unknown_formats() {
    let call = ascent_c_abi::open(&captures(SOURCE)).unwrap();
    let mut request = run();
    let V::Map(fields) = &mut request else {
        panic!("run packet");
    };
    fields.insert("resultFormat".into(), text("typed-rows"));
    let result = response(&call, &request);
    assert_eq!(field(ok(&result), "resultFormat"), &text("typed-rows"));
    assert_eq!(
        field(field(ok(&result), "relations"), "added"),
        &V::List(vec![V::List(vec![V::Integer(2.into())])])
    );
    let V::Map(fields) = &mut request else {
        panic!("run packet");
    };
    fields.insert("resultFormat".into(), text("auto"));
    assert_eq!(field(&response(&call, &request), "ok"), &V::Boolean(false));
    call.close().unwrap();
}

#[test]
fn precompiled_graph_closure_captures_and_state_cross_the_c_abi() {
    let mut input = captures(SOURCE);
    let V::Map(fields) = &mut input else {
        panic!("capture packet");
    };
    fields.remove("sources");
    fields.remove("constructor");
    fields.insert(
        "graph".into(),
        map([
            ("algorithm", text("transitive")),
            ("source", text("edge")),
            ("width", V::Integer(2.into())),
            ("output", text("path")),
            ("captures", map([])),
            (
                "rows",
                V::List(vec![
                    V::List(vec![V::Integer(1.into()), V::Integer(2.into())]),
                    V::List(vec![V::Integer(2.into()), V::Integer(3.into())]),
                ]),
            ),
        ]),
    );
    let call = ascent_c_abi::open(&input).unwrap();
    let mut request = run();
    let V::Map(fields) = &mut request else {
        panic!("run packet");
    };
    fields.insert("resultFormat".into(), text("typed-rows"));
    let original = call.call(&request).unwrap();
    let before = original.decode(ValueLimits::default()).unwrap();
    assert_eq!(
        field(field(ok(&before), "relations"), "path"),
        &V::List(vec![
            V::List(vec![V::Integer(1.into()), V::Integer(2.into())]),
            V::List(vec![V::Integer(1.into()), V::Integer(3.into())]),
            V::List(vec![V::Integer(2.into()), V::Integer(3.into())]),
        ])
    );
    ok(&response(
        &call,
        &map([
            ("method", text("replace")),
            ("sources", map([("edge", V::List(vec![]))])),
        ]),
    ));
    assert_eq!(
        field(field(ok(&response(&call, &request)), "relations"), "path"),
        &V::List(vec![])
    );
    call.close().unwrap();
    assert_eq!(original.decode(ValueLimits::default()).unwrap(), before);
    let V::Map(fields) = &mut input else {
        panic!("capture packet");
    };
    let V::Map(graph) = fields.get_mut("graph").unwrap() else {
        panic!("Graph packet");
    };
    graph.insert("algorithm".into(), text("eval-arbitrary-lambda"));
    assert!(ascent_c_abi::open(&input).is_err());
}

#[test]
fn declarative_match_and_finite_for_execute_through_the_c_abi() {
    let source = "(define-program (shapes) (sources seed packed) (outputs unpacked pair selected)
      (relation seed ((n exact-integer?)) ((7)))
      (relation packed (value) '((#(2 9)) (#(3 10)) (#(4))))
      (relation unpacked ((x exact-integer?) (y exact-integer?)))
      (relation pair ((x exact-integer?) (y exact-integer?)))
      (relation selected ((n exact-integer?)))
      ((unpacked X Y) <-- (packed V) (match (X Y) (V) (vector X Y)))
      ((pair X Y) <-- (seed N) (for (X Y) (N) (list (vector N (+ N 1)) (vector (+ N 2) N)) (vector X Y)))
      ((selected N) <-- (or (and (seed N)) (and (pair N V))) (if (N) (odd? N))))";
    let call = ascent_c_abi::open(&captures(source)).unwrap();
    let mut request = run();
    let V::Map(fields) = &mut request else {
        panic!("run packet");
    };
    fields.insert("resultFormat".into(), text("typed-rows"));
    let result = response(&call, &request);
    assert_eq!(
        field(field(ok(&result), "relations"), "unpacked"),
        &V::List(vec![
            V::List(vec![V::Integer(2.into()), V::Integer(9.into())]),
            V::List(vec![V::Integer(3.into()), V::Integer(10.into())]),
        ])
    );
    assert_eq!(
        field(field(ok(&result), "relations"), "pair"),
        &V::List(vec![
            V::List(vec![V::Integer(7.into()), V::Integer(8.into())]),
            V::List(vec![V::Integer(9.into()), V::Integer(7.into())]),
        ])
    );
    ok(&response(
        &call,
        &map([
            ("method", text("replace")),
            ("sources", map([("seed", V::List(vec![]))])),
        ]),
    ));
    assert_eq!(
        field(field(ok(&response(&call, &request)), "relations"), "pair"),
        &V::List(vec![])
    );
    let invalid = source.replace("(vector X Y)", "(vector X X)");
    assert!(ascent_c_abi::open(&captures(&invalid)).is_err());
    let callback = source.replace(
        "(list (vector N (+ N 1)) (vector (+ N 2) N))",
        "(arbitrary-callback N)",
    );
    assert!(ascent_c_abi::open(&captures(&callback)).is_err());
    let wrong_type = source.replace("#(2 9)", "#(2 #t)");
    assert!(ascent_c_abi::open(&captures(&wrong_type)).is_err());
    let empty = source.replace("(list (vector N (+ N 1)) (vector (+ N 2) N))", "(list)");
    let empty = ascent_c_abi::open(&captures(&empty)).unwrap();
    assert_eq!(
        field(field(ok(&response(&empty, &request)), "relations"), "pair"),
        &V::List(vec![])
    );
    assert_eq!(
        field(
            &response(
                &empty,
                &map([
                    ("method", text("replace")),
                    ("sources", map([("pair", V::List(vec![]))]))
                ])
            ),
            "ok"
        ),
        &V::Boolean(false)
    );
    empty.close().unwrap();
    call.close().unwrap();
}
