// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
//! Complete reference-engine outputs, including initialization and liveness.
//! No Scheme runtime or transitive Provider participates in this oracle.
use polonius_engine::{Algorithm, AllFacts, Atom, FactTypes, Output};
use std::collections::HashMap;
use std::fs;
use std::io::{self, BufRead, Write};
use std::path::Path;

macro_rules! atom {
    ($name:ident) => {
        #[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd, Hash)]
        struct $name(usize);
        impl From<usize> for $name {
            fn from(value: usize) -> Self {
                Self(value)
            }
        }
        impl From<$name> for usize {
            fn from(value: $name) -> Self {
                value.0
            }
        }
        impl Atom for $name {
            fn index(self) -> usize {
                self.0
            }
        }
    };
}
atom!(Origin);
atom!(Loan);
atom!(Point);
atom!(Variable);
atom!(MovePath);
#[derive(Clone, Copy, Debug)]
struct Types;
impl FactTypes for Types {
    type Origin = Origin;
    type Loan = Loan;
    type Point = Point;
    type Variable = Variable;
    type Path = MovePath;
}
#[derive(Default)]
struct Names {
    ids: HashMap<String, usize>,
    text: Vec<String>,
}
impl Names {
    fn intern(&mut self, text: &str) -> usize {
        if let Some(id) = self.ids.get(text) {
            return *id;
        }
        let id = self.text.len();
        self.text.push(text.to_owned());
        self.ids.insert(text.to_owned(), id);
        id
    }
    fn read<const N: usize>(
        &mut self,
        directory: &Path,
        name: &str,
    ) -> io::Result<Vec<[usize; N]>> {
        let file = fs::File::open(directory.join(format!("{name}.facts")))?;
        let mut result = Vec::new();
        for (ordinal, line) in io::BufReader::new(file).lines().enumerate() {
            let line = line?;
            let fields: Vec<_> = line.split('\t').collect();
            if fields.len() != N || fields.iter().any(|field| field.is_empty()) {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    format!("{name}:{} requires {N} nonempty fields", ordinal + 1),
                ));
            }
            result.push(std::array::from_fn(|index| self.intern(fields[index])));
        }
        println!("POLONIUS-SOURCE name={name} rows={}", result.len());
        io::stdout().flush()?;
        Ok(result)
    }
}
fn load(directory: &Path, names: &mut Names) -> io::Result<AllFacts<Types>> {
    let mut facts = AllFacts::default();
    macro_rules! pair {
        ($field:ident, $left:ident, $right:ident) => {
            facts.$field = names
                .read::<2>(directory, stringify!($field))?
                .into_iter()
                .map(|[a, b]| ($left(a), $right(b)))
                .collect();
        };
    }
    macro_rules! triple {
        ($field:ident, $first:ident, $second:ident, $third:ident) => {
            facts.$field = names
                .read::<3>(directory, stringify!($field))?
                .into_iter()
                .map(|[a, b, c]| ($first(a), $second(b), $third(c)))
                .collect();
        };
    }
    triple!(loan_issued_at, Origin, Loan, Point);
    facts.universal_region = names
        .read::<1>(directory, "universal_region")?
        .into_iter()
        .map(|[a]| Origin(a))
        .collect();
    pair!(cfg_edge, Point, Point);
    pair!(loan_killed_at, Loan, Point);
    triple!(subset_base, Origin, Origin, Point);
    // Public raw facts use point/loan; the reference engine owns its internal index.
    pair!(loan_invalidated_at, Point, Loan);
    pair!(var_used_at, Variable, Point);
    pair!(var_defined_at, Variable, Point);
    pair!(var_dropped_at, Variable, Point);
    pair!(use_of_var_derefs_origin, Variable, Origin);
    pair!(drop_of_var_derefs_origin, Variable, Origin);
    pair!(child_path, MovePath, MovePath);
    pair!(path_is_var, MovePath, Variable);
    pair!(path_assigned_at_base, MovePath, Point);
    pair!(path_moved_at_base, MovePath, Point);
    pair!(path_accessed_at_base, MovePath, Point);
    pair!(known_placeholder_subset, Origin, Origin);
    pair!(placeholder, Origin, Loan);
    Ok(facts)
}
// Sort borrowed interned names; hold only fixed-size ID tuples per row.
// Equality of IDs is equality of source tokens, so deduplication preserves the
// reference engine's set semantics without per-result string copies.
fn write_rows<const N: usize>(
    directory: &Path,
    names: &Names,
    name: &str,
    mut rows: Vec<[usize; N]>,
) -> io::Result<()> {
    rows.sort_unstable_by(|left, right| {
        left.iter()
            .map(|id| &names.text[*id])
            .cmp(right.iter().map(|id| &names.text[*id]))
    });
    rows.dedup();
    let mut file = io::BufWriter::new(fs::File::create(directory.join(format!("{name}.tsv")))?);
    for row in &rows {
        for (column, id) in row.iter().enumerate() {
            if column != 0 {
                file.write_all(b"\t")?;
            }
            file.write_all(names.text[*id].as_bytes())?;
        }
        file.write_all(b"\n")?;
    }
    file.flush()?;
    println!("POLONIUS-OUTPUT name={name} rows={}", rows.len());
    io::stdout().flush()
}
fn export(output: &Output<Types>, names: &Names, directory: &Path) -> io::Result<()> {
    fs::create_dir_all(directory)?;
    macro_rules! at_point {
        ($field:ident) => {
            write_rows(
                directory,
                names,
                stringify!($field),
                output
                    .$field
                    .iter()
                    .flat_map(|(point, values)| {
                        values.iter().map(|value| [value.index(), point.index()])
                    })
                    .collect(),
            )?;
        };
    }
    at_point!(errors);
    at_point!(move_errors);
    at_point!(loan_live_at);
    at_point!(origin_live_on_entry);
    at_point!(loan_invalidated_at);
    at_point!(var_live_on_entry);
    at_point!(var_drop_live_on_entry);
    at_point!(path_maybe_initialized_on_exit);
    at_point!(path_maybe_uninitialized_on_exit);
    at_point!(var_maybe_partly_initialized_on_exit);
    write_rows(
        directory,
        names,
        "subset_errors",
        output
            .subset_errors
            .iter()
            .flat_map(|(point, pairs)| {
                pairs
                    .iter()
                    .map(|(left, right)| [left.index(), right.index(), point.index()])
            })
            .collect(),
    )?;
    write_rows(
        directory,
        names,
        "subset",
        output
            .subset
            .iter()
            .flat_map(|(point, origins)| {
                origins.iter().flat_map(|(left, rights)| {
                    rights
                        .iter()
                        .map(|right| [left.index(), right.index(), point.index()])
                })
            })
            .collect(),
    )?;
    write_rows(
        directory,
        names,
        "origin_contains_loan_at",
        output
            .origin_contains_loan_at
            .iter()
            .flat_map(|(point, origins)| {
                origins.iter().flat_map(|(origin, loans)| {
                    loans
                        .iter()
                        .map(|loan| [origin.index(), loan.index(), point.index()])
                })
            })
            .collect(),
    )?;
    write_rows(
        directory,
        names,
        "known_contains",
        output
            .known_contains
            .iter()
            .flat_map(|(origin, loans)| loans.iter().map(|loan| [origin.index(), loan.index()]))
            .collect(),
    )?;
    Ok(())
}
fn main() -> io::Result<()> {
    let args: Vec<_> = std::env::args().collect();
    if args.len() != 4 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "usage: polonius_data_truth INPUT_DIRECTORY OUTPUT_DIRECTORY naive|datafrog-opt",
        ));
    }
    let algorithm = match args[3].as_str() {
        "naive" => Algorithm::Naive,
        "datafrog-opt" => Algorithm::DatafrogOpt,
        _ => {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "unknown reference algorithm",
            ));
        }
    };
    let mut names = Names::default();
    let facts = load(Path::new(&args[1]), &mut names)?;
    println!("POLONIUS-REFERENCE-START algorithm={algorithm:?} dump=true");
    io::stdout().flush()?;
    let solve_started = std::time::Instant::now();
    let output = Output::<Types>::compute(&facts, algorithm, true);
    println!(
        "POLONIUS-SOLVE-COMPLETE elapsed-ms={}",
        solve_started.elapsed().as_millis()
    );
    io::stdout().flush()?;
    let export_started = std::time::Instant::now();
    export(&output, &names, Path::new(&args[2]))?;
    println!(
        "POLONIUS-REFERENCE-COMPLETE export-ms={}",
        export_started.elapsed().as_millis()
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    pub(super) struct Inputs(pub(super) std::path::PathBuf);
    impl Inputs {
        pub(super) fn empty() -> Self {
            let nonce = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let directory = std::env::temp_dir()
                .join(format!("ascent-polonius-{}-{nonce}", std::process::id()));
            fs::create_dir(&directory).unwrap();
            for name in [
                "loan_issued_at",
                "universal_region",
                "cfg_edge",
                "loan_killed_at",
                "subset_base",
                "loan_invalidated_at",
                "var_used_at",
                "var_defined_at",
                "var_dropped_at",
                "use_of_var_derefs_origin",
                "drop_of_var_derefs_origin",
                "child_path",
                "path_is_var",
                "path_assigned_at_base",
                "path_moved_at_base",
                "path_accessed_at_base",
                "known_placeholder_subset",
                "placeholder",
            ] {
                fs::write(directory.join(format!("{name}.facts")), "").unwrap();
            }
            Self(directory)
        }
        pub(super) fn write(&self, name: &str, data: &str) {
            fs::write(self.0.join(format!("{name}.facts")), data).unwrap();
        }
    }
    impl Drop for Inputs {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
    #[test]
    fn raw_invalidation_is_point_then_loan() {
        let inputs = Inputs::empty();
        inputs.write("cfg_edge", "p0\tp1\n");
        inputs.write("universal_region", "origin\n");
        inputs.write("loan_issued_at", "origin\tloan\tp0\n");
        for (raw, expected_error) in [("p1\tloan\n", true), ("loan\tp1\n", false)] {
            inputs.write("loan_invalidated_at", raw);
            let mut names = Names::default();
            let facts = load(&inputs.0, &mut names).unwrap();
            let point = Point(names.intern("p1"));
            let loan = Loan(names.intern("loan"));
            for algorithm in [Algorithm::Naive, Algorithm::DatafrogOpt] {
                let output = Output::<Types>::compute(&facts, algorithm, true);
                if expected_error {
                    assert_eq!(output.errors.get(&point), Some(&vec![loan]));
                } else {
                    assert!(output.errors.is_empty());
                }
            }
        }
    }
    #[test]
    fn export_is_name_ordered_and_preserves_field_order() {
        let inputs = Inputs::empty();
        let mut names = Names::default();
        let z = names.intern("z");
        let a = names.intern("a");
        let p = names.intern("point");
        write_rows(&inputs.0, &names, "rows", vec![[z, p], [a, p], [z, p]]).unwrap();
        assert_eq!(
            fs::read_to_string(inputs.0.join("rows.tsv")).unwrap(),
            "a\tpoint\nz\tpoint\n"
        );
    }
    #[test]
    fn point_scopes_do_not_join_and_cycles_do_not_publish_self_subsets() {
        let mut facts = AllFacts::<Types>::default();
        facts.cfg_edge = vec![(Point(0), Point(0)), (Point(1), Point(1))];
        facts.universal_region = vec![Origin(0), Origin(1), Origin(2)];
        facts.subset_base = vec![
            (Origin(0), Origin(1), Point(0)),
            (Origin(1), Origin(0), Point(0)),
            (Origin(1), Origin(2), Point(1)),
        ];
        for algorithm in [Algorithm::Naive, Algorithm::DatafrogOpt] {
            let output = Output::<Types>::compute(&facts, algorithm, true);
            for relation in output.subset.values() {
                for (left, rights) in relation {
                    assert!(!rights.contains(left));
                }
            }
            assert!(output.subset[&Point(0)][&Origin(0)].contains(&Origin(1)));
            assert!(!output.subset[&Point(0)][&Origin(0)].contains(&Origin(2)));
            assert!(output.subset[&Point(1)][&Origin(1)].contains(&Origin(2)));
        }
    }
    #[test]
    fn killed_loan_cannot_escape_along_cfg() {
        let mut facts = AllFacts::<Types>::default();
        facts.cfg_edge = vec![(Point(0), Point(1))];
        facts.universal_region = vec![Origin(2)];
        facts.loan_issued_at = vec![(Origin(2), Loan(3), Point(0))];
        facts.loan_killed_at = vec![(Loan(3), Point(0))];
        facts.loan_invalidated_at = vec![(Point(1), Loan(3))];
        for algorithm in [Algorithm::Naive, Algorithm::DatafrogOpt] {
            assert!(
                Output::<Types>::compute(&facts, algorithm, true)
                    .errors
                    .is_empty()
            );
        }
    }
}

#[cfg(test)]
#[path = "polonius_data_truth/controls.rs"]
mod control_tests;
