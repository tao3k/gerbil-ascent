// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
//! Independent full-data partition oracle. Counts implied pairs without
//! materializing them; it is not a Scheme runtime or a Scheme performance result.
use ascent::ascent;
use ascent_byods_rels::eqrel;
use std::{collections::HashMap, error::Error, fs, path::Path};

fn rust_application_count(
    alloc: Vec<(usize, usize)>,
    assign: Vec<(usize, usize)>,
    load: Vec<(usize, usize, usize)>,
    store: Vec<(usize, usize, usize)>,
) -> usize {
    ascent! {
        relation alloc(usize, usize);
        relation assign(usize, usize);
        relation load(usize, usize, usize);
        relation store(usize, usize, usize);
        #[ds(eqrel)]
        relation vpt(usize, usize);
        vpt(x, y) <-- assign(x, y);
        vpt(x, y) <-- alloc(x, y);
        vpt(y, p) <-- store(x, f, y), load(p, q, f), vpt(x, q);
    }
    let mut program = AscentProgram {
        alloc,
        assign,
        load,
        store,
        ..AscentProgram::default()
    };
    program.run();
    program.__vpt_ind_common.count_exact()
}

#[derive(Default)]
struct Partition {
    names: HashMap<String, usize>,
    parent: Vec<usize>,
    size: Vec<usize>,
    active: Vec<bool>,
}
impl Partition {
    fn node(&mut self, name: &str) -> usize {
        if let Some(&id) = self.names.get(name) {
            return id;
        }
        let id = self.parent.len();
        self.names.insert(name.to_owned(), id);
        self.parent.push(id);
        self.size.push(1);
        self.active.push(false);
        id
    }
    fn root(&mut self, id: usize) -> usize {
        let parent = self.parent[id];
        if parent != id {
            self.parent[id] = self.root(parent);
        }
        self.parent[id]
    }
    fn join(&mut self, left: usize, right: usize) -> bool {
        let mut a = self.root(left);
        let mut b = self.root(right);
        let changed = a != b || !self.active[a];
        if a != b {
            if self.size[a] < self.size[b] {
                std::mem::swap(&mut a, &mut b);
            }
            self.parent[b] = a;
            self.size[a] += self.size[b];
        }
        self.active[a] = true;
        changed
    }
    fn equivalent(&mut self, a: usize, b: usize) -> bool {
        let a = self.root(a);
        let b = self.root(b);
        a == b && self.active[a]
    }
    fn counts(&self) -> (usize, usize, u128) {
        let mut classes = 0;
        let mut largest = 0;
        let mut pairs = 0;
        for (id, &parent) in self.parent.iter().enumerate() {
            if parent == id && self.active[id] {
                classes += 1;
                largest = largest.max(self.size[id]);
                pairs += (self.size[id] as u128).pow(2);
            }
        }
        (classes, largest, pairs)
    }
}
type FieldRows = HashMap<String, Vec<(usize, usize)>>;
fn inject(partition: &mut Partition, loads: &FieldRows, stores: &FieldRows) -> usize {
    let mut changed = 0;
    for (field, writes) in stores {
        if let Some(reads) = loads.get(field) {
            for &(base, source) in writes {
                for &(destination, read_base) in reads {
                    if partition.equivalent(base, read_base) {
                        changed += usize::from(partition.join(source, destination));
                    }
                }
            }
        }
    }
    changed
}
fn read_rows(path: &Path, width: usize) -> Result<Vec<Vec<String>>, Box<dyn Error>> {
    let source = fs::read_to_string(path)?;
    let mut rows = Vec::new();
    for (ordinal, line) in source.lines().enumerate() {
        let row: Vec<_> = line.split('\t').map(str::to_owned).collect();
        if row.len() != width {
            return Err(format!(
                "{}:{}: expected {width} columns",
                path.display(),
                ordinal + 1
            )
            .into());
        }
        rows.push(row);
    }
    Ok(rows)
}
fn main() -> Result<(), Box<dyn Error>> {
    let directory = std::env::args()
        .nth(1)
        .ok_or("expected pinned dataset directory")?;
    let directory = Path::new(&directory);
    let mut partition = Partition::default();
    let mut alloc = Vec::new();
    let mut assign = Vec::new();
    for name in ["alloc", "assign"] {
        let rows = read_rows(&directory.join(format!("{name}.facts")), 2)?;
        for row in &rows {
            let a = partition.node(&row[0]);
            let b = partition.node(&row[1]);
            partition.join(a, b);
            (if name == "alloc" {
                &mut alloc
            } else {
                &mut assign
            })
            .push((a, b));
        }
        println!("MODEL-SOURCE name={name} rows={}", rows.len());
    }
    let mut loads = FieldRows::new();
    let mut stores = FieldRows::new();
    let mut load = Vec::new();
    let mut store = Vec::new();
    let mut fields = HashMap::new();
    for name in ["load", "store"] {
        let rows = read_rows(&directory.join(format!("{name}.facts")), 3)?;
        for row in &rows {
            let a = partition.node(&row[0]);
            let b = partition.node(&row[if name == "load" { 1 } else { 2 }]);
            let field = row[if name == "load" { 2 } else { 1 }].clone();
            let next = fields.len();
            let field_id = *fields.entry(field.clone()).or_insert(next);
            if name == "load" {
                load.push((a, b, field_id));
            } else {
                store.push((a, field_id, b));
            }
            (if name == "load" {
                &mut loads
            } else {
                &mut stores
            })
            .entry(field)
            .or_default()
            .push((a, b));
        }
        println!("MODEL-SOURCE name={name} rows={}", rows.len());
    }
    let mut round = 0;
    loop {
        round += 1;
        let changed = inject(&mut partition, &loads, &stores);
        println!("MODEL-ROUND round={round} effective-unions={changed}");
        if changed == 0 {
            break;
        }
    }
    let (classes, largest, pairs) = partition.counts();
    println!("RUST-APPLICATION-START");
    let rust_pairs = rust_application_count(alloc, assign, load, store);
    assert_eq!(
        rust_pairs as u128, pairs,
        "full-data implicit application count differs from partition truth"
    );
    println!("RUST-APPLICATION-OK pairs={rust_pairs}");
    println!(
        "{{\"nodes\":{},\"active_classes\":{classes},\"largest_class\":{largest},\"concrete_pairs\":{pairs},\"rounds\":{round}}}",
        partition.parent.len()
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn inactive_self_read_and_wrong_field_cannot_inject() {
        let mut p = Partition::default();
        let x = p.node("x");
        let y = p.node("y");
        let z = p.node("z");
        let loads = FieldRows::from([("f".into(), vec![(z, x)])]);
        let stores = FieldRows::from([("f".into(), vec![(x, y)])]);
        assert_eq!(inject(&mut p, &loads, &stores), 0);
        assert_eq!(p.counts(), (0, 0, 0));
        p.join(x, x);
        assert_eq!(
            inject(
                &mut p,
                &loads,
                &FieldRows::from([("g".into(), vec![(x, y)])])
            ),
            0
        );
        assert_eq!(inject(&mut p, &loads, &stores), 1);
        assert_eq!(inject(&mut p, &loads, &stores), 0);
        assert_eq!(p.counts(), (2, 2, 5));
    }
}
