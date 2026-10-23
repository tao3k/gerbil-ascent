use crate::{Runtime, values};
use gerbil_ascent::Data;
#[test]
fn original_scheme_dsl_values_calls_and_failure_recovery() {
    eprintln!("NATIVE init begin");
    let runtime = Runtime::initialize().unwrap();
    eprintln!("NATIVE init complete");
    let packets = [
        Data::Null,
        Data::Bool(false),
        Data::Bool(true),
        Data::Integer((-1_234_567_891_011_121_314_151_617_181_920_212_223i128).into()),
        Data::Text("原生\0Scheme 🦀".into()),
        Data::object([(
            "items",
            Data::List(vec![Data::from(42usize), Data::Bool(false)]),
        )]),
    ];
    for packet in packets {
        eprintln!("NATIVE packet {packet:?}");
        let root = values::encode(&runtime.runtime, &packet).unwrap();
        assert_eq!(values::decode(root, 0).unwrap(), packet);
    }
    check_integer_edges(&runtime);
    #[cfg(all(feature = "instances", target_os = "macos"))]
    bind_source_library(&runtime);
    let call = |fields| runtime.call(&Data::Map(fields));
    let request = |operation: &str, fields: Vec<(&str, Data)>| {
        let mut out =
            std::collections::BTreeMap::from([("operation".into(), Data::from(operation))]);
        out.extend(fields.into_iter().map(|(k, v)| (k.into(), v)));
        out
    };
    let description = call(request("describe", vec![])).unwrap();
    assert_eq!(description.field("abi").unwrap(), &Data::from(1usize));
    assert!(call(request("unknown", vec![])).is_err());
    let module = call(request("dsl-open", vec![
            ("source", Data::from("(def answer (lambda () 1)) (def (replace n) (set! answer (lambda () n))) (def (reader) (lambda () (answer))) (def (numbers x) (let-values (((a b) (values x 1/3))) (vector a b)))")),
            ("trusted", Data::Bool(true)),
        ])).unwrap();
    let owner = module.field("owner").unwrap().clone();
    let result = call(request(
        "module-call",
        vec![
            ("owner", owner.clone()),
            ("export", Data::from("reader")),
            ("arguments", Data::List(vec![])),
        ],
    ))
    .unwrap();
    let callable = result.field("valueHandle").unwrap().clone();
    for n in [1usize, 7, 8] {
        call(request(
            "module-call",
            vec![
                ("owner", owner.clone()),
                ("export", Data::from("replace")),
                ("arguments", Data::List(vec![Data::from(n)])),
            ],
        ))
        .unwrap();
        let result = call(request(
            "module-apply",
            vec![
                ("owner", owner.clone()),
                ("value", callable.clone()),
                ("arguments", Data::List(vec![])),
            ],
        ))
        .unwrap();
        assert_eq!(
            result
                .field("value")
                .unwrap()
                .field("root")
                .unwrap()
                .field("value")
                .unwrap(),
            &Data::from(n.to_string())
        );
    }
    let complex = call(request(
        "module-call",
        vec![
            ("owner", owner.clone()),
            ("export", Data::from("numbers")),
            ("arguments", Data::List(vec![Data::from(9usize)])),
        ],
    ))
    .unwrap();
    assert!(format!("{complex:?}").contains("1/3"));
    call(request("module-close", vec![("owner", owner.clone())])).unwrap();
    assert!(
        call(request(
            "module-apply",
            vec![
                ("owner", owner),
                ("value", callable),
                ("arguments", Data::List(vec![]))
            ]
        ))
        .is_err()
    );
    assert!(call(request("describe", vec![])).is_ok());
}

fn check_integer_edges(runtime: &Runtime) {
    // Exercise native fixnum edges and the exact arbitrary-precision fallback
    // on both sides of the host word, including nested borrowed projections.
    let integers = [
        num_bigint::BigInt::from(0),
        num_bigint::BigInt::from(isize::MIN),
        num_bigint::BigInt::from(isize::MAX),
        -(num_bigint::BigInt::from(1) << 61usize),
        (num_bigint::BigInt::from(1) << 61usize) - 1,
        num_bigint::BigInt::from(1) << 61usize,
        num_bigint::BigInt::from(1) << 4096usize,
        -(num_bigint::BigInt::from(1) << 4096usize),
    ];
    let packet = Data::List(integers.into_iter().map(Data::Integer).collect());
    let root = values::encode(&runtime.runtime, &packet).unwrap();
    assert_eq!(values::decode(root, 0).unwrap(), packet);
}

#[cfg(all(feature = "instances", target_os = "macos"))]
fn bind_source_library(runtime: &Runtime) {
    unsafe extern "C" {
        fn ascent_hybrid_bind(root: i64) -> i64;
    }
    let input = Data::List(vec![
        Data::Integer((crate::control::ascent_hybrid_checkpoint as *const () as usize).into()),
        Data::from(concat!(env!("ASCENT_INSTANCE_PACKAGE"), "/_owners/lib")),
    ]);
    let fields = input
        .list()
        .unwrap()
        .iter()
        .map(|item| values::encode(&runtime.runtime, item).unwrap())
        .collect::<Vec<_>>();
    let input = runtime
        .runtime
        .collection_from_objects(
            gerbil_scheme::CollectionKind::Vector,
            &fields.iter().collect::<Vec<_>>(),
        )
        .unwrap()
        .into_object();
    // SAFETY: this same build-owned rooted export initializes only the
    // module-source carrier policy, allowing comparison with linked setup.
    let binding = unsafe { runtime.runtime.bind_object_export(ascent_hybrid_bind) }.unwrap();
    drop(binding.call(&input).into_result().unwrap());
}
