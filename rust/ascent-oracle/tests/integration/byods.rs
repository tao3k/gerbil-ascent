// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! BYODS equivalence and transitive storage providers.

use super::common::scheme_output;
use ascent::ascent;
use ascent_byods_rels::{eqrel, trrel, trrel_uf};
use std::collections::BTreeSet;

type BinaryRows = Vec<(u32, u32)>;
type TernaryRows = Vec<(u32, u32, u32)>;
type ByodsSnapshot = (BinaryRows, TernaryRows);

fn four_node_edges() -> [(u32, u32); 8] {
    [
        (0, 0),
        (0, 1),
        (0, 2),
        (1, 2),
        (2, 1),
        (2, 3),
        (3, 0),
        (3, 3),
    ]
}

fn eight_node_edges() -> [(u32, u32); 12] {
    [
        (0, 1),
        (1, 2),
        (2, 3),
        (3, 4),
        (4, 5),
        (5, 6),
        (6, 7),
        (7, 0),
        (0, 4),
        (2, 6),
        (4, 0),
        (6, 2),
    ]
}

fn eight_node_subset(mask: u16) -> BinaryRows {
    eight_node_edges()
        .into_iter()
        .enumerate()
        .filter_map(|(bit, edge)| (mask & (1 << bit) != 0).then_some(edge))
        .collect()
}

fn closure_reference(edges: &[(u32, u32)], symmetric: bool, strict_trrel: bool) -> Vec<String> {
    let nodes: BTreeSet<_> = edges.iter().flat_map(|&(from, to)| [from, to]).collect();
    let mut expected = Vec::new();
    for &from in &nodes {
        let mut reached = BTreeSet::new();
        let mut pending = vec![from];
        while let Some(node) = pending.pop() {
            if reached.insert(node) {
                pending.extend(edges.iter().filter_map(|&(left, right)| {
                    if left == node { Some(right) } else { None }
                }));
                if symmetric {
                    pending.extend(edges.iter().filter_map(|&(left, right)| {
                        if right == node { Some(left) } else { None }
                    }));
                }
            }
        }
        for to in reached {
            if !strict_trrel || from != to || edges.contains(&(from, from)) {
                expected.push(format!("binary-output\t{from}\t{to}"));
            }
        }
    }
    expected.sort_unstable();
    expected
}

#[test]
fn four_node_byods_subsets_match_independent_closure() {
    let possible = four_node_edges();
    for mask in 0..(1u16 << possible.len()) {
        let edges: Vec<_> = possible
            .iter()
            .enumerate()
            .filter_map(|(bit, edge)| (mask & (1 << bit) != 0).then_some(*edge))
            .collect();
        assert_eq!(
            ascent_eqrel_rows(&edges, &[]),
            closure_reference(&edges, true, false),
            "eqrel mask={mask}"
        );
        assert_eq!(
            ascent_trrel_rows(&edges, &[]),
            closure_reference(&edges, false, true),
            "trrel mask={mask}"
        );
        assert_eq!(
            ascent_trrel_uf_rows(&edges, &[]),
            closure_reference(&edges, false, false),
            "trrel_uf mask={mask}"
        );
    }
}

#[test]
fn eight_node_byods_subsets_match_model_and_selected_scheme_snapshots() {
    let masks = (0..256u32)
        .map(|sample| ((sample * 263) & 0x0fff) as u16)
        .chain([0x0001, 0x0555, 0x0f0f, 0x0fff]);
    for mask in masks {
        let edges = eight_node_subset(mask);
        let expected_eq = closure_reference(&edges, true, false);
        let expected_tr = closure_reference(&edges, false, true);
        let expected_uf = closure_reference(&edges, false, false);
        assert_eq!(
            ascent_eqrel_rows(&edges, &[]),
            expected_eq,
            "eqrel mask={mask}"
        );
        assert_eq!(
            ascent_trrel_rows(&edges, &[]),
            expected_tr,
            "trrel mask={mask}"
        );
        assert_eq!(
            ascent_trrel_uf_rows(&edges, &[]),
            expected_uf,
            "trrel_uf mask={mask}"
        );

        if [0, 1, 0x0555, 0x0f0f, 0x0fff].contains(&mask) {
            let rows = edges
                .iter()
                .map(|(from, to)| format!("({from} {to})"))
                .collect::<Vec<_>>()
                .join(" ");
            let request = format!("(({rows}) ())\n");
            for (recipe, expected) in [
                ("eqrel-rows", &expected_eq),
                ("trrel-rows", &expected_tr),
                ("trrel-uf-rows", &expected_uf),
            ] {
                let output = scheme_output(recipe, &request);
                let mut actual = output.lines().map(str::to_owned).collect::<Vec<_>>();
                assert_eq!(actual.pop().as_deref(), Some("END"));
                actual.sort_unstable();
                assert_eq!(&actual, expected, "{recipe} mask={mask}");
            }
        }
    }
}

fn ascent_eqrel_rows(binary: &[(u32, u32)], grouped: &[(u32, u32, u32)]) -> Vec<String> {
    ascent! {
        relation binary_seed(u32, u32);
        relation grouped_seed(u32, u32, u32);
        #[ds(eqrel)]
        relation binary_eq(u32, u32);
        #[ds(eqrel)]
        relation grouped_eq(u32, u32, u32);
        relation binary_output(u32, u32);
        relation grouped_output(u32, u32, u32);
        binary_eq(x, y) <-- binary_seed(x, y);
        grouped_eq(g, x, y) <-- grouped_seed(g, x, y);
        binary_output(x, y) <-- binary_eq(x, y);
        grouped_output(g, x, y) <-- grouped_eq(g, x, y);
    }
    let mut program = AscentProgram {
        binary_seed: binary.to_vec(),
        grouped_seed: grouped.to_vec(),
        ..AscentProgram::default()
    };
    program.run();
    let mut rows: Vec<_> = program
        .binary_output
        .iter()
        .map(|(x, y)| format!("binary-output\t{x}\t{y}"))
        .chain(
            program
                .grouped_output
                .iter()
                .map(|(g, x, y)| format!("grouped-output\t{g}\t{x}\t{y}")),
        )
        .collect();
    rows.sort_unstable();
    rows
}

#[test]
fn binary_and_grouped_eqrel_match_ascent_byods() {
    let snapshots: &[ByodsSnapshot] = &[
        (vec![], vec![]),
        (vec![(1, 2)], vec![(0, 3, 4)]),
        (vec![(1, 2), (2, 3)], vec![(0, 1, 2), (1, 2, 3)]),
        (
            vec![(1, 2), (3, 4), (2, 3), (1, 2)],
            vec![(0, 1, 2), (0, 2, 3), (1, 4, 5)],
        ),
        (
            vec![(3, 4), (1, 2), (4, 4), (2, 3), (4, 1)],
            vec![(0, 3, 4), (1, 3, 4), (0, 1, 2), (0, 2, 3)],
        ),
        (
            vec![(9, 9), (7, 8), (8, 7), (7, 7)],
            vec![(0, 9, 9), (1, 7, 8), (1, 8, 7), (1, 7, 7)],
        ),
        ((0..20).map(|node| (node, node + 1)).collect(), vec![]),
    ];
    for (binary, grouped) in snapshots {
        let binary_request = binary
            .iter()
            .map(|(x, y)| format!("({x} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let grouped_request = grouped
            .iter()
            .map(|(g, x, y)| format!("({g} {x} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let request = format!("(({binary_request}) ({grouped_request}))\n");
        let output = scheme_output("eqrel-rows", &request);
        let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
        assert_eq!(actual.pop().as_deref(), Some("END"));
        actual.sort_unstable();
        assert_eq!(actual, ascent_eqrel_rows(binary, grouped));
    }
}

fn ascent_trrel_rows(binary: &[(u32, u32)], grouped: &[(u32, u32, u32)]) -> Vec<String> {
    ascent! {
        relation binary_seed(u32, u32);
        relation grouped_seed(u32, u32, u32);
        #[ds(trrel)]
        relation binary_tr(u32, u32);
        #[ds(trrel)]
        relation grouped_tr(u32, u32, u32);
        relation binary_output(u32, u32);
        relation grouped_output(u32, u32, u32);
        binary_tr(x, y) <-- binary_seed(x, y);
        grouped_tr(g, x, y) <-- grouped_seed(g, x, y);
        binary_output(x, y) <-- binary_tr(x, y);
        grouped_output(g, x, y) <-- grouped_tr(g, x, y);
    }
    let mut program = AscentProgram {
        binary_seed: binary.to_vec(),
        grouped_seed: grouped.to_vec(),
        ..AscentProgram::default()
    };
    program.run();
    let mut rows: Vec<_> = program
        .binary_output
        .iter()
        .map(|(x, y)| format!("binary-output\t{x}\t{y}"))
        .chain(
            program
                .grouped_output
                .iter()
                .map(|(g, x, y)| format!("grouped-output\t{g}\t{x}\t{y}")),
        )
        .collect();
    rows.sort_unstable();
    rows
}

#[test]
fn binary_and_grouped_trrel_match_ascent_byods() {
    let snapshots: &[ByodsSnapshot] = &[
        (vec![], vec![]),
        (vec![(1, 1)], vec![(0, 2, 2)]),
        (vec![(1, 2)], vec![(0, 3, 4)]),
        (vec![(1, 2), (2, 3)], vec![(0, 1, 2), (1, 2, 3)]),
        (vec![(1, 2), (2, 3), (3, 1)], vec![(0, 1, 2), (0, 2, 1)]),
        (vec![(1, 2), (3, 4), (2, 3)], vec![(0, 1, 2), (1, 2, 3)]),
        ((0..20).map(|node| (node, node + 1)).collect(), vec![]),
    ];
    for (binary, grouped) in snapshots {
        let binary_request = binary
            .iter()
            .map(|(x, y)| format!("({x} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let grouped_request = grouped
            .iter()
            .map(|(g, x, y)| format!("({g} {x} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let request = format!("(({binary_request}) ({grouped_request}))\n");
        let output = scheme_output("trrel-rows", &request);
        let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
        assert_eq!(actual.pop().as_deref(), Some("END"));
        actual.sort_unstable();
        assert_eq!(actual, ascent_trrel_rows(binary, grouped));
    }
}

fn ascent_trrel_uf_rows(binary: &[(u32, u32)], grouped: &[(u32, u32, u32)]) -> Vec<String> {
    ascent! {
        relation binary_seed(u32, u32);
        relation grouped_seed(u32, u32, u32);
        #[ds(trrel_uf)]
        relation binary_tr(u32, u32);
        #[ds(trrel_uf)]
        relation grouped_tr(u32, u32, u32);
        relation binary_output(u32, u32);
        relation grouped_output(u32, u32, u32);
        binary_tr(x, y) <-- binary_seed(x, y);
        grouped_tr(g, x, y) <-- grouped_seed(g, x, y);
        binary_output(x, y) <-- binary_tr(x, y);
        grouped_output(g, x, y) <-- grouped_tr(g, x, y);
    }
    let mut program = AscentProgram {
        binary_seed: binary.to_vec(),
        grouped_seed: grouped.to_vec(),
        ..AscentProgram::default()
    };
    program.run();
    let mut rows: Vec<_> = program
        .binary_output
        .iter()
        .map(|(x, y)| format!("binary-output\t{x}\t{y}"))
        .chain(
            program
                .grouped_output
                .iter()
                .map(|(g, x, y)| format!("grouped-output\t{g}\t{x}\t{y}")),
        )
        .collect();
    rows.sort_unstable();
    rows
}

#[test]
fn binary_and_grouped_trrel_uf_match_ascent_byods() {
    let snapshots: &[ByodsSnapshot] = &[
        (vec![], vec![]),
        (vec![(1, 1)], vec![(0, 2, 2)]),
        (vec![(1, 2)], vec![(0, 3, 4)]),
        (vec![(1, 2), (2, 3)], vec![(0, 1, 2), (1, 2, 3)]),
        (vec![(1, 2), (2, 3), (3, 1)], vec![(0, 1, 2), (0, 2, 1)]),
        (vec![(1, 2), (3, 4), (2, 3)], vec![(0, 1, 2), (1, 2, 3)]),
        ((0..20).map(|node| (node, node + 1)).collect(), vec![]),
    ];
    for (binary, grouped) in snapshots {
        let binary_request = binary
            .iter()
            .map(|(x, y)| format!("({x} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let grouped_request = grouped
            .iter()
            .map(|(g, x, y)| format!("({g} {x} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let request = format!("(({binary_request}) ({grouped_request}))\n");
        let output = scheme_output("trrel-uf-rows", &request);
        let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
        assert_eq!(actual.pop().as_deref(), Some("END"));
        actual.sort_unstable();
        assert_eq!(actual, ascent_trrel_uf_rows(binary, grouped));
    }
}

#[test]
fn grouped_eqrel_split_producers_expose_upstream_merge_gap() {
    ascent! {
        relation first(String, u32, u32);
        relation second(String, u32, u32);
        relation wanted(String, u32);
        #[ds(eqrel)]
        relation eq(String, u32, u32);
        relation matched(String, u32, u32);
        eq(g, x, y) <-- first(g, x, y);
        eq(g, x, y) <-- second(g, x, y);
        matched(g, x, y) <-- eq(g, x, y), wanted(g, y);
    }
    let first = vec![("alpha".to_owned(), 1, 2)];
    let second = vec![("alpha".to_owned(), 2, 3)];
    let wanted = vec![("alpha".to_owned(), 3)];
    let mut split = AscentProgram {
        first: first.clone(),
        second: second.clone(),
        wanted: wanted.clone(),
        ..AscentProgram::default()
    };
    split.run();
    let mut combined = AscentProgram {
        first: first.into_iter().chain(second).collect(),
        wanted,
        ..AscentProgram::default()
    };
    combined.run();
    let target = ("alpha".to_owned(), 1, 3);
    assert!(combined.matched.contains(&target));
    assert!(!split.matched.contains(&target));

    let output = scheme_output(
        "byods-query-rows",
        "(((\"alpha\" 1 2)) ((\"alpha\" 3)) ((\"alpha\" 2 3)))\n",
    );
    assert!(output.lines().any(|line| line == "eq-match\talpha\t1\t3"));
}

#[test]
fn grouped_byods_join_with_string_keys_matches_ascent() {
    ascent! {
        relation seed(String, u32, u32);
        relation seed_extra(String, u32, u32);
        relation wanted(String, u32);
        #[ds(eqrel)]
        relation eq(String, u32, u32);
        #[ds(trrel)]
        relation tr(String, u32, u32);
        #[ds(trrel_uf)]
        relation uf(String, u32, u32);
        relation eq_match(String, u32, u32);
        relation tr_match(String, u32, u32);
        relation uf_match(String, u32, u32);
        eq(g, x, y) <-- seed(g, x, y);
        tr(g, x, y) <-- seed(g, x, y);
        uf(g, x, y) <-- seed(g, x, y);
        eq(g, x, y) <-- seed_extra(g, x, y);
        tr(g, x, y) <-- seed_extra(g, x, y);
        uf(g, x, y) <-- seed_extra(g, x, y);
        eq_match(g, x, y) <-- eq(g, x, y), wanted(g, y);
        tr_match(g, x, y) <-- tr(g, x, y), wanted(g, y);
        uf_match(g, x, y) <-- uf(g, x, y), wanted(g, y);
    }
    let eight_node_cases = [0u16, 1, 0x0555, 0x0fff].map(|mask| {
        let first = eight_node_subset(mask);
        let second = eight_node_edges()
            .into_iter()
            .filter(|edge| !first.contains(edge))
            .collect::<Vec<_>>();
        let grouped = |edges: Vec<(u32, u32)>| {
            edges
                .into_iter()
                .map(|(from, to)| ("alpha".to_owned(), from, to))
                .collect::<Vec<_>>()
        };
        (
            grouped(first),
            grouped(second),
            vec![("alpha".to_owned(), 0)],
        )
    });
    for (seed, seed_extra, wanted) in [
        (vec![], vec![], vec![]),
        (
            vec![
                ("alpha".to_owned(), 1, 2),
                ("alpha".to_owned(), 2, 3),
                ("beta".to_owned(), 1, 2),
            ],
            vec![],
            vec![("alpha".to_owned(), 3), ("beta".to_owned(), 2)],
        ),
        (
            vec![("alpha".to_owned(), 1, 2), ("alpha".to_owned(), 2, 1)],
            vec![],
            vec![("alpha".to_owned(), 1)],
        ),
        (
            vec![("alpha".to_owned(), 1, 2), ("beta".to_owned(), 1, 2)],
            vec![("alpha".to_owned(), 2, 3), ("beta".to_owned(), 2, 1)],
            vec![("alpha".to_owned(), 3), ("beta".to_owned(), 1)],
        ),
    ]
    .into_iter()
    .chain(eight_node_cases)
    {
        let mut program = AscentProgram {
            seed: seed.clone(),
            seed_extra: seed_extra.clone(),
            wanted: wanted.clone(),
            ..AscentProgram::default()
        };
        program.run();
        // In 0.8.0, eqrel's grouped read after two separate producer rules
        // can drop the merged alpha component. A single producer over the
        // same facts supplies the mathematical equivalence baseline instead.
        let mut combined = AscentProgram {
            seed: seed.iter().chain(seed_extra.iter()).cloned().collect(),
            wanted: wanted.clone(),
            ..AscentProgram::default()
        };
        combined.run();
        let mut expected = combined
            .eq_match
            .iter()
            .map(|(g, x, y)| format!("eq-match\t{g}\t{x}\t{y}"))
            .chain(
                program
                    .tr_match
                    .iter()
                    .map(|(g, x, y)| format!("tr-match\t{g}\t{x}\t{y}")),
            )
            .chain(
                program
                    .uf_match
                    .iter()
                    .map(|(g, x, y)| format!("uf-match\t{g}\t{x}\t{y}")),
            )
            .collect::<Vec<_>>();
        expected.sort_unstable();
        let seed_request = seed
            .iter()
            .map(|(g, x, y)| format!("({g:?} {x} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let wanted_request = wanted
            .iter()
            .map(|(g, y)| format!("({g:?} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let seed_extra_request = seed_extra
            .iter()
            .map(|(g, x, y)| format!("({g:?} {x} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let request = format!("(({seed_request}) ({wanted_request}) ({seed_extra_request}))\n");
        let mut actual = scheme_output("byods-query-rows", &request)
            .lines()
            .map(str::to_owned)
            .collect::<Vec<_>>();
        assert_eq!(actual.pop().as_deref(), Some("END"));
        actual.sort_unstable();
        assert_eq!(actual, expected, "seed {seed:?}, wanted {wanted:?}");
    }
}
