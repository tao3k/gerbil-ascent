// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Finite interaction of generators, guards, bindings, negation and aggregation.

use super::common::scheme_output;
use ascent::aggregators::{count, sum};
use ascent::ascent;
use std::collections::{BTreeMap, BTreeSet};

type Edge = (u32, u32);

fn max_target<'a>(input: impl Iterator<Item = (&'a u32,)>) -> impl Iterator<Item = u32> {
    input.map(|(target,)| *target).max().into_iter()
}

fn edges_for(mask: u32) -> Vec<Edge> {
    (0..3)
        .flat_map(|from| (0..3).map(move |to| (from, to)))
        .enumerate()
        .filter_map(|(bit, edge)| (mask & (1 << bit) != 0).then_some(edge))
        .collect()
}

fn rust_rows(edges: &[Edge], roots: &[u32]) -> BTreeSet<String> {
    ascent! {
        relation edge(u32, u32);
        relation blocked(u32, u32);
        relation root(u32);
        relation candidate(u32, u32, u32);
        relation allowed(u32, u32);
        relation reach(u32, u32);
        relation reach_count(u32, usize);
        relation reach_max(u32, u32);

        blocked(x, y) <-- edge(x, y), if (*x + *y) % 2 == 0;
        candidate(x, z, score) <-- edge(x, y),
            for z in [*y, (*y + 1) % 3], if *x != z,
            let score = *x + z;
        allowed(x, z) <-- candidate(x, z, _), !blocked(x, z);
        reach(x, z) <-- allowed(x, z);
        reach(x, z) <-- reach(x, y), allowed(y, z);
        reach_count(x, total) <-- root(x), agg total = count() in reach(x, _);
        reach_max(x, target) <-- root(x), agg target = max_target(z) in reach(x, z);
    }
    let mut program = AscentProgram {
        edge: edges.to_vec(),
        root: roots.iter().copied().map(|root| (root,)).collect(),
        ..AscentProgram::default()
    };
    program.run();
    program
        .blocked
        .iter()
        .map(|(x, y)| format!("blocked\t{x}\t{y}"))
        .chain(
            program
                .candidate
                .iter()
                .map(|(x, z, score)| format!("candidate\t{x}\t{z}\t{score}")),
        )
        .chain(
            program
                .allowed
                .iter()
                .map(|(x, z)| format!("allowed\t{x}\t{z}")),
        )
        .chain(
            program
                .reach
                .iter()
                .map(|(x, z)| format!("reach\t{x}\t{z}")),
        )
        .chain(
            program
                .reach_count
                .iter()
                .map(|(x, total)| format!("reach-count\t{x}\t{total}")),
        )
        .chain(
            program
                .reach_max
                .iter()
                .map(|(x, target)| format!("reach-max\t{x}\t{target}")),
        )
        .collect()
}

fn model_rows(edges: &[Edge]) -> BTreeSet<String> {
    let mut rows = BTreeSet::new();
    let blocked = edges
        .iter()
        .copied()
        .filter(|(x, y)| (x + y) % 2 == 0)
        .collect::<BTreeSet<_>>();
    for &(x, y) in &blocked {
        rows.insert(format!("blocked\t{x}\t{y}"));
    }
    let mut allowed = [[false; 3]; 3];
    for &(x, y) in edges {
        for z in [y, (y + 1) % 3] {
            if x != z {
                rows.insert(format!("candidate\t{x}\t{z}\t{}", x + z));
                if !blocked.contains(&(x, z)) {
                    allowed[x as usize][z as usize] = true;
                }
            }
        }
    }
    let mut reach = allowed;
    for (x, targets) in allowed.iter().enumerate() {
        for (z, present) in targets.iter().enumerate() {
            if *present {
                rows.insert(format!("allowed\t{x}\t{z}"));
            }
        }
    }
    // Floyd-Warshall is independent of the deductive engine's rule rounds.
    for via in 0..3 {
        for x in 0..3 {
            for z in 0..3 {
                reach[x][z] |= reach[x][via] && reach[via][z];
            }
        }
    }
    for (x, targets) in reach.iter().enumerate() {
        for (z, present) in targets.iter().enumerate() {
            if *present {
                rows.insert(format!("reach\t{x}\t{z}"));
            }
        }
        rows.insert(format!(
            "reach-count\t{x}\t{}",
            targets.iter().filter(|present| **present).count()
        ));
        if let Some(target) = targets.iter().rposition(|present| *present) {
            rows.insert(format!("reach-max\t{x}\t{target}"));
        }
    }
    rows
}

// The same finite input is used by POO Flow's negation/count model fixture.
// This pins the Rust 0.8.0 behavior before its Scheme receipt is shown to a model.
#[test]
fn model_study_negation_count_matches_finite_expectations() {
    fn rows(edges: &[Edge], blocked: &[Edge]) -> BTreeSet<String> {
        ascent! {
            relation edge(u32, u32);
            relation blocked(u32, u32);
            relation weight(u32, u32);
            relation root(u32);
            relation path(u32, u32);
            relation allowed(u32, u32);
            relation weighted(u32, u32);
            relation summary(u32, usize);

            path(x, y) <-- edge(x, y);
            path(x, z) <-- path(x, y), edge(y, z);
            allowed(x, y) <-- path(x, y), !blocked(x, y);
            weighted(x, v) <-- allowed(x, y), weight(y, w),
                if *w % 2 == 0, let v = *w + *w;
            summary(r, n) <-- root(r), agg n = count() in weighted(r, _);
        }
        let mut program = AscentProgram {
            edge: edges.to_vec(),
            blocked: blocked.to_vec(),
            weight: vec![(2, 4), (3, 6)],
            root: vec![(1,)],
            ..AscentProgram::default()
        };
        program.run();
        program
            .path
            .iter()
            .map(|(x, y)| format!("path\t{x}\t{y}"))
            .chain(
                program
                    .allowed
                    .iter()
                    .map(|(x, y)| format!("allowed\t{x}\t{y}")),
            )
            .chain(
                program
                    .weighted
                    .iter()
                    .map(|(x, v)| format!("weighted\t{x}\t{v}")),
            )
            .chain(
                program
                    .summary
                    .iter()
                    .map(|(r, n)| format!("summary\t{r}\t{n}")),
            )
            .collect()
    }

    let edges = [(1, 2), (2, 3)];
    let blocked: BTreeSet<String> = [
        "path\t1\t2",
        "path\t1\t3",
        "path\t2\t3",
        "allowed\t1\t2",
        "allowed\t2\t3",
        "weighted\t1\t8",
        "weighted\t2\t12",
        "summary\t1\t1",
    ]
    .into_iter()
    .map(str::to_owned)
    .collect();
    let unblocked: BTreeSet<String> = [
        "path\t1\t2",
        "path\t1\t3",
        "path\t2\t3",
        "allowed\t1\t2",
        "allowed\t1\t3",
        "allowed\t2\t3",
        "weighted\t1\t8",
        "weighted\t1\t12",
        "weighted\t2\t12",
        "summary\t1\t2",
    ]
    .into_iter()
    .map(str::to_owned)
    .collect();
    assert_eq!(rows(&edges, &[(1, 3)]), blocked);
    assert_eq!(rows(&edges, &[]), unblocked);
    assert_eq!(rows(&[(1, 2), (1, 2), (2, 3)], &[]), unblocked);
}

// Same four source states as the Scheme public Library contract. Rust is
// rebuilt for each state: retained deletion is not a Rust oracle guarantee.
#[test]
fn support_withdrawal_matches_public_library_contract() {
    let phases: &[(&[Edge], &[Edge], u32)] = &[
        (&[(0, 1), (1, 2), (0, 2)], &[(0, 1), (0, 2), (1, 2)], 20),
        (&[(0, 1), (1, 2)], &[(0, 1), (0, 2), (1, 2)], 20),
        (&[(0, 1)], &[(0, 1)], 8),
        (&[(0, 2)], &[(0, 2)], 12),
    ];
    for &(edges, expected_path, expected_total) in phases {
        ascent! {
            relation edge(u32, u32);
            relation blocked(u32, u32);
            relation weight(u32, u32);
            relation root(u32);
            relation path(u32, u32);
            relation allowed(u32, u32);
            relation weighted(u32, u32);
            relation summary(u32, u32);

            path(x, y) <-- edge(x, y);
            path(x, z) <-- path(x, y), edge(y, z);
            allowed(x, y) <-- path(x, y), !blocked(x, y);
            weighted(x, v) <-- allowed(x, y), weight(y, w),
                if *w % 2 == 0, let v = *w + *w;
            summary(r, n) <-- root(r), agg n = sum(v) in weighted(r, v);
        }
        let mut program = AscentProgram {
            edge: edges.to_vec(),
            weight: vec![(0, 2), (1, 4), (2, 6)],
            root: vec![(0,)],
            ..AscentProgram::default()
        };
        program.run();
        let expected = expected_path.iter().copied().collect::<BTreeSet<_>>();
        assert_eq!(program.path.into_iter().collect::<BTreeSet<_>>(), expected);
        assert_eq!(
            program.allowed.into_iter().collect::<BTreeSet<_>>(),
            expected
        );
        let expected_weighted = expected_path
            .iter()
            .map(|&(from, to)| (from, 2 * [2, 4, 6][to as usize]))
            .collect::<BTreeSet<_>>();
        assert_eq!(
            program.weighted.into_iter().collect::<BTreeSet<_>>(),
            expected_weighted
        );
        assert_eq!(
            program.summary.into_iter().collect::<BTreeSet<_>>(),
            BTreeSet::from([(0, expected_total)])
        );
    }
    let scheme = scheme_output("support-study-reference", "");
    let expected = [
        "0\tcomplete\t((0 20))\tvalid\tvalid\ttask-shape\t()",
        "1\tcomplete\t((0 20))\tvalid\tvalid\ttask-shape\t()",
        "2\tcomplete\t((0 8))\tvalid\tvalid\ttask-shape\t()",
        "3\tcomplete\t((0 12))\tvalid\tvalid\ttask-shape\t()",
        "stale\tcomplete\t((0 20))\tinvalid\tinvalid\ttask-shape\t()",
        "END",
    ];
    assert_eq!(scheme.lines().collect::<Vec<_>>(), expected);
    // Native validity of a hypothetical fact does not satisfy this task.
    let outside = scheme_output("support-study-hypothetical", "");
    for (generation, (line, total)) in outside.lines().take(4).zip([20, 20, 20, 12]).enumerate() {
        assert_eq!(
            line,
            format!("{generation}\tcomplete\t((0 {total}))\tvalid\tvalid\toutside-task-shape\t()")
        );
    }
    assert_eq!(outside.lines().count(), 6);
    assert_eq!(outside.lines().last(), Some("END"));
}

// Frozen support states plus independent negation/guard/set-sum discriminators.
#[test]
fn support_discriminators_match_public_library_contract() {
    let edges: &[Edge] = &[(0, 1), (1, 2), (0, 2)];
    let cases: &[(&[Edge], &[Edge], &[Edge], u32)] = &[
        (edges, &[], &[(0, 2), (1, 4), (2, 6)], 20),
        (&[(0, 1), (1, 2)], &[], &[(0, 2), (1, 4), (2, 6)], 20),
        (&[(0, 1)], &[], &[(0, 2), (1, 4), (2, 6)], 8),
        (&[(0, 2)], &[], &[(0, 2), (1, 4), (2, 6)], 12),
        (edges, &[(0, 2)], &[(0, 2), (1, 4), (2, 6)], 8),
        (edges, &[], &[(0, 2), (1, 3), (2, 6)], 12),
        (edges, &[], &[(0, 2), (1, 4), (2, 4)], 8),
    ];
    let mut expected_lines = Vec::new();
    for (generation, &(edges, blocked, weights, total)) in cases.iter().enumerate() {
        ascent! {
            relation edge(u32, u32);
            relation blocked(u32, u32);
            relation weight(u32, u32);
            relation root(u32);
            relation path(u32, u32);
            relation allowed(u32, u32);
            relation weighted(u32, u32);
            relation summary(u32, u32);
            path(x, y) <-- edge(x, y);
            path(x, z) <-- path(x, y), edge(y, z);
            allowed(x, y) <-- path(x, y), !blocked(x, y);
            weighted(x, v) <-- allowed(x, y), weight(y, w),
                if *w % 2 == 0, let v = *w + *w;
            summary(r, n) <-- root(r), agg n = sum(v) in weighted(r, v);
        }
        let mut program = AscentProgram {
            edge: edges.to_vec(),
            blocked: blocked.to_vec(),
            weight: weights.to_vec(),
            root: vec![(0,)],
            ..AscentProgram::default()
        };
        program.run();
        let mut closure = [[false; 3]; 3];
        for &(x, y) in edges {
            closure[x as usize][y as usize] = true;
        }
        for via in 0..3 {
            for from in 0..3 {
                for to in 0..3 {
                    closure[from][to] |= closure[from][via] && closure[via][to];
                }
            }
        }
        let path = (0..3)
            .flat_map(|x| (0..3).map(move |y| (x, y)))
            .filter(|&(x, y)| closure[x as usize][y as usize])
            .collect::<BTreeSet<Edge>>();
        let allowed = path
            .iter()
            .copied()
            .filter(|edge| !blocked.contains(edge))
            .collect::<BTreeSet<_>>();
        let weighted = allowed
            .iter()
            .flat_map(|&(x, y)| {
                weights
                    .iter()
                    .filter(move |&&(node, value)| node == y && value % 2 == 0)
                    .map(move |&(_, value)| (x, 2 * value))
            })
            .collect::<BTreeSet<_>>();
        assert_eq!(program.path.into_iter().collect::<BTreeSet<_>>(), path);
        assert_eq!(
            program.allowed.into_iter().collect::<BTreeSet<_>>(),
            allowed
        );
        assert_eq!(
            program.weighted.into_iter().collect::<BTreeSet<_>>(),
            weighted
        );
        assert_eq!(
            weighted
                .iter()
                .filter(|&&(x, _)| x == 0)
                .map(|&(_, value)| value)
                .sum::<u32>(),
            total
        );
        assert_eq!(
            program.summary.into_iter().collect::<BTreeSet<_>>(),
            BTreeSet::from([(0, total)])
        );
        expected_lines.push(format!(
            "{generation}\tcomplete\t((0 {total}))\tvalid\tvalid\ttask-shape\t()"
        ));
        eprintln!("RUST-DISCRIMINATOR-PROGRESS {generation}");
    }
    expected_lines.extend([
        "stale\tcomplete\t((0 20))\tinvalid\tinvalid\ttask-shape\t()".into(),
        "END".into(),
    ]);
    assert_eq!(
        scheme_output("support-discriminator-reference", "")
            .lines()
            .map(str::to_owned)
            .collect::<Vec<_>>(),
        expected_lines
    );
}

#[test]
fn clause_composition_matches_rust_scheme_and_independent_model() {
    let mut cases = (0..512)
        .map(|mask| (mask, edges_for(mask)))
        .collect::<Vec<_>>();
    for (offset, mask) in [1, 3, 42, 73, 170, 255, 511].into_iter().enumerate() {
        let mut edges = edges_for(mask);
        edges.push(edges[0]);
        cases.push((512 + offset as u32, edges));
    }
    let request = format!(
        "({})\n",
        cases
            .iter()
            .map(|(case_id, edges)| {
                let edges = edges
                    .iter()
                    .map(|(x, y)| format!("({x} {y})"))
                    .collect::<Vec<_>>()
                    .join(" ");
                format!("({case_id} ({edges}))")
            })
            .collect::<Vec<_>>()
            .join(" ")
    );
    let output = scheme_output("clause-composition-rows", &request);
    let mut scheme = output.lines().map(str::to_owned).collect::<Vec<_>>();
    assert_eq!(scheme.pop().as_deref(), Some("END"));
    let scheme = scheme.into_iter().collect::<BTreeSet<_>>();
    let mut expected = BTreeSet::new();
    for (case_id, edges) in cases {
        let rust = rust_rows(&edges, &[0, 1, 2]);
        let model = model_rows(&edges);
        assert_eq!(rust, model, "Rust case={case_id}");
        expected.extend(rust.into_iter().map(|row| format!("{case_id}\t{row}")));
    }
    assert_eq!(scheme, expected);
}

fn scale_edges(size: u32) -> Vec<Edge> {
    (0..size)
        .map(|index| {
            let from = 4 * index;
            (from, if index % 2 == 0 { from } else { from + 1 })
        })
        .collect()
}

fn scale_model_rows(edges: &[Edge], roots: &[u32]) -> BTreeSet<String> {
    let mut rows = BTreeSet::new();
    let blocked = edges
        .iter()
        .copied()
        .filter(|(from, to)| (from + to) % 2 == 0)
        .collect::<BTreeSet<_>>();
    for &(from, to) in &blocked {
        rows.insert(format!("blocked\t{from}\t{to}"));
    }
    let mut allowed = BTreeMap::<u32, BTreeSet<u32>>::new();
    for &(from, to) in edges {
        for target in [to, (to + 1) % 3] {
            if from != target {
                rows.insert(format!("candidate\t{from}\t{target}\t{}", from + target));
                if !blocked.contains(&(from, target)) {
                    allowed.entry(from).or_default().insert(target);
                    rows.insert(format!("allowed\t{from}\t{target}"));
                }
            }
        }
    }
    for &root in roots {
        let mut visited = BTreeSet::new();
        let mut pending = allowed
            .get(&root)
            .into_iter()
            .flat_map(|targets| targets.iter().copied())
            .collect::<Vec<_>>();
        while let Some(target) = pending.pop() {
            if visited.insert(target) {
                rows.insert(format!("reach\t{root}\t{target}"));
                if let Some(next) = allowed.get(&target) {
                    pending.extend(next.iter().copied());
                }
            }
        }
        rows.insert(format!("reach-count\t{root}\t{}", visited.len()));
        if let Some(maximum) = visited.last() {
            rows.insert(format!("reach-max\t{root}\t{maximum}"));
        }
    }
    rows
}

fn compare_scale(size: u32) {
    let edges = scale_edges(size);
    let roots = (0..size).map(|index| 4 * index).collect::<Vec<_>>();
    let rust = rust_rows(&edges, &roots);
    let model = scale_model_rows(&edges, &roots);
    assert_eq!(rust, model, "Rust source rows={size}");
    let output = scheme_output("clause-scale-rows", &format!("{size}\n"));
    let mut scheme = output.lines().map(str::to_owned).collect::<Vec<_>>();
    assert_eq!(scheme.pop().as_deref(), Some("END"));
    assert_eq!(scheme.into_iter().collect::<BTreeSet<_>>(), model);
}

#[test]
fn composed_clauses_match_model_at_1000_source_rows() {
    compare_scale(1000);
}

#[test]
fn composed_clauses_match_model_at_10000_source_rows() {
    compare_scale(10000);
}
