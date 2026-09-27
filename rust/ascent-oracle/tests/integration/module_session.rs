// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Module embedding and retained program sessions.

use super::common::scheme_output;
use super::positive_closure::scheme_pairs;
use ascent::aggregators::sum;
use ascent::{ascent, ascent_run};

#[test]
#[allow(unused_variables)] // Ascent 0.8.0 emits an unused tuple binding for nullary relations.
fn nullary_gate_with_boolean_and_string_columns_matches_ascent() {
    ascent! {
        relation enabled();
        relation input(bool, String);
        relation selected(bool, String);
        selected(flag, name) <-- enabled(), input(flag, name);
    }
    for (enabled, input) in [
        (false, vec![]),
        (false, vec![(true, "alpha".to_owned())]),
        (
            true,
            vec![(true, "alpha".to_owned()), (false, "beta".to_owned())],
        ),
        (true, vec![(false, "".to_owned()), (false, "".to_owned())]),
    ] {
        let mut program = AscentProgram {
            enabled: if enabled { vec![()] } else { vec![] },
            input: input.clone(),
            ..AscentProgram::default()
        };
        program.run();
        let mut expected = program
            .selected
            .iter()
            .map(|(flag, name)| format!("{flag}\t{name}"))
            .collect::<Vec<_>>();
        expected.sort_unstable();
        let input_request = input
            .iter()
            .map(|(flag, name)| format!("({} {name:?})", if *flag { "#t" } else { "#f" }))
            .collect::<Vec<_>>()
            .join(" ");
        let request = format!(
            "({} ({input_request}))\n",
            if enabled { "#t" } else { "#f" }
        );
        let mut actual = scheme_output("typed-rows", &request)
            .lines()
            .map(str::to_owned)
            .collect::<Vec<_>>();
        assert_eq!(actual.pop().as_deref(), Some("END"));
        actual.sort_unstable();
        assert_eq!(actual, expected, "enabled={enabled}, input={input:?}");
    }
}

fn ascent_local_origin_rows(edges: &[(u32, u32)], origin: u32) -> Vec<String> {
    let result = ascent_run! {
        relation edge(u32, u32);
        relation reach(u32, u32);
        edge(x, y) <-- for &(x, y) in edges;
        reach(x, y) <-- edge(x, y), if *x == origin;
        reach(x, z) <-- reach(x, y), edge(y, z);
    };
    let mut rows: Vec<_> = result
        .reach
        .iter()
        .map(|(x, y)| format!("{x}\t{y}"))
        .collect();
    rows.sort_unstable();
    rows
}

#[test]
fn gerbil_module_and_lexical_origin_match_ascent_run() {
    let snapshots: &[(u32, &[(u32, u32)])] = &[
        (1, &[(1, 2), (2, 3), (3, 4), (2, 5)]),
        (2, &[(1, 2), (2, 3), (3, 4), (2, 5)]),
        (3, &[(1, 2), (2, 3), (3, 4), (4, 2)]),
        (9, &[(1, 2), (2, 3)]),
    ];
    for &(origin, edges) in snapshots {
        let source = edges
            .iter()
            .map(|(x, y)| format!("({x} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let request = format!("({origin} ({source}))\n");
        let output = scheme_output("module-rows", &request);
        let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
        assert_eq!(actual.pop().as_deref(), Some("END"));
        actual.sort_unstable();
        assert_eq!(actual, ascent_local_origin_rows(edges, origin));
    }
}

#[test]
fn rust_repeated_run_source_update_oracle() {
    ascent! {
        relation edge(u32, u32);
        relation reach(u32, u32);
        reach(x, y) <-- edge(x, y);
        reach(x, z) <-- reach(x, y), edge(y, z);
    }
    let mut program = AscentProgram {
        edge: vec![(1, 2)],
        ..AscentProgram::default()
    };
    program.run();
    let mut first = program.reach.clone();
    first.sort_unstable();
    assert_eq!(first, vec![(1, 2)]);
    assert_eq!(scheme_pairs(&program.edge, true), first);

    program.edge.push((2, 3));
    program.run();
    let mut second = program.reach.clone();
    second.sort_unstable();
    assert_eq!(second, vec![(1, 2), (1, 3), (2, 3)]);
    assert_eq!(scheme_pairs(&program.edge, true), second);

    program.run();
    let mut unchanged = program.reach.clone();
    unchanged.sort_unstable();
    assert_eq!(unchanged, second);

    program.edge.push((2, 3));
    program.run();
    let mut duplicate_source = program.reach.clone();
    duplicate_source.sort_unstable();
    assert_eq!(duplicate_source, second);
    assert_eq!(scheme_pairs(&program.edge, true), duplicate_source);

    program.edge.push((3, 1));
    program.run();
    let mut cycle = program.reach.clone();
    cycle.sort_unstable();
    assert_eq!(cycle.len(), 9);
    assert_eq!(scheme_pairs(&program.edge, true), cycle);

    let mut fresh = AscentProgram {
        edge: program.edge.clone(),
        ..AscentProgram::default()
    };
    fresh.run();
    fresh.reach.sort_unstable();
    assert_eq!(cycle, fresh.reach);
}

#[test]
fn rust_repeated_run_after_negated_source_update() {
    ascent! {
        relation candidate(u32);
        relation blocked(u32);
        relation allowed(u32);
        allowed(x) <-- candidate(x), !blocked(x);
    }
    let mut program = AscentProgram {
        candidate: vec![(1,)],
        ..AscentProgram::default()
    };
    program.run();
    assert_eq!(program.allowed, vec![(1,)]);
    program.blocked.push((1,));
    program.run();
    assert_eq!(program.allowed, vec![(1,)]);
}

#[test]
fn rust_repeated_run_after_aggregate_source_update() {
    ascent! {
        relation number(i32);
        relation total(i32);
        total(value) <-- agg value = sum(x) in number(x);
    }
    let mut program = AscentProgram {
        number: vec![(1,)],
        ..AscentProgram::default()
    };
    program.run();
    assert_eq!(program.total, vec![(1,)]);
    program.number.push((2,));
    program.run();
    program.total.sort_unstable();
    assert_eq!(program.total, vec![(1,), (4,)]);

    let mut fresh = AscentProgram {
        number: vec![(1,), (2,)],
        ..AscentProgram::default()
    };
    fresh.run();
    assert_eq!(fresh.total, vec![(3,)]);
}

#[test]
fn mutually_recursive_scc_matches_ascent() {
    ascent! {
        relation edge(u32, u32);
        relation path0(u32, u32);
        relation path1(u32, u32);
        relation witness(u32);
        path1(x, z), witness(z) <-- path0(x, y), edge(y, z);
        path0(x, z) <-- path1(x, y), edge(y, z);
        path0(x, y) <-- edge(x, y);
    }
    let compare = |program: &AscentProgram, phase: &str| {
        let edges = &program.edge;
        let mut rust_rows = program
            .path0
            .iter()
            .map(|(x, y)| format!("path0\t{x}\t{y}"))
            .chain(
                program
                    .path1
                    .iter()
                    .map(|(x, y)| format!("path1\t{x}\t{y}")),
            )
            .chain(program.witness.iter().map(|(z,)| format!("witness\t{z}")))
            .collect::<Vec<_>>();
        rust_rows.sort();
        let request = format!(
            "({})\n",
            edges
                .iter()
                .map(|(x, y)| format!("({x} {y})"))
                .collect::<Vec<_>>()
                .join(" ")
        );
        let mut scheme_rows = scheme_output("mutual-rows", &request)
            .lines()
            .map(str::to_owned)
            .collect::<Vec<_>>();
        scheme_rows.sort();
        assert_eq!(scheme_rows, rust_rows, "{phase}: source {edges:?}");
        rust_rows
    };
    for edges in [
        vec![],
        vec![(1, 1)],
        vec![(1, 2), (2, 3), (3, 1)],
        vec![(3, 1), (2, 3), (1, 2)],
        vec![(1, 2), (1, 2), (2, 3), (3, 1)],
        vec![(1, 2), (1, 3), (2, 4), (3, 4), (4, 2)],
        vec![(1, 2), (2, 3)],
    ] {
        let mut program = AscentProgram {
            edge: edges.clone(),
            ..AscentProgram::default()
        };
        program.run();
        compare(&program, "fresh");
    }
    let mut retained = AscentProgram {
        edge: vec![(1, 2)],
        ..AscentProgram::default()
    };
    let updates: &[&[(u32, u32)]] = &[
        &[],
        &[(2, 3)],
        &[],
        &[(2, 3)],
        &[(3, 1)],
        &[(3, 4), (4, 2)],
        &[(1, 4)],
    ];
    let request = format!(
        "(session ((1 2)) {})\n",
        updates
            .iter()
            .map(|step| format!(
                "({})",
                step.iter()
                    .map(|(x, y)| format!("({x} {y})"))
                    .collect::<Vec<_>>()
                    .join(" ")
            ))
            .collect::<Vec<_>>()
            .join(" ")
    );
    let mut expected = Vec::new();
    retained.run();
    expected.push(compare(&retained, "retained phase 0"));
    for (phase, additions) in updates.iter().enumerate() {
        retained.edge.extend_from_slice(additions);
        retained.run();
        expected.push(compare(&retained, &format!("retained phase {}", phase + 1)));
    }
    let mut observed = Vec::<Vec<String>>::new();
    for line in scheme_output("mutual-rows", &request).lines() {
        if let Some(phase) = line.strip_prefix("phase\t") {
            assert_eq!(phase.parse::<usize>().unwrap(), observed.len());
            observed.push(Vec::new());
        } else {
            observed
                .last_mut()
                .expect("phase header before rows")
                .push(line.to_owned());
        }
    }
    for rows in &mut observed {
        rows.sort();
    }
    assert_eq!(observed, expected, "retained Scheme and Rust sessions");
}
