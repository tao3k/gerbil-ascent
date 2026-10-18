use gerbil_ascent::{Cancellation, Engine, Limits, Program, Row, Value};

#[test]
fn existing_scheme_rule_fragments_load_at_runtime_without_a_compiler() {
    let program = Program::read_rule_sources(&[
        "; native Scheme rule data\n(ascent (relation edge ((x integer?) (y exact-integer?))) (relation reach ((x integer?) (y integer?))) ((reach x y) <-- (edge x y)))",
        "(ascent-fragment (relation edge ((x integer?) (y integer?))) ((reach x z) <-- (reach x y) (edge y z)))",
    ]).unwrap();
    let row = |a, b| -> Row { vec![Value::from(a), Value::from(b)].into() };
    for threads in if cfg!(feature = "rayon") {
        &[1, 4, 8, 12][..]
    } else {
        &[1][..]
    } {
        let mut session = Engine::new(*threads)
            .unwrap()
            .open(program.clone())
            .unwrap();
        session
            .replace("edge", vec![row(i64::MIN, 0), row(0, i64::MAX)])
            .unwrap();
        let snapshot = session
            .run(&Limits::default(), &Cancellation::default())
            .unwrap();
        assert_eq!(
            snapshot.relations["reach"],
            vec![row(i64::MIN, 0), row(i64::MIN, i64::MAX), row(0, i64::MAX)]
        );
    }
}
#[test]
fn malformed_or_executable_rule_sources_never_execute() {
    for text in [
        "(import :gerbil/runtime)",
        "#.(error \"execute\")",
        "(ascent)",
        "(ascent (relation a ((x integer?)))) trailing",
        "(ascent (relation a ((x integer?))) (() <-- (a x)))",
        "(ascent (relation a ((x unknown?))))",
    ] {
        assert!(
            Program::read_rule_sources(&[text])
                .and_then(|p| Engine::new(1).unwrap().open(p))
                .is_err(),
            "{text}"
        );
    }
    assert!(Program::read_rule_sources(&[&"x".repeat(65_537)]).is_err());
    assert!(
        Program::read_rule_sources(&[&format!("{}{}", "(".repeat(130), ")".repeat(130))]).is_err()
    );
}
