// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Exhaustive small-graph differential for interacting Ascent features.

use super::common::{CoordinateMax, scheme_output};

use ascent::{aggregators::count, ascent};

type Edge = (u32, u32);
type Case = (Vec<Edge>, Vec<u32>);
const SCHEME_CORPUS_CHUNK_SIZE: usize = 256;

fn cases() -> Vec<Case> {
    let mut result = Vec::with_capacity(778);
    for mask in 0..(1u16 << 9) {
        let edges = (0..9)
            .filter(|bit| mask & (1 << bit) != 0)
            .map(|bit| (bit / 3, bit % 3))
            .collect();
        let blocked = (0..3).filter(|node| mask & (1 << node) != 0).collect();
        result.push((edges, blocked));
    }
    let cycle = vec![(0, 1), (1, 2), (2, 0)];
    for mask in 0..8 {
        let blocked = (0..3).filter(|node| mask & (1 << node) != 0).collect();
        result.push((cycle.clone(), blocked));
    }
    result.push((vec![(0, 1), (0, 1), (1, 2)], vec![2]));
    result.push((vec![(2, 2), (2, 2), (0, 1)], vec![0, 0]));
    let four_node_edges = [
        (0, 0),
        (0, 1),
        (0, 2),
        (1, 2),
        (2, 1),
        (2, 3),
        (3, 0),
        (3, 3),
    ];
    for mask in 0..256u16 {
        let edges = four_node_edges
            .iter()
            .enumerate()
            .filter_map(|(bit, edge)| (mask & (1 << bit) != 0).then_some(*edge))
            .collect();
        let blocked = (0..4u32)
            .filter(|node| mask & (1 << (node + 4)) != 0)
            .collect();
        result.push((edges, blocked));
    }
    result
}

fn rust_rows(edges: &[Edge], blocked: &[u32]) -> Vec<String> {
    ascent! {
        relation edge(u32, u32);
        relation block(u32);
        relation root(u32);
        relation path(u32, u32);
        relation witness(u32);
        relation safe(u32, u32);
        relation reach_count(u32, usize);
        relation selected(u32);
        lattice score(u32, CoordinateMax);

        path(x, y), witness(y) <-- edge(x, y);
        path(x, z) <-- path(x, y), edge(y, z);
        safe(x, y) <-- path(x, y), !block(y);
        reach_count(x, total) <-- root(x), agg total = count() in path(x, _);
        selected(x) <-- (witness(x) | root(x)), if *x % 2 == 0;
        score(to, CoordinateMax(*from, *to)) <-- edge(from, to);
        score(to, value.clone()) <-- score(from, ?value), edge(from, to);
    }
    let mut program = AscentProgram {
        edge: edges.to_vec(),
        block: blocked.iter().map(|node| (*node,)).collect(),
        root: vec![(0,), (1,), (2,), (3,)],
        ..AscentProgram::default()
    };
    program.run();
    let mut rows = Vec::new();
    rows.extend(
        program
            .path
            .iter()
            .map(|(from, to)| format!("path\t{from}\t{to}")),
    );
    rows.extend(
        program
            .witness
            .iter()
            .map(|(node,)| format!("witness\t{node}")),
    );
    rows.extend(
        program
            .safe
            .iter()
            .map(|(from, to)| format!("safe\t{from}\t{to}")),
    );
    rows.extend(
        program
            .reach_count
            .iter()
            .map(|(node, total)| format!("reach-count\t{node}\t{total}")),
    );
    rows.extend(
        program
            .selected
            .iter()
            .map(|(node,)| format!("selected\t{node}")),
    );
    rows.extend(
        program
            .score
            .iter()
            .map(|(node, CoordinateMax(first, second))| {
                format!("score\t{node}\t{first}\t{second}")
            }),
    );
    rows
}

fn render_snapshot(edges: &[Edge], blocked: &[u32]) -> String {
    let edge_rows = edges
        .iter()
        .map(|(from, to)| format!("({from} {to})"))
        .collect::<Vec<_>>()
        .join(" ");
    let blocked_nodes = blocked
        .iter()
        .map(u32::to_string)
        .collect::<Vec<_>>()
        .join(" ");
    format!("(({edge_rows}) ({blocked_nodes}))")
}

fn scheme_request(cases: &[Case]) -> String {
    let rendered = cases
        .iter()
        .map(|(edges, blocked)| render_snapshot(edges, blocked))
        .collect::<Vec<_>>()
        .join(" ");
    format!("({rendered})\n")
}

fn session_additions(index: usize) -> (Edge, u32) {
    let nodes = if index < 522 { 3 } else { 4 };
    let from = (index % nodes) as u32;
    let to = (from + 1) % nodes as u32;
    ((from, to), to)
}

fn scheme_session_request(cases: &[Case], offset: usize) -> String {
    let rendered = cases
        .iter()
        .enumerate()
        .map(|(index, (edges, blocked))| {
            let initial = render_snapshot(edges, blocked);
            let ((from, to), added_block) = session_additions(offset + index);
            format!("({initial} ((({from} {to})) ({added_block})))")
        })
        .collect::<Vec<_>>()
        .join(" ");
    format!("(session ({rendered}))\n")
}

fn scheme_corpus_rows(cases: &[Case], request: impl Fn(&[Case], usize) -> String) -> Vec<String> {
    let mut rows = Vec::new();
    for (chunk_index, chunk) in cases.chunks(SCHEME_CORPUS_CHUNK_SIZE).enumerate() {
        let offset = chunk_index * SCHEME_CORPUS_CHUNK_SIZE;
        let output = scheme_output("integrated-corpus-rows", &request(chunk, offset));
        let mut lines = output.lines();
        while let Some(line) = lines.next() {
            if line == "END" {
                assert!(lines.next().is_none(), "fixture output after END");
                break;
            }
            let (local, rest) = line.split_once('\t').expect("indexed Scheme row");
            let global = offset + local.parse::<usize>().expect("case index");
            rows.push(format!("{global}\t{rest}"));
        }
        assert!(output.ends_with("END\n"), "fixture output missing END");
    }
    rows
}

#[test]
fn composed_three_and_four_node_corpus_matches_rust_ascent() {
    let cases = cases();
    assert_eq!(cases.len(), 778);
    let mut actual = scheme_corpus_rows(&cases, |chunk, _| scheme_request(chunk));
    actual.sort_unstable();

    let mut expected = Vec::new();
    for (index, (edges, blocked)) in cases.iter().enumerate() {
        expected.extend(
            rust_rows(edges, blocked)
                .into_iter()
                .map(|row| format!("{index}\t{row}")),
        );
    }
    expected.sort_unstable();
    assert_eq!(actual, expected);
}

#[test]
fn composed_nonpositive_sessions_match_fresh_fixed_points() {
    let cases = cases();
    let mut actual = scheme_corpus_rows(&cases, scheme_session_request);
    actual.sort_unstable();

    let mut expected = Vec::new();
    for (index, (edges, blocked)) in cases.iter().enumerate() {
        expected.extend(
            rust_rows(edges, blocked)
                .into_iter()
                .map(|row| format!("{index}\t0\t{row}")),
        );
        let (added_edge, added_block) = session_additions(index);
        let mut combined_edges = edges.clone();
        combined_edges.push(added_edge);
        let mut combined_blocked = blocked.clone();
        combined_blocked.push(added_block);
        expected.extend(
            rust_rows(&combined_edges, &combined_blocked)
                .into_iter()
                .map(|row| format!("{index}\t1\t{row}")),
        );
        expected.extend(
            rust_rows(edges, blocked)
                .into_iter()
                .map(|row| format!("{index}\t2\t{row}")),
        );
    }
    expected.sort_unstable();
    if actual != expected {
        let first = actual
            .iter()
            .zip(&expected)
            .position(|(left, right)| left != right)
            .unwrap_or(actual.len().min(expected.len()));
        panic!(
            "composed session mismatch at {first}: Scheme {:?}, fresh Rust {:?} ({} vs {} rows)",
            actual.get(first),
            expected.get(first),
            actual.len(),
            expected.len()
        );
    }
}
