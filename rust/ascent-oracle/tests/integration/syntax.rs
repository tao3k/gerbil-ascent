// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Rust Ascent 0.8.0 syntax forms compared with Scheme macro lowering.

use super::common::scheme_output;
use ascent::ascent;

mod reusable {
    ascent::ascent_source! { closure_source:
        relation edge(u32, u32);
        relation closure(u32, u32);
        closure(x, y) <-- edge(x, y);
        closure(x, z) <-- closure(x, y), edge(y, z);
    }
}

fn rust_closure_rows(edges: &[(u32, u32)]) -> Vec<String> {
    ascent! {
        include_source!(reusable::closure_source);
    }
    let mut program = AscentProgram {
        edge: edges.to_vec(),
        ..AscentProgram::default()
    };
    program.run();
    program
        .closure
        .iter()
        .map(|(from, to)| format!("closure\t{from}\t{to}"))
        .collect()
}

fn rust_macro_rows() -> Vec<String> {
    ascent! {
        relation macro_seed(u32);
        macro emit_seed($value: expr) {
            macro_seed($value)
        }
        emit_seed!(9);
    }
    let mut program = AscentProgram::default();
    program.run();
    program
        .macro_seed
        .iter()
        .map(|(value,)| format!("macro-seed\t{value}"))
        .collect()
}

fn rust_rows(edges: &[(u32, u32)]) -> Vec<String> {
    ascent! {
        relation edge(u32, u32);
        relation seed(u32);
        relation marker(u32);
        relation selected(u32);
        relation successor(u32);
        relation optional(Option<u32>);
        relation unwrapped(u32);
        relation unwrapped_pattern(u32);
        relation let_pair(u32, u32);
        relation for_pair(u32, u32);

        seed(7), marker(8);
        selected(x) <-- (seed(x) | edge(x, _));
        successor(*x + 1) <-- edge(x, _);
        unwrapped(x) <-- optional(value), if let Some(x) = *value;
        unwrapped_pattern(*x) <-- optional(?Some(x));
        let_pair(x, y) <-- edge(a, b), let (x, y) = (*a, *b + 1);
        for_pair(x, y) <-- edge(a, b), for (x, y) in [(*a, *b), (*b, *a)];
    }
    let mut program = AscentProgram {
        edge: edges.to_vec(),
        optional: vec![(Some(4),), (None,)],
        ..AscentProgram::default()
    };
    program.run();
    let mut rows = Vec::new();
    rows.extend(program.seed.iter().map(|(value,)| format!("seed\t{value}")));
    rows.extend(
        program
            .marker
            .iter()
            .map(|(value,)| format!("marker\t{value}")),
    );
    rows.extend(
        program
            .selected
            .iter()
            .map(|(value,)| format!("selected\t{value}")),
    );
    rows.extend(
        program
            .successor
            .iter()
            .map(|(value,)| format!("successor\t{value}")),
    );
    rows.extend(
        program
            .unwrapped
            .iter()
            .map(|(value,)| format!("unwrapped\t{value}")),
    );
    rows.extend(
        program
            .unwrapped_pattern
            .iter()
            .map(|(value,)| format!("unwrapped-pattern\t{value}")),
    );
    rows.extend(
        program
            .let_pair
            .iter()
            .map(|(from, to)| format!("let-pair\t{from}\t{to}")),
    );
    rows.extend(
        program
            .for_pair
            .iter()
            .map(|(from, to)| format!("for-pair\t{from}\t{to}")),
    );
    rows.extend(rust_closure_rows(edges));
    rows.extend(rust_macro_rows());
    rows.sort_unstable();
    rows
}

#[test]
fn facts_disjunction_and_head_expression_match_scheme() {
    for edges in [
        &[][..],
        &[(1, 2), (2, 3), (1, 4)][..],
        &[(1, 2), (1, 2), (2, 3)][..],
    ] {
        let request = format!(
            "({})\n",
            edges
                .iter()
                .map(|(from, to)| format!("({from} {to})"))
                .collect::<Vec<_>>()
                .join(" ")
        );
        let output = scheme_output("syntax-rows", &request);
        let mut scheme: Vec<_> = output.lines().map(str::to_owned).collect();
        assert_eq!(scheme.pop().as_deref(), Some("END"));
        scheme.sort_unstable();
        assert_eq!(scheme, rust_rows(edges), "edges: {edges:?}");
    }
}
