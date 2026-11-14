// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Complete Fibonacci and context-flow programs from the pinned Rust package.

use super::common::scheme_output;
use ascent::ascent;

fn rust_fibonacci_rows(numbers: &[isize]) -> Vec<String> {
    ascent! {
        relation number(isize);
        relation fib(isize, isize);
        fib(0, 1) <-- number(0);
        fib(1, 1) <-- number(1);
        fib(x, y + z) <-- number(x), if *x >= 2, fib(x - 1, y), fib(x - 2, z);
    }
    let mut program = AscentProgram {
        number: numbers.iter().map(|&value| (value,)).collect(),
        ..AscentProgram::default()
    };
    program.run();
    let mut rows: Vec<_> = program
        .fib
        .iter()
        .map(|(index, value)| format!("fib\t{index}\t{value}"))
        .collect();
    rows.sort_unstable();
    rows
}

#[test]
fn upstream_fibonacci_recursive_expressions_match_scheme() {
    for numbers in [
        vec![],
        vec![0],
        vec![0, 1],
        (0..6).collect(),
        (0..9).collect(),
    ] {
        let input = numbers
            .iter()
            .map(isize::to_string)
            .collect::<Vec<_>>()
            .join(" ");
        let output = scheme_output("upstream-example-rows", &format!("(fibonacci ({input}))\n"));
        let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
        assert_eq!(actual.pop().as_deref(), Some("END"));
        actual.sort_unstable();
        assert_eq!(actual, rust_fibonacci_rows(&numbers));
    }
}

#[derive(Clone, Eq, PartialEq, Hash)]
struct Instr(&'static str);
#[derive(Clone, Eq, PartialEq, Hash)]
struct Context(&'static str);
#[derive(Clone, Eq, PartialEq, Hash)]
enum Res {
    Ok,
    Err,
}

type Edge = (&'static str, &'static str, &'static str, &'static str);

fn rust_context_flow_rows(edges: &[Edge]) -> Vec<String> {
    ascent! {
        relation succ(Instr, Context, Instr, Context);
        relation flow(Instr, Context, Instr, Context);
        flow(i1, c1, i2, c2) <-- succ(i1, c1, i2, c2);
        flow(i1, c1, i3, c3) <-- flow(i1, c1, i2, c2), flow(i2, c2, i3, c3);
        relation res(Res);
        res(Res::Ok) <-- flow(Instr("w1"), Context("c1"), Instr("r2"), Context("c1"));
        res(Res::Err) <-- flow(Instr("w1"), Context("c1"), Instr("r2"), Context("c2"));
    }
    let mut program = AscentProgram {
        succ: edges
            .iter()
            .map(|&(from, from_context, to, to_context)| {
                (
                    Instr(from),
                    Context(from_context),
                    Instr(to),
                    Context(to_context),
                )
            })
            .collect(),
        ..AscentProgram::default()
    };
    program.run();
    let mut rows: Vec<_> = program
        .flow
        .iter()
        .map(|(from, from_context, to, to_context)| {
            format!(
                "flow\t{}\t{}\t{}\t{}",
                from.0, from_context.0, to.0, to_context.0
            )
        })
        .chain(program.res.iter().map(|(result,)| match result {
            Res::Ok => "res\tok".to_owned(),
            Res::Err => "res\terr".to_owned(),
        }))
        .collect();
    rows.sort_unstable();
    rows
}

#[test]
fn upstream_context_flow_four_column_join_matches_scheme() {
    let cases: Vec<Vec<Edge>> = vec![
        vec![],
        vec![
            ("w1", "c1", "w2", "c1"),
            ("w2", "c1", "r1", "c1"),
            ("r1", "c1", "r2", "c1"),
            ("w1", "c2", "w2", "c2"),
            ("w2", "c2", "r1", "c2"),
            ("r1", "c2", "r2", "c2"),
        ],
        vec![("w1", "c1", "w2", "c1"), ("w2", "c1", "r2", "c2")],
        vec![
            ("w1", "c1", "r2", "c1"),
            ("w1", "c1", "r2", "c2"),
            ("w1", "c1", "r2", "c2"),
        ],
    ];
    for edges in &cases {
        let rendered = edges
            .iter()
            .map(|(from, from_context, to, to_context)| {
                format!("(\"{from}\" \"{from_context}\" \"{to}\" \"{to_context}\")")
            })
            .collect::<Vec<_>>()
            .join(" ");
        let output = scheme_output(
            "upstream-example-rows",
            &format!("(context-flow ({rendered}))\n"),
        );
        let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
        assert_eq!(actual.pop().as_deref(), Some("END"));
        actual.sort_unstable();
        assert_eq!(actual, rust_context_flow_rows(edges));
    }
}
