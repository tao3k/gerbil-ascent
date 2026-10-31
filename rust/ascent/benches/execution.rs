use gerbil_ascent::{
    Atom, Cancellation, Clause, Engine, Limits, Program, Relation, Row, Rule, Term, Type, Value,
};
use std::{
    hint::black_box,
    time::{Duration, Instant},
};

fn program() -> Program {
    let atom = |name: &str, vars: &[u32]| {
        Atom::new(name, vars.iter().copied().map(Term::Variable).collect())
    };
    Program {
        relation_limit: None,
        fact_limits: gerbil_ascent::FactLimits::default(),
        relations: vec![
            Relation::new("edge", vec![Type::Integer; 2], true),
            Relation::new("reach", vec![Type::Integer; 2], false),
        ],
        rules: vec![
            Rule {
                head: atom("reach", &[0, 1]),
                body: vec![Clause::positive(atom("edge", &[0, 1]))],
            },
            Rule {
                head: atom("reach", &[0, 2]),
                body: vec![
                    Clause::positive(atom("reach", &[0, 1])),
                    Clause::positive(atom("edge", &[1, 2])),
                ],
            },
        ],
    }
}
fn main() {
    ascent::ascent! {
        struct Oracle;
        relation edge(i64,i64);
        relation reach(i64,i64);
        reach(x,y) <-- edge(x,y);
        reach(x,z) <-- reach(x,y),edge(y,z);
    }
    let capacity = std::thread::available_parallelism().map_or(1, std::num::NonZero::get);
    let mut counts = vec![1, 2, 4, capacity];
    counts.sort_unstable();
    counts.dedup();
    println!("groups\tbackend\tworkers\tsample\twall_ns\toutput_rows");
    for groups in [16_i64, 64, 256] {
        let edges: Vec<_> = (0..groups)
            .flat_map(|g| (0..15).map(move |i| (g * 16 + i, g * 16 + i + 1)))
            .collect();
        let rows: Vec<Row> = edges
            .iter()
            .map(|(a, b)| vec![Value::from(*a), Value::from(*b)].into())
            .collect();
        let mut oracle = Oracle {
            edge: edges.clone(),
            ..Default::default()
        };
        oracle.run();
        oracle.reach.sort_unstable();
        let expected: Vec<Row> = oracle
            .reach
            .iter()
            .map(|(a, b)| vec![Value::from(*a), Value::from(*b)].into())
            .collect();
        let mut engines = vec![("scheme-aot-serial", Engine::serial().unwrap())];
        engines.extend(
            counts
                .iter()
                .map(|n| ("scheme-aot-rayon", Engine::new(*n).unwrap())),
        );
        // Alternate traversal direction; preserve all seven samples, not best-of.
        for sample in 0..7 {
            for index in 0..engines.len() {
                let (name, engine) = &engines[if sample % 2 == 0 {
                    index
                } else {
                    engines.len() - 1 - index
                }];
                let start = Instant::now();
                let mut session = engine.open(program()).unwrap();
                session.replace("edge", rows.clone()).unwrap();
                let result = session
                    .run(
                        &Limits {
                            timeout: Duration::from_secs(30),
                            ..Limits::default()
                        },
                        &Cancellation::default(),
                    )
                    .unwrap();
                let elapsed = start.elapsed().as_nanos();
                assert_eq!(result.relations["reach"], expected);
                black_box(&result);
                println!(
                    "{groups}\t{name}\t{}\t{sample}\t{elapsed}\t{}",
                    engine.threads(),
                    expected.len()
                );
            }
            let start = Instant::now();
            let mut oracle = Oracle {
                edge: edges.clone(),
                ..Default::default()
            };
            oracle.run();
            oracle.reach.sort_unstable();
            let elapsed = start.elapsed().as_nanos();
            assert_eq!(oracle.reach.len(), expected.len());
            black_box(&oracle);
            println!(
                "{groups}\trust-ascent-oracle\t1\t{sample}\t{elapsed}\t{}",
                expected.len()
            );
        }
    }
}
