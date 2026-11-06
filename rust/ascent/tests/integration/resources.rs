use gerbil_ascent::{
    Atom, Cancellation, Clause, Engine, Error, Limits, Program, Relation, Row, Rule, Term, Type,
    Value,
};
use std::{
    sync::{Arc, Barrier, mpsc},
    time::{Duration, Instant},
};

fn workers() -> &'static [usize] {
    if cfg!(feature = "rayon") {
        &[1, 2, 4, 8, 12]
    } else {
        &[1]
    }
}
fn copy_program(width: usize, copies: usize) -> Program {
    let terms: Vec<_> = (0..width)
        .map(|i| Term::Variable(u32::try_from(i).unwrap()))
        .collect();
    Program {
        relation_limit: None,
        fact_limits: gerbil_ascent::FactLimits::default(),
        relations: vec![
            Relation::new("input", vec![Type::Integer; width], true),
            Relation::new("output", vec![Type::Integer; width], false),
        ],
        rules: (0..copies)
            .map(|_| Rule {
                head: Atom::new("output", terms.clone()),
                body: vec![Clause::positive(Atom::new("input", terms.clone()))],
            })
            .collect(),
    }
}
fn unary_rows(n: usize) -> Vec<Row> {
    (0..n)
        .map(|i| vec![Value::from(i64::try_from(i).unwrap())].into())
        .collect()
}
#[test]
fn work_and_fact_limits_are_exact_at_chunk_boundaries() {
    for &threads in workers() {
        let engine = Engine::new(threads).unwrap();
        for n in [0, 1, 127, 128, 129, 255, 256, 257] {
            let mut session = engine.open(copy_program(1, 1)).unwrap();
            session.replace("input", unary_rows(n)).unwrap();
            let exact = Limits {
                max_states: n * 2,
                max_facts: n * 2,
                ..Limits::default()
            };
            let result = session.run(&exact, &Cancellation::default()).unwrap();
            assert_eq!(result.relations["output"].len(), n);
            if n == 0 {
                continue;
            }
            for (limits, error) in [
                (
                    Limits {
                        max_states: n * 2 - 1,
                        ..exact.clone()
                    },
                    Error::StateLimit,
                ),
                (
                    Limits {
                        max_facts: n * 2 - 1,
                        ..exact.clone()
                    },
                    Error::FactLimit,
                ),
            ] {
                let mut candidate = engine.open(copy_program(1, 1)).unwrap();
                candidate.replace("input", unary_rows(n)).unwrap();
                assert_eq!(
                    candidate.run(&limits, &Cancellation::default()),
                    Err(error),
                    "workers={threads} n={n}"
                );
                assert!(candidate.last_completed().is_none());
            }
        }
    }
}
#[test]
fn duplicate_rules_charge_work_but_only_unique_facts() {
    for &threads in workers() {
        let engine = Engine::new(threads).unwrap();
        let mut session = engine.open(copy_program(1, 16)).unwrap();
        session.replace("input", unary_rows(257)).unwrap();
        let exact = Limits {
            max_states: 257 * 2 * 16,
            max_facts: 257 * 2,
            ..Limits::default()
        };
        let result = session.run(&exact, &Cancellation::default()).unwrap();
        assert_eq!(result.relations["output"], unary_rows(257));
        session.replace("input", unary_rows(258)).unwrap();
        assert_eq!(
            session.run(
                &Limits {
                    max_facts: 515,
                    ..Limits::default()
                },
                &Cancellation::default()
            ),
            Err(Error::FactLimit)
        );
        assert_eq!(session.last_completed(), Some(result.clone()));
        assert_eq!(
            session
                .run(&exact, &Cancellation::default())
                .unwrap()
                .relations,
            result.relations
        );
    }
}
#[test]
fn wide_bindings_and_multi_column_index_keys_spill_without_changing_results() {
    let mut program = copy_program(12, 1);
    let repeated = program.rules[0].body[0].clone();
    program.rules[0].body.push(repeated);
    let row: Row = (0_i64..12).map(Value::from).collect::<Vec<_>>().into();
    for &threads in workers() {
        let mut session = Engine::new(threads).unwrap().open(program.clone()).unwrap();
        session.replace("input", vec![row.clone()]).unwrap();
        let result = session
            .run(&Limits::default(), &Cancellation::default())
            .unwrap();
        assert_eq!(result.relations["output"], vec![row.clone()]);
    }
}
fn expensive_program() -> Program {
    let mut program = copy_program(1, 1);
    program.rules[0].body.push(Clause::positive(Atom::new(
        "input",
        vec![Term::Variable(1)],
    )));
    program
}
#[test]
fn cancellation_and_deadline_during_large_evaluation_preserve_completed_snapshot() {
    let mut session = Engine::new(if cfg!(feature = "rayon") { 4 } else { 1 })
        .unwrap()
        .open(expensive_program())
        .unwrap();
    session.replace("input", unary_rows(1)).unwrap();
    let before = session
        .run(&Limits::default(), &Cancellation::default())
        .unwrap();
    session.replace("input", unary_rows(4000)).unwrap();
    let barrier = Arc::new(Barrier::new(2));
    let worker_barrier = barrier.clone();
    let cancellation = Cancellation::default();
    let worker_cancel = cancellation.clone();
    let (sender, receiver) = mpsc::channel();
    let handle = std::thread::spawn(move || {
        worker_barrier.wait();
        let result = session.run(
            &Limits {
                max_states: usize::MAX,
                ..Limits::default()
            },
            &worker_cancel,
        );
        sender.send((session, result)).unwrap();
    });
    barrier.wait();
    std::thread::sleep(Duration::from_millis(5));
    let canceled_at = Instant::now();
    cancellation.cancel();
    let (mut session, result) = receiver
        .recv_timeout(Duration::from_secs(2))
        .expect("cancellation did not return within the bound");
    handle.join().unwrap();
    assert_eq!(result, Err(Error::Canceled));
    assert!(canceled_at.elapsed() < Duration::from_secs(2));
    assert_eq!(session.last_completed(), Some(before.clone()));
    session.replace("input", unary_rows(4000)).unwrap();
    assert_eq!(
        session.run(
            &Limits {
                timeout: Duration::from_millis(1),
                max_states: usize::MAX,
                ..Limits::default()
            },
            &Cancellation::default()
        ),
        Err(Error::Timeout)
    );
    assert_eq!(session.last_completed(), Some(before.clone()));
    assert_eq!(
        session
            .run(&Limits::default(), &Cancellation::default())
            .unwrap()
            .relations,
        before.relations
    );
}

// A queued request keeps its caller's deadline. A stale request must not
// evaluate a failing expression and replace Timeout with an evaluation error.
#[cfg(feature = "rayon")]
#[test]
fn deadline_spans_rayon_queue_and_preserves_completed_snapshot() {
    use gerbil_ascent::{Expression, Operator};

    let pool = Arc::new(
        rayon::ThreadPoolBuilder::new()
            .num_threads(1)
            .build()
            .unwrap(),
    );
    let mut program = copy_program(1, 1);
    for relation in &mut program.relations {
        relation.columns = vec![Type::Any];
    }
    program.rules[0].body.push(Clause::Guard {
        inputs: vec![0],
        expression: Expression::Call(Operator::Even, vec![Expression::Term(Term::Variable(0))]),
    });
    let mut session = Engine::with_pool(pool.clone()).open(program).unwrap();
    session
        .replace("input", vec![vec![Value::from(2_i64)].into()])
        .unwrap();
    let before = session
        .run(&Limits::default(), &Cancellation::default())
        .unwrap();
    session
        .replace("input", vec![vec![Value::Text("invalid".into())].into()])
        .unwrap();

    let (entered, ready) = mpsc::sync_channel(1);
    let (release, blocked) = mpsc::sync_channel(1);
    pool.spawn(move || {
        entered.send(()).unwrap();
        blocked.recv_timeout(Duration::from_secs(2)).unwrap();
    });
    ready.recv_timeout(Duration::from_secs(2)).unwrap();
    let timer = std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(250));
        release.send(()).unwrap();
    });
    let result = session.run(
        &Limits {
            timeout: Duration::from_millis(10),
            ..Limits::default()
        },
        &Cancellation::default(),
    );
    timer.join().unwrap();
    assert_eq!(result, Err(Error::Timeout));
    assert_eq!(session.last_completed(), Some(before));
}

#[test]
fn work_distribution_preserves_results_limits_and_population() {
    use gerbil_ascent::WorkDistribution;
    for distribution in [
        WorkDistribution::Adaptive,
        WorkDistribution::AcrossRequests,
        WorkDistribution::WithinRequest,
    ] {
        for &threads in workers() {
            let engine = Engine::new(threads)
                .unwrap()
                .with_work_distribution(distribution);
            assert_eq!(engine.threads(), threads);
            assert_eq!(engine.work_distribution(), distribution);
            let mut session = engine.open(copy_program(1, 4)).unwrap();
            session.replace("input", unary_rows(1024)).unwrap();
            let complete = session
                .run(&Limits::default(), &Cancellation::default())
                .unwrap();
            assert_eq!(complete.relations["output"], unary_rows(1024));
            assert_eq!(engine.pending_evaluations(), 0);
            // Reuse is still checked; failed recomputation cannot publish partial data.
            assert_eq!(
                session
                    .run(&Limits::default(), &Cancellation::default())
                    .unwrap(),
                complete
            );
            session.replace("input", unary_rows(1025)).unwrap();
            for (limits, cancellation, error) in [
                (
                    Limits {
                        max_states: 1,
                        ..Limits::default()
                    },
                    Cancellation::default(),
                    Error::StateLimit,
                ),
                (
                    Limits {
                        max_facts: 1,
                        ..Limits::default()
                    },
                    Cancellation::default(),
                    Error::FactLimit,
                ),
                (
                    Limits {
                        timeout: Duration::ZERO,
                        ..Limits::default()
                    },
                    Cancellation::default(),
                    Error::Timeout,
                ),
            ] {
                assert_eq!(session.run(&limits, &cancellation), Err(error));
                assert_eq!(session.last_completed(), Some(complete.clone()));
                assert_eq!(engine.pending_evaluations(), 0);
            }
            let cancellation = Cancellation::default();
            cancellation.cancel();
            assert_eq!(
                session.run(&Limits::default(), &cancellation),
                Err(Error::Canceled)
            );
            assert_eq!(engine.pending_evaluations(), 0);
            assert_eq!(session.last_completed(), Some(complete));
        }
    }
}

#[test]
fn independent_relation_shards_obey_one_global_fact_limit() {
    let mut program = copy_program(1, 8);
    program.relations.truncate(1);
    for (i, rule) in program.rules.iter_mut().enumerate() {
        rule.head.relation = format!("output{i}");
        program.relations.push(Relation::new(
            &rule.head.relation,
            vec![Type::Integer],
            false,
        ));
    }
    for n in [63, 64, 65, 257, 511, 512, 513, 1024] {
        for &threads in workers() {
            let engine = Engine::new(threads).unwrap();
            let mut session = engine.open(program.clone()).unwrap();
            session.replace("input", unary_rows(n)).unwrap();
            let exact = Limits {
                max_facts: n * 9,
                max_states: n * 2 * 8,
                ..Limits::default()
            };
            let complete = session.run(&exact, &Cancellation::default()).unwrap();
            assert_eq!(
                complete.relations.values().map(Vec::len).sum::<usize>(),
                n * 9
            );
            let mut failing = engine.open(program.clone()).unwrap();
            failing.replace("input", unary_rows(n)).unwrap();
            assert_eq!(
                failing.run(
                    &Limits {
                        max_facts: n * 9 - 1,
                        ..exact
                    },
                    &Cancellation::default()
                ),
                Err(Error::FactLimit)
            );
            assert!(failing.last_completed().is_none());
        }
    }
}

#[test]
fn multiple_index_shapes_preserve_typed_equality_and_sorted_snapshots() {
    let types = vec![Type::Text, Type::Symbol, Type::Integer, Type::Boolean];
    let input: Vec<Row> = ["", "same", "中文", "z"]
        .into_iter()
        .flat_map(|text| {
            ["same", "中文"].into_iter().flat_map(move |symbol| {
                [i64::MAX, 0, i64::MIN].into_iter().flat_map(move |n| {
                    [true, false].into_iter().map(move |flag| {
                        vec![
                            Value::from(text),
                            Value::Symbol(symbol.into()),
                            Value::from(n),
                            Value::Boolean(flag),
                        ]
                        .into()
                    })
                })
            })
        })
        .collect();
    let selectors = [
        (vec![0], vec![Value::from("中文")]),
        (
            vec![0, 1],
            vec![Value::from("same"), Value::Symbol("中文".into())],
        ),
        (vec![2], vec![Value::from(i64::MIN)]),
        (vec![2, 3], vec![Value::from(0), Value::Boolean(false)]),
    ];
    let terms: Vec<_> = (0..4).map(Term::Variable).collect();
    let mut program = Program {
        relation_limit: None,
        fact_limits: gerbil_ascent::FactLimits::default(),
        relations: vec![Relation::new("table", types.clone(), true)],
        rules: vec![],
    };
    for (i, (columns, _)) in selectors.iter().enumerate() {
        let source = format!("selector{i}");
        let output = format!("output{i}");
        program.relations.push(Relation::new(
            &source,
            columns.iter().map(|c| types[*c]).collect(),
            true,
        ));
        program
            .relations
            .push(Relation::new(&output, types.clone(), false));
        program.rules.push(Rule {
            head: Atom::new(output, terms.clone()),
            body: vec![
                Clause::positive(Atom::new(
                    source,
                    columns.iter().map(|c| terms[*c].clone()).collect(),
                )),
                Clause::positive(Atom::new("table", terms.clone())),
            ],
        });
    }
    for &threads in workers() {
        let mut session = Engine::new(threads).unwrap().open(program.clone()).unwrap();
        for reverse in [false, true] {
            let mut submitted = input.clone();
            if reverse {
                submitted.reverse();
            }
            submitted.extend(input.iter().cloned());
            session.replace("table", submitted).unwrap();
            for (i, (_, values)) in selectors.iter().enumerate() {
                session
                    .replace(&format!("selector{i}"), vec![values.clone().into()])
                    .unwrap();
            }
            let snapshot = session
                .run(&Limits::default(), &Cancellation::default())
                .unwrap();
            for (i, (columns, values)) in selectors.iter().enumerate() {
                let mut expected: Vec<_> = input
                    .iter()
                    .filter(|row| columns.iter().zip(values).all(|(c, v)| row[*c] == *v))
                    .cloned()
                    .collect();
                expected.sort();
                assert_eq!(
                    snapshot.relations[&format!("output{i}")],
                    expected,
                    "workers={threads} reverse={reverse} index={columns:?}"
                );
            }
        }
    }
}

#[test]
fn large_sorted_publication_matches_serial_order() {
    let expected = unary_rows(20_000);
    let mut input = expected.clone();
    input.reverse();
    input.extend(expected.iter().cloned());
    for &threads in workers() {
        let mut session = Engine::new(threads)
            .unwrap()
            .open(copy_program(1, 1))
            .unwrap();
        session.replace("input", input.clone()).unwrap();
        let limits = Limits {
            max_states: 40_000,
            max_facts: 40_000,
            ..Limits::default()
        };
        let snapshot = session.run(&limits, &Cancellation::default()).unwrap();
        assert_eq!(snapshot.relations["input"], expected);
        assert_eq!(snapshot.relations["output"], expected);
    }
}

#[test]
fn relation_publishers_join_before_recursive_and_negative_consumers() {
    let pair = |name: &str, a, b| Atom::new(name, vec![Term::Variable(a), Term::Variable(b)]);
    let program = Program {
        relation_limit: None,
        fact_limits: gerbil_ascent::FactLimits::default(),
        relations: vec![
            Relation::new("edge", vec![Type::Integer; 2], true),
            Relation::new("blocked", vec![Type::Integer], true),
            Relation::new("reach", vec![Type::Integer; 2], false),
            Relation::new("mirror", vec![Type::Integer; 2], false),
            Relation::new("kept", vec![Type::Integer; 2], false),
        ],
        rules: vec![
            Rule {
                head: pair("reach", 0, 1),
                body: vec![Clause::positive(pair("edge", 0, 1))],
            },
            Rule {
                head: pair("reach", 0, 2),
                body: vec![
                    Clause::positive(pair("mirror", 0, 1)),
                    Clause::positive(pair("edge", 1, 2)),
                ],
            },
            Rule {
                head: pair("mirror", 0, 1),
                body: vec![Clause::positive(pair("reach", 0, 1))],
            },
            Rule {
                head: pair("mirror", 0, 1),
                body: vec![Clause::positive(pair("reach", 0, 1))],
            },
            Rule {
                head: pair("kept", 0, 1),
                body: vec![
                    Clause::positive(pair("mirror", 0, 1)),
                    Clause::negative(Atom::new("blocked", vec![Term::Variable(1)])),
                ],
            },
        ],
    };
    let make_pairs = |pairs: &[[i64; 2]]| -> Vec<Row> {
        pairs
            .iter()
            .map(|pair| {
                pair.iter()
                    .map(|n| Value::from(*n))
                    .collect::<Vec<_>>()
                    .into()
            })
            .collect()
    };
    let expected = make_pairs(&[[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]]);
    let kept = make_pairs(&[[0, 1], [0, 3], [1, 3], [2, 3]]);
    for &threads in workers() {
        let mut session = Engine::new(threads).unwrap().open(program.clone()).unwrap();
        for repetition in 0..8 {
            let mut input = make_pairs(&[[0, 1], [1, 2], [2, 3], [0, 1]]);
            if repetition % 2 == 0 {
                input.reverse();
            }
            session.replace("edge", input).unwrap();
            session
                .replace("blocked", vec![vec![Value::from(2)].into()])
                .unwrap();
            let limits = Limits {
                max_facts: 20,
                ..Limits::default()
            };
            let snapshot = session.run(&limits, &Cancellation::default()).unwrap();
            assert_eq!(snapshot.relations["reach"], expected);
            assert_eq!(snapshot.relations["mirror"], expected);
            assert_eq!(snapshot.relations["kept"], kept);
            session
                .replace("edge", make_pairs(&[[4, 5], [5, 6], [6, 7]]))
                .unwrap();
            session
                .replace("blocked", vec![vec![Value::from(6)].into()])
                .unwrap();
            assert_eq!(
                session.run(
                    &Limits {
                        max_facts: 19,
                        ..limits.clone()
                    },
                    &Cancellation::default()
                ),
                Err(Error::FactLimit)
            );
            assert_eq!(session.last_completed(), Some(snapshot.clone()));
            assert_eq!(
                session
                    .run(&limits, &Cancellation::default())
                    .unwrap()
                    .relations,
                snapshot.relations
            );
        }
    }
}

#[test]
fn parallel_head_publication_precedes_recursive_and_stratified_readers() {
    let program = Program::read_rule_sources(&["(ascent
      (relation edge ((x integer?) (y integer?)))
      (relation blocked ((x integer?)))
      (relation r ((x integer?) (y integer?)))
      (relation s ((x integer?) (y integer?)))
      (relation kept ((x integer?) (y integer?)))
      ((r x y) <-- (edge x y))
      ((s x y) <-- (edge x y))
      ((r x z) <-- (s x y) (edge y z))
      ((s x y) <-- (r x y))
      ((kept x y) <-- (s x y) (not (blocked y))))"])
    .unwrap();
    let pair = |a, b| -> Row { vec![Value::from(a), Value::from(b)].into() };
    let mut edges = Vec::new();
    let mut blocked: Vec<Row> = Vec::new();
    let mut closure = Vec::new();
    let mut kept = Vec::new();
    for group in 0_i64..128 {
        let base = 4 * group;
        for i in 0..3 {
            edges.push(pair(base + i, base + i + 1));
        }
        blocked.push(vec![Value::from(base + 2)].into());
        for i in 0..4 {
            for j in i + 1..4 {
                closure.push(pair(base + i, base + j));
                if j != 2 {
                    kept.push(pair(base + i, base + j));
                }
            }
        }
    }
    for &threads in workers() {
        let engine = Engine::new(threads).unwrap();
        for cap in [2560, 2559] {
            let mut session = engine.open(program.clone()).unwrap();
            session.replace("edge", edges.clone()).unwrap();
            session.replace("blocked", blocked.clone()).unwrap();
            let result = session.run(
                &Limits {
                    max_facts: cap,
                    ..Limits::default()
                },
                &Cancellation::default(),
            );
            if cap == 2559 {
                assert_eq!(result, Err(Error::FactLimit));
                assert!(session.last_completed().is_none());
            } else {
                let snapshot = result.unwrap();
                assert_eq!(snapshot.relations["r"], closure);
                assert_eq!(snapshot.relations["s"], closure);
                assert_eq!(snapshot.relations["kept"], kept);
            }
        }
    }
}
