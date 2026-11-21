use crate::{Runtime, values};
use gerbil_ascent::Data;
#[test]
fn original_scheme_dsl_values_calls_and_failure_recovery() {
    eprintln!("NATIVE init begin");
    let runtime = Runtime::initialize().unwrap();
    eprintln!("NATIVE init complete");
    check_native_values(&runtime);
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
    check_fresh_description(&description);
    check_source_projection_transport(&runtime);
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

fn check_native_values(runtime: &Runtime) {
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
        assert_eq!(values::decode(root, false).unwrap(), packet);
    }
    check_integer_edges(runtime);
}

fn check_fresh_description(description: &Data) {
    assert_eq!(description.field("abi").unwrap(), &Data::from(1usize));
    assert_eq!(
        description.field("sourceScopes").unwrap(),
        &Data::from(0usize)
    );
}

fn check_source_projection_transport(runtime: &Runtime) {
    use gerbil_ascent::{Cancellation, Catalog, Limits};
    for rows in [
        "((-9223372036854775808 0) (-9223372036854775808 0) (0 9223372036854775807))",
        "((0 9223372036854775808))",
        "((#f 7))",
        "((#(1) #(2)))",
        "()",
    ] {
        let source = format!(
            "(ascent (relation edge (a b) '{rows}) (relation reach (a b)) ((reach a b) <-- (edge a b)))"
        );
        let opened = runtime
            .call(&Data::object([
                ("operation", Data::from("open-sources")),
                ("sources", Data::List(vec![Data::from(source)])),
            ]))
            .unwrap();
        let handle = opened.field("handle").unwrap().clone();
        let control =
            crate::control::Control::new(&Limits::default(), &Cancellation::default()).unwrap();
        let request = Data::object([
            ("operation", Data::from("source-projection")),
            ("handle", handle.clone()),
            ("executionControl", control.id()),
        ]);
        // Use the original unwrapped C ABI, under the identical live authority.
        let input = values::encode(&runtime.runtime, &request).unwrap();
        // SAFETY: the export borrows an owner-local root and returns a fresh
        // root from the same linked program; no pointer crosses a thread.
        let export = unsafe {
            runtime
                .runtime
                .bind_object_export(crate::ffi::ascent_hybrid_call)
        }
        .unwrap();
        let response = export.call(&input).into_result().unwrap();
        let ordinary =
            crate::application::decode_response(values::decode(response, false).unwrap()).unwrap();
        let packed = runtime.call(&request).unwrap();
        assert_eq!(packed, ordinary, "complete source catalogue for {rows}");
        assert_eq!(
            packed.field("sourceGeneration").unwrap(),
            &Data::from(0usize)
        );
        Catalog::read(packed.field("program").unwrap()).unwrap();
        runtime
            .call(&Data::object([
                ("operation", Data::from("close")),
                ("handle", handle),
            ]))
            .unwrap();
    }
    check_projection_packet_context(runtime);
}

fn check_projection_packet_context(runtime: &Runtime) {
    use gerbil_scheme::{CollectionKind, GerbilRuntime, SchemeScalar, TableEquality};
    fn field<'r>(
        runtime: &'r GerbilRuntime,
        key: &str,
        value: &values::Root<'r>,
    ) -> values::Root<'r> {
        let key = runtime.string_from_utf8(key).unwrap().into_object();
        runtime
            .gerbil_hash_table(TableEquality::Structural, &[(&key, value)])
            .unwrap()
    }
    for key in ["rows", "columns"] {
        let vm = &runtime.runtime;
        let packet = vm.numeric_vector(&[1_i64, 1, 7]).unwrap();
        let relation = field(vm, key, &packet);
        let relations = vm
            .collection_from_objects(CollectionKind::List, &[&relation])
            .unwrap()
            .into_object();
        let program = field(vm, "relations", &relations);
        let result = field(vm, "program", &program);
        let success = vm.scalar_object(SchemeScalar::Boolean(true)).unwrap();
        let envelope = vm
            .collection_from_objects(CollectionKind::Vector, &[&success, &result])
            .unwrap()
            .into_object();
        let decoded = values::decode(envelope, true);
        if key == "rows" {
            let decoded = decoded.unwrap();
            let relation = &decoded.list().unwrap()[1]
                .field("program")
                .unwrap()
                .field("relations")
                .unwrap()
                .list()
                .unwrap()[0];
            assert_eq!(
                relation.field("rows").unwrap(),
                &Data::List(vec![Data::List(vec![Data::from(7usize)])])
            );
        } else {
            assert!(decoded.is_err(), "metadata vectors are not row packets");
        }
    }
    let packet = runtime.runtime.numeric_vector(&[1_i64, 1, 7]).unwrap();
    assert!(values::decode(packet, true).is_err());
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
    let packet = Data::object([
        (
            "integers",
            Data::List(integers.into_iter().map(Data::Integer).collect()),
        ),
        (
            "nested",
            Data::List(vec![Data::object([
                ("enabled", Data::Bool(false)),
                ("label", Data::from("nested")),
                ("coordinate", Data::Real((-0.0_f64).to_bits())),
            ])]),
        ),
    ]);
    let root = values::encode(&runtime.runtime, &packet).unwrap();
    assert_eq!(values::decode(root, false).unwrap(), packet);
}

#[test]
fn integer_row_packets_require_an_exact_positive_rectangle() {
    for malformed in [
        &[][..],
        &[1],
        &[0, 1],
        &[1, 0],
        &[-1, 1, 0],
        &[1, -1, 0],
        &[i64::MAX, i64::MAX, 0],
        &[1, 2, 0],
        &[1, 1, 0, 1],
    ] {
        assert!(values::decode_integer_rows(malformed).is_err());
    }
    assert_eq!(
        values::decode_integer_rows(&[2, 2, i64::MIN, 0, -7, i64::MAX]).unwrap(),
        Data::List(vec![
            Data::List(vec![Data::Integer(i64::MIN.into()), 0usize.into()]),
            Data::List(vec![
                Data::Integer((-7_i64).into()),
                Data::Integer(i64::MAX.into())
            ]),
        ]),
    );
}

#[cfg(all(feature = "instances", target_os = "macos"))]
fn bind_source_library(runtime: &Runtime) {
    unsafe extern "C" {
        fn ascent_hybrid_bind(root: i64) -> i64;
    }
    let manifest = gerbil_scheme_python::PackageManifest::from_json(include_bytes!(concat!(
        env!("OUT_DIR"),
        "/instance_inventory.json"
    )))
    .unwrap();
    let package = manifest
        .verify(std::path::Path::new(env!("ASCENT_INSTANCE_PACKAGE")))
        .unwrap();
    let paths = package
        .load_paths()
        .iter()
        .map(|path| Data::from(path.to_str().unwrap()))
        .collect();
    let input = Data::List(vec![
        Data::Integer((crate::control::ascent_hybrid_checkpoint as *const () as usize).into()),
        Data::List(paths),
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
