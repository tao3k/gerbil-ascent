// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Rust Ascent 0.8.0 syntax forms compared with Scheme macro lowering.

use super::common::scheme_output;
use ascent::ascent;

#[test]
fn generated_static_scc_summary_matches_scheme_rule_dependencies() {
    ascent! {
        relation seed(u32);
        relation copied(u32);
        relation left(u32);
        relation right(u32);
        relation final_rel(u32);
        copied(x) <-- seed(x);
        left(x) <-- right(x);
        right(x) <-- left(x);
        final_rel(x) <-- left(x);
    }
    let mut rust_signatures = Vec::new();
    let mut looping = false;
    for line in AscentProgram::summary().lines() {
        if line.starts_with("scc ") {
            looping = line.contains("is_looping: true");
        } else if let Some(names) = line.trim().strip_prefix("dynamic relations: ") {
            let mut names = names.split(", ").map(str::to_owned).collect::<Vec<_>>();
            names.sort_unstable();
            rust_signatures.push(format!("{looping}:{}", names.join(",")));
        }
    }
    let mut scheme_signatures = scheme_output("scc-summary", "")
        .lines()
        .map(|line| {
            let mut fields = line.split('\t');
            assert_eq!(fields.next(), Some("SCC"));
            let looping = fields.next().expect("SCC loop marker");
            let mut names = fields.map(str::to_owned).collect::<Vec<_>>();
            names.sort_unstable();
            format!("{looping}:{}", names.join(","))
        })
        .collect::<Vec<_>>();
    rust_signatures.sort_unstable();
    scheme_signatures.sort_unstable();
    assert_eq!(rust_signatures, scheme_signatures);
}

#[test]
fn measured_rule_program_keeps_rust_scheme_rows_and_exposes_timing() {
    for seed in [vec![], vec![1], vec![1, 2, 2]] {
        ascent! {
            #![measure_rule_times]
            relation seed(u32);
            relation copied(u32);
            copied(x) <-- seed(x);
        }
        let mut program = AscentProgram {
            seed: seed.iter().copied().map(|value| (value,)).collect(),
            ..AscentProgram::default()
        };
        program.run();
        let rust_rule_time = program.rule0_0_duration;
        let rust_summary = program.scc_times_summary();
        assert!(rust_summary.contains("scc 0: iterations: 1, time:"));
        assert_eq!(rust_summary.matches("scc 0: iterations:").count(), 1);
        assert_eq!(rust_summary.matches("  sum of rule times:").count(), 1);
        assert_eq!(rust_summary.matches("  rule copied <--").count(), 1);
        assert!(rust_summary.contains("update_indices time:"));
        assert!(rust_summary.contains(&format!("    time: {rust_rule_time:?}")));
        let mut rust_sizes = program
            .relation_sizes_summary()
            .lines()
            .map(str::to_owned)
            .collect::<Vec<_>>();

        let request = format!(
            "({})\n",
            seed.iter()
                .map(|value| format!("({value})"))
                .collect::<Vec<_>>()
                .join(" ")
        );
        let output = scheme_output("timed-rows", &request);
        let mut actual = output.lines().map(str::to_owned).collect::<Vec<_>>();
        assert_eq!(actual.pop().as_deref(), Some("END"));
        assert_eq!(actual.pop().as_deref(), Some("TIMING\t1"));
        let mut scheme_sizes = Vec::new();
        actual.retain(|line| {
            if let Some(size) = line.strip_prefix("SIZE\t") {
                let (name, count) = size.split_once('\t').expect("relation size row");
                scheme_sizes.push(format!("{name} size: {count}"));
                false
            } else {
                true
            }
        });
        scheme_sizes.sort_unstable();
        rust_sizes.sort_unstable();
        assert_eq!(scheme_sizes, rust_sizes);
        actual.sort_unstable();
        let mut expected = program
            .copied
            .iter()
            .map(|(value,)| format!("copied\t{value}"))
            .collect::<Vec<_>>();
        expected.sort_unstable();
        assert_eq!(actual, expected);
    }
}

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
        emit_seed!(10);
        macro emit_named_seed($destination: ident, $value: expr) {
            $destination($value)
        }
        emit_named_seed!(macro_seed, 11);
    }
    let mut program = AscentProgram::default();
    program.run();
    program
        .macro_seed
        .iter()
        .map(|(value,)| format!("macro-seed\t{value}"))
        .collect()
}

fn rust_alternate_spelling_rows(edges: &[(u32, u32)]) -> Vec<String> {
    ascent! {
        relation edge(u32, u32);
        relation alternate_a(u32);
        relation alternate_b(u32);
        relation alternate_selected(u32);
        relation alternate_count(usize);

        {alternate_a(7), alternate_b(11)};
        alternate_selected(x) <-- (edge(x, _) || alternate_a(x));
        alternate_count(total) <--
            agg total = (ascent::aggregators::count)() in alternate_selected(_);
    }
    let mut program = AscentProgram {
        edge: edges.to_vec(),
        ..AscentProgram::default()
    };
    program.run();
    let mut rows = Vec::new();
    rows.extend(
        program
            .alternate_a
            .iter()
            .map(|(value,)| format!("alternate-a\t{value}")),
    );
    rows.extend(
        program
            .alternate_b
            .iter()
            .map(|(value,)| format!("alternate-b\t{value}")),
    );
    rows.extend(
        program
            .alternate_selected
            .iter()
            .map(|(value,)| format!("alternate-selected\t{value}")),
    );
    rows.extend(
        program
            .alternate_count
            .iter()
            .map(|(total,)| format!("alternate-count\t{total}")),
    );
    rows
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
        relation consecutive(u32);
        relation anchored_target(u32);
        relation missing_successor(u32);
        relation copied(u32, u32);

        macro emit_copy($destination: ident) {
            $destination(x, y)
        }
        emit_copy!(copied) <-- edge(x, y);

        seed(7), marker(8);
        selected(x) <-- (seed(x) | edge(x, _));
        successor(*x + 1) <-- edge(x, _);
        unwrapped(x) <-- optional(value), if let Some(x) = *value;
        unwrapped_pattern(*x) <-- optional(?Some(x));
        let_pair(x, y) <-- edge(a, b), let (x, y) = (*a, *b + 1);
        for_pair(x, y) <-- edge(a, b), for (x, y) in [(*a, *b), (*b, *a)];
        consecutive(x) <-- edge(x, *x + 1);
        anchored_target(y) <-- seed(x), edge(*x + 1, y);
        missing_successor(x) <-- seed(x), !edge(x, *x + 1);
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
    rows.extend(
        program
            .consecutive
            .iter()
            .map(|(value,)| format!("consecutive\t{value}")),
    );
    rows.extend(
        program
            .anchored_target
            .iter()
            .map(|(value,)| format!("anchored-target\t{value}")),
    );
    rows.extend(
        program
            .copied
            .iter()
            .map(|(from, to)| format!("copied\t{from}\t{to}")),
    );
    rows.extend(
        program
            .missing_successor
            .iter()
            .map(|(value,)| format!("missing-successor\t{value}")),
    );
    rows.extend(rust_closure_rows(edges));
    rows.extend(rust_macro_rows());
    rows.extend(rust_alternate_spelling_rows(edges));
    rows.sort_unstable();
    rows
}

#[test]
fn syntax_forms_and_body_expressions_match_scheme() {
    for edges in [
        &[][..],
        &[(1, 2), (2, 3), (1, 4)][..],
        &[(1, 2), (1, 2), (2, 3)][..],
        &[(1, 2), (2, 4), (8, 9)][..],
        &[(7, 8), (8, 9)][..],
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
