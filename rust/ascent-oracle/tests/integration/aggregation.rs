// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Built-in and custom aggregation parity.

use super::common::scheme_output;
use ascent::aggregators::{count, max, mean, min, sum};
use ascent::ascent;

fn extrema<'a>(input: impl Iterator<Item = (&'a i32,)>) -> impl Iterator<Item = i32> {
    let values: Vec<_> = input.map(|(value,)| *value).collect();
    values
        .iter()
        .min()
        .copied()
        .into_iter()
        .chain(values.iter().max().copied())
}

fn ascent_aggregate_rows(values: &[i32]) -> Vec<String> {
    ascent! {
        relation number(i32);
        relation group_key(u32);
        relation pair(u32, i32);
        relation by_group(u32, i32);
        relation minimum(i32);
        relation maximum(i32);
        relation total(i32);
        relation cardinality(usize);
        relation average(i32);
        relation custom(i32);
        minimum(value) <-- agg value = min(x) in number(x);
        maximum(value) <-- agg value = max(x) in number(x);
        total(value) <-- agg value = sum(x) in number(x);
        cardinality(value) <-- agg value = count() in number(_);
        average(value.round() as i32) <-- agg value = mean(x) in number(x);
        custom(value) <-- agg value = extrema(x) in number(x);
        by_group(group, total) <-- group_key(group), agg total = sum(x) in pair(group, x);
    }
    let mut program = AscentProgram {
        number: values.iter().copied().map(|value| (value,)).collect(),
        group_key: vec![(1,), (2,)],
        pair: vec![(1, 10), (1, 20), (2, 5)],
        ..AscentProgram::default()
    };
    program.run();
    let mut rows = Vec::new();
    rows.extend(
        program
            .by_group
            .iter()
            .map(|(group, total)| format!("by-group\t{group}\t{total}")),
    );
    rows.extend(
        program
            .minimum
            .iter()
            .map(|(value,)| format!("minimum\t{value}")),
    );
    rows.extend(
        program
            .maximum
            .iter()
            .map(|(value,)| format!("maximum\t{value}")),
    );
    rows.extend(
        program
            .total
            .iter()
            .map(|(value,)| format!("total\t{value}")),
    );
    rows.extend(
        program
            .cardinality
            .iter()
            .map(|(value,)| format!("cardinality\t{value}")),
    );
    rows.extend(
        program
            .average
            .iter()
            .map(|(value,)| format!("average\t{value}")),
    );
    rows.extend(
        program
            .custom
            .iter()
            .map(|(value,)| format!("custom\t{value}")),
    );
    rows.sort_unstable();
    rows
}

#[test]
fn builtin_and_custom_aggregators_match_ascent() {
    for values in [&[][..], &[1, 2, 3, 4, 5][..], &[5, 2, 5, 1][..]] {
        let request = format!(
            "({})\n",
            values
                .iter()
                .map(i32::to_string)
                .collect::<Vec<_>>()
                .join(" ")
        );
        let output = scheme_output("aggregate-rows", &request);
        let mut rows: Vec<_> = output.lines().map(str::to_owned).collect();
        assert_eq!(rows.pop().as_deref(), Some("END"));
        rows.sort_unstable();
        assert_eq!(rows, ascent_aggregate_rows(values), "values: {values:?}");
    }
}
