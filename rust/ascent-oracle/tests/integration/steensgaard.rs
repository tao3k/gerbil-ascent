// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
//! Complete B23 application rules, with a graph saturation oracle.
use super::common::scheme_output;
use ascent::ascent;
use ascent_byods_rels::eqrel;
use std::collections::BTreeSet;

#[derive(Default)]
struct Inputs {
    alloc: Vec<(u32, u32)>,
    assign: Vec<(u32, u32)>,
    load: Vec<(u32, u32, u32)>,
    store: Vec<(u32, u32, u32)>,
}

fn rust_eqrel(input: &Inputs) -> BTreeSet<(u32, u32)> {
    ascent! {
        relation alloc(u32, u32);
        relation assign(u32, u32);
        relation load(u32, u32, u32);
        relation store(u32, u32, u32);
        #[ds(eqrel)]
        relation vpt(u32, u32);
        relation output(u32, u32);
        vpt(x, y) <-- assign(x, y);
        vpt(x, y) <-- alloc(x, y);
        vpt(y, p) <-- store(x, f, y), load(p, q, f), vpt(x, q);
        output(x, y) <-- vpt(x, y);
    }
    let mut program = AscentProgram {
        alloc: input.alloc.clone(),
        assign: input.assign.clone(),
        load: input.load.clone(),
        store: input.store.clone(),
        ..AscentProgram::default()
    };
    program.run();
    program.output.into_iter().collect()
}

fn rust_explicit(input: &Inputs) -> BTreeSet<(u32, u32)> {
    ascent! {
        relation alloc(u32, u32);
        relation assign(u32, u32);
        relation load(u32, u32, u32);
        relation store(u32, u32, u32);
        relation vpt(u32, u32);
        vpt(y, x), vpt(x, x) <-- vpt(x, y);
        vpt(x, z) <-- vpt(x, y), vpt(y, z);
        vpt(x, y) <-- assign(x, y);
        vpt(x, y) <-- alloc(x, y);
        vpt(y, p) <-- store(x, f, y), load(p, q, f), vpt(x, q);
    }
    let mut program = AscentProgram {
        alloc: input.alloc.clone(),
        assign: input.assign.clone(),
        load: input.load.clone(),
        store: input.store.clone(),
        ..AscentProgram::default()
    };
    program.run();
    program.vpt.into_iter().collect()
}

// Undirected graph reachability after each effective load/store injection.
// It is independent of Ascent and the Scheme partition-saturation reference.
fn truth(input: &Inputs) -> BTreeSet<(u32, u32)> {
    let mut edges: BTreeSet<_> = input.alloc.iter().chain(&input.assign).copied().collect();
    loop {
        let nodes: BTreeSet<_> = edges.iter().flat_map(|&(a, b)| [a, b]).collect();
        let mut rows = BTreeSet::new();
        for start in nodes {
            let mut seen = BTreeSet::new();
            let mut todo = vec![start];
            while let Some(node) = todo.pop() {
                if seen.insert(node) {
                    todo.extend(edges.iter().filter_map(|&(a, b)| {
                        if a == node {
                            Some(b)
                        } else if b == node {
                            Some(a)
                        } else {
                            None
                        }
                    }));
                }
            }
            rows.extend(seen.into_iter().map(|end| (start, end)));
        }
        let mut changed = false;
        for &(x, f, y) in &input.store {
            for &(p, q, g) in &input.load {
                if f == g && rows.contains(&(x, q)) && !rows.contains(&(y, p)) {
                    changed |= edges.insert((y, p));
                }
            }
        }
        if !changed {
            return rows;
        }
    }
}

fn render(input: &Inputs) -> String {
    let binary = |rows: &Vec<(u32, u32)>| {
        rows.iter()
            .map(|(a, b)| format!("({a} {b})"))
            .collect::<Vec<_>>()
            .join(" ")
    };
    let ternary = |rows: &Vec<(u32, u32, u32)>| {
        rows.iter()
            .map(|(a, b, c)| format!("({a} {b} {c})"))
            .collect::<Vec<_>>()
            .join(" ")
    };
    format!(
        "(({}) ({}) ({}) ({}))",
        binary(&input.alloc),
        binary(&input.assign),
        ternary(&input.load),
        ternary(&input.store)
    )
}

#[test]
fn complete_steensgaard_rules_match_two_rust_arms_and_independent_truth() {
    let mut cases = vec![Inputs::default()];
    for mask in 0..32 {
        cases.push(Inputs {
            alloc: if mask & 1 != 0 {
                vec![(0, 1), (0, 1)]
            } else {
                vec![]
            },
            assign: if mask & 2 != 0 { vec![(1, 2)] } else { vec![] },
            load: vec![(3, 2, if mask & 4 != 0 { 9 } else { 8 }), (5, 3, 9)],
            store: if mask & 8 != 0 {
                vec![(0, 8, 4), (4, 9, 6)]
            } else {
                vec![(0, 8, 4)]
            },
        });
        if mask & 16 != 0 {
            cases.last_mut().unwrap().assign.push((0, 2));
        }
    }
    let request = format!(
        "({})\n",
        cases.iter().map(render).collect::<Vec<_>>().join(" ")
    );
    let output = scheme_output("steensgaard-rows", &request);
    let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
    assert_eq!(actual.pop().as_deref(), Some("END"));
    let mut expected = Vec::new();
    for (ordinal, input) in cases.iter().enumerate() {
        let rows = truth(input);
        assert_eq!(rust_explicit(input), rows, "explicit case={ordinal}");
        assert_eq!(rust_eqrel(input), rows, "eqrel case={ordinal}");
        expected.extend(
            rows.into_iter()
                .map(|(a, b)| format!("{ordinal}\t{a}\t{b}")),
        );
    }
    actual.sort_unstable();
    expected.sort_unstable();
    assert_eq!(actual, expected);
}
