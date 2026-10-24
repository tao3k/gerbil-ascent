//! First-class immutable relation graphs lower to the checked Rust program IR.
use crate::{Atom, Clause, Error, Program, Relation, Result, Row, Rule, RuleProgram, Term, Type};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

/// Immutable, checked relation composition with explicit source and recursion scopes.
#[derive(Clone, Debug)]
pub struct RelationalGraph {
    width: usize,
    node: Arc<Node>,
}
#[derive(Debug)]
enum Node {
    Variable,
    Recursive {
        variable: RelationalGraph,
        body: RelationalGraph,
    },
    Source(String, Vec<Row>),
    Project(RelationalGraph, Vec<usize>),
    Union(RelationalGraph, RelationalGraph),
    Join(RelationalGraph, RelationalGraph, usize, usize),
}
fn invalid(message: &str) -> Error {
    Error::InvalidProgram(message.into())
}
impl RelationalGraph {
    /// Construct a positive recursive relation with a lexically scoped input.
    /// # Errors
    /// Rejects oversized relations, invalid bodies and changed recursive width.
    pub fn fixed_point(width: usize, body: impl FnOnce(Self) -> Result<Self>) -> Result<Self> {
        if width > 16 {
            return Err(invalid("recursive graph width"));
        }
        let variable = Self {
            width,
            node: Arc::new(Node::Variable),
        };
        let body = body(variable.clone())?;
        if body.width != width {
            return Err(invalid("recursive graph result width"));
        }
        Ok(Self {
            width,
            node: Arc::new(Node::Recursive { variable, body }),
        })
    }
    /// # Errors
    /// Rejects invalid labels, oversized tuples and mismatched row widths.
    pub fn source(name: &str, width: usize, rows: Vec<Row>) -> Result<Self> {
        if name.is_empty()
            || name.len() > 128
            || name.starts_with("__ascent_")
            || width > 16
            || rows.iter().any(|row| row.len() != width)
        {
            return Err(invalid("invalid relational source name/width/rows"));
        }
        Ok(Self {
            width,
            node: Arc::new(Node::Source(name.into(), rows)),
        })
    }
    #[must_use]
    pub fn width(&self) -> usize {
        self.width
    }
    /// # Errors
    /// Rejects projection columns outside the input tuple.
    pub fn project(&self, columns: Vec<usize>) -> Result<Self> {
        if columns.len() > 16 || columns.iter().any(|i| *i >= self.width) {
            return Err(invalid("projection column outside source"));
        }
        Ok(Self {
            width: columns.len(),
            node: Arc::new(Node::Project(self.clone(), columns)),
        })
    }
    /// # Errors
    /// Rejects different relation widths.
    pub fn union(&self, other: &Self) -> Result<Self> {
        if self.width != other.width {
            return Err(invalid("union column mismatch"));
        }
        Ok(Self {
            width: self.width,
            node: Arc::new(Node::Union(self.clone(), other.clone())),
        })
    }
    /// # Errors
    /// Rejects invalid keys and tuples wider than the relational contract.
    pub fn join(&self, other: &Self, left: usize, right: usize) -> Result<Self> {
        if left >= self.width || right >= other.width || self.width + other.width > 16 {
            return Err(invalid("join column outside source"));
        }
        Ok(Self {
            width: self.width + other.width,
            node: Arc::new(Node::Join(self.clone(), other.clone(), left, right)),
        })
    }
    /// # Errors
    /// Rejects conflicting source declarations and invalid output identities.
    pub fn program(&self, output: &str) -> Result<RuleProgram> {
        if output.is_empty() || output.len() > 128 || output.starts_with("__ascent_") {
            return Err(invalid("invalid graph output name"));
        }
        let mut program = Program::default();
        let mut sources = BTreeMap::new();
        let mut nodes = BTreeMap::new();
        let root = self.lower(&mut program, &mut sources, &mut nodes)?;
        if sources.contains_key(output) {
            return Err(invalid("graph output shadows source"));
        }
        program
            .relations
            .push(Relation::new(output, vec![Type::Any; self.width], false));
        program.rules.push(Rule {
            head: Atom::new(output, vars(self.width)),
            body: vec![Clause::positive(Atom::new(&root, vars(self.width)))],
        });
        crate::graph::Graph::build(program.clone())?;
        Ok(RuleProgram {
            constructor: output.into(),
            sources: sources.into_keys().collect::<BTreeSet<_>>(),
            outputs: vec![output.into()],
            output_aliases: BTreeMap::new(),
            program,
            explanation: None,
        })
    }
    fn lower(
        &self,
        program: &mut Program,
        sources: &mut BTreeMap<String, (usize, Vec<Row>)>,
        nodes: &mut BTreeMap<usize, String>,
    ) -> Result<String> {
        let key = Arc::as_ptr(&self.node) as usize;
        if let Some(label) = nodes.get(&key) {
            return Ok(label.clone());
        }
        if let Node::Recursive { variable, body } = self.node.as_ref() {
            let label = format!("__ascent_graph_{}", nodes.len());
            nodes.insert(key, label.clone());
            nodes.insert(Arc::as_ptr(&variable.node) as usize, label.clone());
            program
                .relations
                .push(Relation::new(&label, vec![Type::Any; self.width], false));
            let result = body.lower(program, sources, nodes)?;
            program.rules.push(Rule {
                head: Atom::new(&label, vars(self.width)),
                body: vec![Clause::positive(Atom::new(result, vars(self.width)))],
            });
            return Ok(label);
        }
        if let Node::Source(label, rows) = self.node.as_ref() {
            let identity = (self.width, rows.clone());
            if let Some(previous) = sources.get(label) {
                if previous != &identity {
                    return Err(invalid("conflicting graph source declarations"));
                }
            } else {
                sources.insert(label.clone(), identity);
                let mut relation = Relation::new(label, vec![Type::Any; self.width], true);
                relation.rows.clone_from(rows);
                program.relations.push(relation);
            }
            nodes.insert(key, label.clone());
            return Ok(label.clone());
        }
        let mut bodies = Vec::new();
        match self.node.as_ref() {
            Node::Project(input, columns) => {
                let source = input.lower(program, sources, nodes)?;
                let terms = vars(input.width);
                bodies.push((
                    columns.iter().map(|i| terms[*i].clone()).collect(),
                    vec![Clause::positive(Atom::new(&source, terms))],
                ));
            }
            Node::Union(left, right) => {
                for input in [left, right] {
                    let source = input.lower(program, sources, nodes)?;
                    bodies.push((
                        vars(self.width),
                        vec![Clause::positive(Atom::new(&source, vars(self.width)))],
                    ));
                }
            }
            Node::Join(left, right, l, r) => {
                let left_label = left.lower(program, sources, nodes)?;
                let right_label = right.lower(program, sources, nodes)?;
                let a = vars(left.width);
                let mut b = vars(self.width)[left.width..].to_vec();
                b[*r] = a[*l].clone();
                bodies.push((
                    a.iter().chain(&b).cloned().collect(),
                    vec![
                        Clause::positive(Atom::new(&left_label, a)),
                        Clause::positive(Atom::new(&right_label, b)),
                    ],
                ));
            }
            Node::Variable => return Err(invalid("unbound recursive graph variable")),
            Node::Source(..) | Node::Recursive { .. } => unreachable!(),
        }
        let label = format!("__ascent_graph_{}", nodes.len());
        nodes.insert(key, label.clone());
        program
            .relations
            .push(Relation::new(&label, vec![Type::Any; self.width], false));
        for (terms, body) in bodies {
            program.rules.push(Rule {
                head: Atom::new(&label, terms),
                body,
            });
        }
        Ok(label)
    }
}
fn vars(width: usize) -> Vec<Term> {
    (0..width)
        .map(|slot| Term::Variable(u32::try_from(slot).expect("graph width admitted at most 16")))
        .collect()
}
