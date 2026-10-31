// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! The full upstream `var_points_to` rule shape, including independent `_`s.

use super::common::scheme_output;
use ascent::ascent;

#[derive(Clone, Eq, PartialEq, Hash)]
struct Var(&'static str);
#[derive(Clone, Eq, PartialEq, Hash)]
struct Obj(&'static str);
#[derive(Clone, Eq, PartialEq, Hash)]
struct Field(&'static str);

type Pair = (&'static str, &'static str);
type Triple = (&'static str, &'static str, &'static str);

struct Sources {
    assign: Vec<Pair>,
    new: Vec<Pair>,
    ld: Vec<Triple>,
    st: Vec<Triple>,
}

fn rust_rows(source: &Sources) -> Vec<String> {
    ascent! {
        relation assign(Var, Var);
        relation new(Var, Obj);
        relation ld(Var, Var, Field);
        relation st(Var, Field, Var);
        relation alias(Var, Var);
        relation points_to(Var, Obj);

        alias(x, x) <-- assign(x, _);
        alias(x, x) <-- assign(_, x);
        alias(x, y) <-- assign(x, y);
        alias(x, y) <-- ld(x, a, f), alias(a, b), st(b, f, y);
        points_to(x, y) <-- new(x, y);
        points_to(x, y) <-- alias(x, z), points_to(z, y);
    }
    let mut program = AscentProgram {
        assign: source
            .assign
            .iter()
            .map(|&(from, to)| (Var(from), Var(to)))
            .collect(),
        new: source
            .new
            .iter()
            .map(|&(variable, object)| (Var(variable), Obj(object)))
            .collect(),
        ld: source
            .ld
            .iter()
            .map(|&(target, base, field)| (Var(target), Var(base), Field(field)))
            .collect(),
        st: source
            .st
            .iter()
            .map(|&(base, field, value)| (Var(base), Field(field), Var(value)))
            .collect(),
        ..AscentProgram::default()
    };
    program.run();
    let mut rows: Vec<_> = program
        .alias
        .iter()
        .map(|(from, to)| format!("alias\t{}\t{}", from.0, to.0))
        .chain(
            program
                .points_to
                .iter()
                .map(|(variable, object)| format!("points-to\t{}\t{}", variable.0, object.0)),
        )
        .collect();
    rows.sort_unstable();
    rows
}

fn scheme_request(source: &Sources) -> String {
    let pairs = |rows: &[Pair]| {
        rows.iter()
            .map(|(left, right)| format!("(\"{left}\" \"{right}\")"))
            .collect::<Vec<_>>()
            .join(" ")
    };
    let triples = |rows: &[Triple]| {
        rows.iter()
            .map(|(first, second, third)| format!("(\"{first}\" \"{second}\" \"{third}\")"))
            .collect::<Vec<_>>()
            .join(" ")
    };
    format!(
        "(({}) ({}) ({}) ({}))\n",
        pairs(&source.assign),
        pairs(&source.new),
        triples(&source.ld),
        triples(&source.st)
    )
}

#[test]
fn upstream_points_to_rule_shape_matches_scheme() {
    let cases = [
        Sources {
            assign: vec![],
            new: vec![],
            ld: vec![],
            st: vec![],
        },
        Sources {
            assign: vec![("v1", "v2")],
            new: vec![("v1", "h1"), ("v2", "h2"), ("v3", "h3")],
            ld: vec![("v4", "v1", "f")],
            st: vec![("v1", "f", "v3")],
        },
        Sources {
            assign: vec![("v1", "v2"), ("v2", "v3"), ("v1", "v2")],
            new: vec![("v3", "h3"), ("v4", "h4")],
            ld: vec![("v5", "v1", "f"), ("v6", "v2", "g")],
            st: vec![("v2", "f", "v4"), ("v3", "g", "v4")],
        },
    ];
    for source in &cases {
        let output = scheme_output("var-points-to-rows", &scheme_request(source));
        let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
        assert_eq!(actual.pop().as_deref(), Some("END"));
        actual.sort_unstable();
        assert_eq!(actual, rust_rows(source));
    }
}
