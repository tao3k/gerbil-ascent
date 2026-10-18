use gerbil_ascent::{
    Atom, Cancellation, Clause, Engine, Limits, Program, Relation, Row, Rule, Term, Type, Value,
};
use std::time::Instant;

#[derive(Clone, Copy)]
struct Shape {
    components: usize,
    groups: i64,
    width: i64,
}
impl Shape {
    fn edges(self) -> Vec<(i64, i64)> {
        (0..self.groups)
            .flat_map(|g| {
                (0..self.width - 1).map(move |i| (g * self.width + i, g * self.width + i + 1))
            })
            .collect()
    }
    fn truth(self) -> Vec<Row> {
        (0..self.groups)
            .flat_map(|g| {
                (0..self.width).flat_map(move |i| {
                    ((i + 1)..self.width).map(move |j| {
                        vec![
                            Value::from(g * self.width + i),
                            Value::from(g * self.width + j),
                        ]
                        .into()
                    })
                })
            })
            .collect()
    }
    fn program(self) -> Program {
        let mut program = Program::default();
        for i in 0..self.components {
            let edge = format!("edge{i}");
            let reach = format!("reach{i}");
            let atom = |name: &str, vars: &[u32]| {
                Atom::new(name, vars.iter().copied().map(Term::Variable).collect())
            };
            program.relations.extend([
                Relation::new(&edge, vec![Type::Integer; 2], true),
                Relation::new(&reach, vec![Type::Integer; 2], false),
            ]);
            program.rules.extend([
                Rule {
                    head: atom(&reach, &[0, 1]),
                    body: vec![Clause::positive(atom(&edge, &[0, 1]))],
                },
                Rule {
                    head: atom(&reach, &[0, 2]),
                    body: vec![
                        Clause::positive(atom(&reach, &[0, 1])),
                        Clause::positive(atom(&edge, &[1, 2])),
                    ],
                },
            ]);
        }
        program
    }
}
fn run(shape: Shape, workers: usize, samples: usize) {
    let engine = if workers == 0 {
        Engine::serial()
    } else {
        Engine::new(workers)
    }
    .unwrap();
    let rows: Vec<Row> = shape
        .edges()
        .iter()
        .map(|(a, b)| vec![Value::from(*a), Value::from(*b)].into())
        .collect();
    let expected = shape.truth();
    for sample in 0..=samples {
        let t0 = Instant::now();
        let mut session = engine.open(shape.program()).unwrap();
        let t1 = Instant::now();
        for i in 0..shape.components {
            session.replace(&format!("edge{i}"), rows.clone()).unwrap();
        }
        let t2 = Instant::now();
        let result = session
            .run(&Limits::default(), &Cancellation::default())
            .unwrap();
        let t3 = Instant::now();
        let output: Vec<_> = (0..shape.components)
            .map(|i| result.relations[&format!("reach{i}")].clone())
            .collect();
        let t4 = Instant::now();
        for actual in &output {
            assert_eq!(actual, &expected);
        }
        std::hint::black_box(&output);
        if sample > 0 {
            println!(
                "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\tNA\tNA\tNA",
                shape.components,
                shape.groups,
                shape.width,
                if workers == 0 {
                    "scheme-aot-serial"
                } else {
                    "scheme-aot-rayon"
                },
                workers.max(1),
                sample - 1,
                t1.duration_since(t0).as_nanos(),
                t2.duration_since(t1).as_nanos(),
                t3.duration_since(t2).as_nanos(),
                t4.duration_since(t3).as_nanos(),
                t4.duration_since(t0).as_nanos(),
                expected.len() * shape.components
            );
        }
    }
}
fn oracle_1(shape: Shape, samples: usize) {
    ascent::ascent! {
        struct Oracle;
        relation edge0(i64,i64);
        relation reach0(i64,i64);
        reach0(x,y) <-- edge0(x,y);
        reach0(x,z) <-- reach0(x,y),edge0(y,z);
    }
    let edges = shape.edges();
    let expected: Vec<_> = shape
        .truth()
        .iter()
        .map(|row| match (&row[0], &row[1]) {
            (Value::Integer(a), Value::Integer(b)) => {
                (i64::try_from(a).unwrap(), i64::try_from(b).unwrap())
            }
            _ => unreachable!(),
        })
        .collect();
    for sample in 0..=samples {
        let t0 = Instant::now();
        let mut oracle = Oracle::default();
        let t1 = Instant::now();
        oracle.edge0.clone_from(&edges);
        let t2 = Instant::now();
        oracle.run();
        let t3 = Instant::now();
        oracle.reach0.sort_unstable();
        let t4 = Instant::now();
        assert_eq!(oracle.reach0, expected);
        std::hint::black_box(&oracle);
        if sample > 0 {
            println!(
                "{}\t{}\t{}\trust-ascent-oracle\t1\t{}\t{}\t{}\t{}\t{}\t{}\t{}\tNA\tNA\tNA",
                shape.components,
                shape.groups,
                shape.width,
                sample - 1,
                t1.duration_since(t0).as_nanos(),
                t2.duration_since(t1).as_nanos(),
                t3.duration_since(t2).as_nanos(),
                t4.duration_since(t3).as_nanos(),
                t4.duration_since(t0).as_nanos(),
                expected.len() * shape.components
            );
        }
    }
}
fn oracle_8(shape: Shape, samples: usize) {
    ascent::ascent! {
        struct Oracle;
        relation edge0(i64,i64);
        relation reach0(i64,i64);
        reach0(x,y) <-- edge0(x,y);
        reach0(x,z) <-- reach0(x,y),edge0(y,z);
        relation edge1(i64,i64);
        relation reach1(i64,i64);
        reach1(x,y) <-- edge1(x,y);
        reach1(x,z) <-- reach1(x,y),edge1(y,z);
        relation edge2(i64,i64);
        relation reach2(i64,i64);
        reach2(x,y) <-- edge2(x,y);
        reach2(x,z) <-- reach2(x,y),edge2(y,z);
        relation edge3(i64,i64);
        relation reach3(i64,i64);
        reach3(x,y) <-- edge3(x,y);
        reach3(x,z) <-- reach3(x,y),edge3(y,z);
        relation edge4(i64,i64);
        relation reach4(i64,i64);
        reach4(x,y) <-- edge4(x,y);
        reach4(x,z) <-- reach4(x,y),edge4(y,z);
        relation edge5(i64,i64);
        relation reach5(i64,i64);
        reach5(x,y) <-- edge5(x,y);
        reach5(x,z) <-- reach5(x,y),edge5(y,z);
        relation edge6(i64,i64);
        relation reach6(i64,i64);
        reach6(x,y) <-- edge6(x,y);
        reach6(x,z) <-- reach6(x,y),edge6(y,z);
        relation edge7(i64,i64);
        relation reach7(i64,i64);
        reach7(x,y) <-- edge7(x,y);
        reach7(x,z) <-- reach7(x,y),edge7(y,z);
    }
    let edges = shape.edges();
    let expected: Vec<_> = shape
        .truth()
        .iter()
        .map(|row| match (&row[0], &row[1]) {
            (Value::Integer(a), Value::Integer(b)) => {
                (i64::try_from(a).unwrap(), i64::try_from(b).unwrap())
            }
            _ => unreachable!(),
        })
        .collect();
    for sample in 0..=samples {
        let t0 = Instant::now();
        let mut oracle = Oracle::default();
        let t1 = Instant::now();
        oracle.edge0.clone_from(&edges);
        oracle.edge1.clone_from(&edges);
        oracle.edge2.clone_from(&edges);
        oracle.edge3.clone_from(&edges);
        oracle.edge4.clone_from(&edges);
        oracle.edge5.clone_from(&edges);
        oracle.edge6.clone_from(&edges);
        oracle.edge7.clone_from(&edges);
        let t2 = Instant::now();
        oracle.run();
        let t3 = Instant::now();
        oracle.reach0.sort_unstable();
        oracle.reach1.sort_unstable();
        oracle.reach2.sort_unstable();
        oracle.reach3.sort_unstable();
        oracle.reach4.sort_unstable();
        oracle.reach5.sort_unstable();
        oracle.reach6.sort_unstable();
        oracle.reach7.sort_unstable();
        let t4 = Instant::now();
        assert_eq!(oracle.reach0, expected);
        assert_eq!(oracle.reach1, expected);
        assert_eq!(oracle.reach2, expected);
        assert_eq!(oracle.reach3, expected);
        assert_eq!(oracle.reach4, expected);
        assert_eq!(oracle.reach5, expected);
        assert_eq!(oracle.reach6, expected);
        assert_eq!(oracle.reach7, expected);
        std::hint::black_box(&oracle);
        if sample > 0 {
            println!(
                "{}\t{}\t{}\trust-ascent-oracle\t1\t{}\t{}\t{}\t{}\t{}\t{}\t{}\tNA\tNA\tNA",
                shape.components,
                shape.groups,
                shape.width,
                sample - 1,
                t1.duration_since(t0).as_nanos(),
                t2.duration_since(t1).as_nanos(),
                t3.duration_since(t2).as_nanos(),
                t4.duration_since(t3).as_nanos(),
                t4.duration_since(t0).as_nanos(),
                expected.len() * shape.components
            );
        }
    }
}
fn main() {
    let args: Vec<_> = std::env::args().skip(1).collect();
    assert_eq!(
        args.len(),
        5,
        "components groups width workers|oracle samples"
    );
    let shape = Shape {
        components: args[0].parse().unwrap(),
        groups: args[1].parse().unwrap(),
        width: args[2].parse().unwrap(),
    };
    let samples = args[4].parse().unwrap();
    if args[3] == "oracle" {
        match shape.components {
            1 => oracle_1(shape, samples),
            8 => oracle_8(shape, samples),
            _ => panic!("oracle supports 1 or 8 components"),
        }
    } else {
        run(shape, args[3].parse().unwrap(), samples);
    }
}
