use crate::{
    Atom as DeclarationAtom, Error, Program, Result, Row, Term,
    execution::{Cell, Pattern, Values},
};
use std::{
    collections::{BTreeMap, BTreeSet, HashSet},
    sync::Arc,
};
type Domains = Arc<[Option<HashSet<Cell>>]>;

#[derive(Clone, Debug)]
pub(crate) struct Atom {
    pub relation: usize,
    pub terms: std::sync::Arc<[Pattern]>,
    pub keys: Vec<usize>,
    pub index: Option<usize>,
    domains: Option<Domains>,
    pub dynamic_types: Option<Arc<[crate::Type]>>,
}
impl Atom {
    pub fn accepts(&self, row: &[Cell]) -> bool {
        self.domains.as_ref().is_none_or(|domains| {
            row.iter()
                .zip(domains.iter())
                .all(|(cell, domain)| domain.as_ref().is_none_or(|domain| domain.contains(cell)))
        })
    }
}
#[derive(Clone, Debug)]
pub(crate) enum Clause {
    Relation {
        atom: Atom,
        negative: bool,
    },
    Guard(crate::Expression),
    Compute {
        output: usize,
        expression: crate::Expression,
    },
    Reduce {
        output: usize,
        operator: crate::Reducer,
        atom: Atom,
        inputs: Vec<usize>,
    },
}
impl Clause {
    pub fn dependency(&self) -> Option<(&Atom, bool)> {
        match self {
            Self::Relation { atom, negative } => Some((atom, *negative)),
            Self::Reduce { atom, .. } => Some((atom, true)),
            _ => None,
        }
    }
}
#[derive(Clone, Debug)]
pub(crate) struct Rule {
    pub head: Atom,
    pub body: Vec<Clause>,
    pub variables: usize,
}
impl Rule {
    pub fn clauses(&self) -> std::slice::Iter<'_, Clause> {
        self.body.iter()
    }
    pub fn variables(&self) -> usize {
        self.variables
    }
}
/// Relations are nodes; rule bodies reference the dependencies of each head.
/// Positive cycles are allowed, while stratification rejects negative cycles.
#[derive(Clone, Debug)]
pub(crate) struct Graph {
    pub program: Program,
    pub names: BTreeMap<String, usize>,
    pub strata: Vec<usize>,
    pub rules: Vec<Rule>,
    pub indexes: Vec<Vec<Vec<usize>>>,
    pub values: Values,
}
impl Graph {
    pub fn build(program: Program) -> Result<Self> {
        program.fact_limits.tighten(crate::FactLimits::default())?;
        if program.relation_limit == Some(0)
            || (program.relation_limit.is_some()
                && program.relations.iter().any(|r| r.lattice.is_some()))
        {
            return Err(invalid("invalid per-relation set limit"));
        }
        let mut names = BTreeMap::new();
        for (id, relation) in program.relations.iter().enumerate() {
            validate_relation(relation)?;
            if relation.name.is_empty() || names.insert(relation.name.clone(), id).is_some() {
                return Err(invalid("empty or duplicate relation name"));
            }
        }
        let mut values = Values::default();
        let mut rules = program
            .rules
            .iter()
            .map(|rule| RuleAdmission::new(&program, &names, &mut values).admit(rule))
            .collect::<Result<Vec<_>>>()?;
        let indexes = prepare_indexes(&mut rules, program.relations.len());
        if !super::certificate::check(&program, &rules, &indexes, &values) {
            return Err(invalid("positive compiler certificate rejected"));
        }
        let strata = stratify(&program.relations, &rules)?;
        Ok(Self {
            program,
            names,
            strata,
            rules,
            indexes,
            values,
        })
    }
    pub fn validate_rows(&self, relation: &str, rows: &[Row]) -> Result<usize> {
        let id = *self
            .names
            .get(relation)
            .ok_or_else(|| Error::InvalidUpdate("unknown source".into()))?;
        let declaration = &self.program.relations[id];
        if !declaration.source {
            return Err(Error::InvalidUpdate(
                "derived relation is not source authority".into(),
            ));
        }
        if rows.iter().any(|row| !declaration.accepts(row)) {
            return Err(Error::InvalidUpdate(
                "source row type/arity mismatch".into(),
            ));
        }
        Ok(id)
    }
}

// Validation visits each domain member and each initial row once.
fn validate_relation(relation: &crate::Relation) -> Result<()> {
    if relation.lattice.is_some() && (relation.columns.is_empty() || relation.source) {
        return Err(invalid(
            "lattice needs a value column and cannot be source authority",
        ));
    }
    if relation.lattice.is_some()
        && relation.rows.iter().any(|row| {
            row.last()
                .is_none_or(|value| crate::lattice::numeric(value).is_err())
        })
    {
        return Err(invalid("numeric lattice initial value required"));
    }

    if relation.domains.len() != relation.columns.len()
        || relation
            .domains
            .iter()
            .zip(&relation.columns)
            .any(|(domain, ty)| {
                domain
                    .as_ref()
                    .is_some_and(|values| values.iter().any(|v| !ty.accepts(v)))
            })
    {
        return Err(invalid("invalid column domain"));
    }
    if relation.rows.iter().any(|row| !relation.accepts(row)) {
        return Err(invalid("initial row type/arity/domain mismatch"));
    }
    Ok(())
}

fn prepare_indexes(rules: &mut [Rule], relations: usize) -> Vec<Vec<Vec<usize>>> {
    let mut shapes = vec![Vec::new(); relations];
    let mut slots = vec![BTreeMap::new(); relations];
    for atom in rules
        .iter_mut()
        .flat_map(|rule| &mut rule.body)
        .filter_map(|clause| match clause {
            Clause::Relation { atom, .. } | Clause::Reduce { atom, .. } => Some(atom),
            _ => None,
        })
    {
        if atom.keys.is_empty() {
            continue;
        }
        let relation = &mut shapes[atom.relation];
        let slot = *slots[atom.relation]
            .entry(atom.keys.clone())
            .or_insert_with(|| {
                relation.push(atom.keys.clone());
                relation.len() - 1
            });
        atom.index = Some(slot);
    }
    shapes
}

fn invalid(message: &str) -> Error {
    Error::InvalidProgram(message.into())
}

struct RuleAdmission<'a> {
    program: &'a Program,
    values: &'a mut Values,
    names: &'a BTreeMap<String, usize>,
    variables: BTreeMap<u32, usize>,
    bound: BTreeSet<u32>,
    types: BTreeMap<u32, crate::Type>,
}
impl<'a> RuleAdmission<'a> {
    fn new(
        program: &'a Program,
        names: &'a BTreeMap<String, usize>,
        values: &'a mut Values,
    ) -> Self {
        Self {
            program,
            values,
            names,
            variables: BTreeMap::new(),
            bound: BTreeSet::new(),
            types: BTreeMap::new(),
        }
    }
    fn admit(mut self, rule: &crate::Rule) -> Result<Rule> {
        let body = rule
            .body
            .iter()
            .map(|clause| self.clause(clause))
            .collect::<Result<Vec<_>>>()?;
        let head = self.atom(&rule.head, true, false)?;
        Ok(Rule {
            head,
            body,
            variables: self.variables.len(),
        })
    }
    fn clause(&mut self, clause: &crate::Clause) -> Result<Clause> {
        use crate::Clause as Input;
        match clause {
            Input::Relation { atom, negative } => Ok(Clause::Relation {
                atom: self.atom(atom, false, *negative)?,
                negative: *negative,
            }),
            Input::Guard { inputs, expression } => {
                self.inputs(inputs)?;
                Ok(Clause::Guard(self.expression(expression)?))
            }
            Input::Compute {
                inputs,
                output,
                expression,
            } => {
                self.inputs(inputs)?;
                let checked = self.expression(expression)?;
                let ty = self
                    .expression_type(expression)
                    .ok_or_else(|| invalid("compute output type is not determined"))?;
                let output = self.output(*output, ty)?;
                Ok(Clause::Compute {
                    output,
                    expression: checked,
                })
            }
            Input::Reduce {
                output,
                operator,
                atom,
                inputs,
            } => {
                if inputs.len() != usize::from(*operator != crate::Reducer::Count) {
                    return Err(invalid("reducer input arity"));
                }
                let outer = self.bound.clone();
                let checked = self.atom(atom, false, false)?;
                let result_type = if *operator == crate::Reducer::Count
                    || (*operator != crate::Reducer::Mean
                        && inputs
                            .iter()
                            .all(|id| self.types.get(id) == Some(&crate::Type::Integer)))
                {
                    crate::Type::Integer
                } else {
                    crate::Type::Any
                };
                let inputs = inputs
                    .iter()
                    .map(|id| {
                        if !atom.terms.contains(&Term::Variable(*id))
                            || !matches!(
                                self.types.get(id),
                                Some(crate::Type::Integer | crate::Type::Any)
                            )
                        {
                            return Err(invalid("reducer needs an integer variable from its atom"));
                        }
                        Ok(self.variables[id])
                    })
                    .collect::<Result<Vec<_>>>()?;
                self.bound = outer;
                let output = self.output(*output, result_type)?;
                Ok(Clause::Reduce {
                    output,
                    operator: *operator,
                    atom: checked,
                    inputs,
                })
            }
        }
    }
    fn inputs(&mut self, inputs: &[u32]) -> Result<()> {
        for input in inputs {
            self.expression(&crate::Expression::Term(Term::Variable(*input)))?;
        }
        Ok(())
    }
    fn output(&mut self, output: u32, ty: crate::Type) -> Result<usize> {
        let Term::Variable(slot) = self.term(&Term::Variable(output), ty, false, false)? else {
            unreachable!()
        };
        Ok(slot as usize)
    }
    fn expression_type(&self, expression: &crate::Expression) -> Option<crate::Type> {
        use crate::{Expression, Operator, Type, Value};
        match expression {
            Expression::Term(Term::Variable(id)) => self.types.get(id).copied(),
            Expression::Term(Term::Literal(value)) => Some(match value {
                Value::Object(_) => Type::Any,
                Value::Integer(_) => Type::Integer,
                Value::Boolean(_) => Type::Boolean,
                Value::Text(_) => Type::Text,
                Value::Symbol(_) => Type::Symbol,
            }),
            Expression::Term(Term::Wildcard) => None,
            Expression::Call(operator, operands) => match operator {
                Operator::Add | Operator::Subtract | Operator::Multiply => Some(Type::Integer),
                Operator::Identity => self.expression_type(&operands[0]),
                Operator::StringAppend | Operator::SymbolToString => Some(Type::Text),
                Operator::StringToSymbol => Some(Type::Symbol),
                Operator::VectorRef => Some(Type::Any),
                Operator::And | Operator::Or => {
                    let first = operands
                        .first()
                        .map_or(Some(Type::Boolean), |e| self.expression_type(e));
                    operands
                        .iter()
                        .all(|e| self.expression_type(e) == first)
                        .then_some(first)
                        .flatten()
                }
                _ => Some(Type::Boolean),
            },
        }
    }
    fn expression(&mut self, expression: &crate::Expression) -> Result<crate::Expression> {
        self.expression_at(expression, 0, &mut 0)
    }
    fn expression_at(
        &mut self,
        expression: &crate::Expression,
        depth: usize,
        nodes: &mut usize,
    ) -> Result<crate::Expression> {
        use crate::Expression;
        if depth > 128 || *nodes >= 65_536 {
            return Err(invalid("expression structure bound"));
        }
        *nodes += 1;
        match expression {
            Expression::Term(Term::Variable(id)) => {
                if !self.bound.contains(id) {
                    return Err(invalid("unbound operator variable"));
                }
                Ok(Expression::Term(Term::Variable(
                    u32::try_from(self.variables[id]).map_err(|_| invalid("variable bound"))?,
                )))
            }
            Expression::Term(Term::Literal(value)) => {
                Ok(Expression::Term(Term::Literal(value.clone())))
            }
            Expression::Term(Term::Wildcard) => Err(invalid("operator wildcard")),
            Expression::Call(operator, operands) => {
                if !operator.arity(operands.len()) {
                    return Err(invalid("operator arity"));
                }
                Ok(Expression::Call(
                    *operator,
                    operands
                        .iter()
                        .map(|e| self.expression_at(e, depth + 1, nodes))
                        .collect::<Result<_>>()?,
                ))
            }
        }
    }
    fn atom(&mut self, atom: &DeclarationAtom, head: bool, negative: bool) -> Result<Atom> {
        let id = *self
            .names
            .get(&atom.relation)
            .ok_or_else(|| invalid("undeclared relation"))?;
        let declaration = &self.program.relations[id];
        if head && declaration.auxiliary {
            return Err(invalid("mapping tables cannot be rule heads"));
        }
        if head && declaration.source {
            return Err(invalid("rule cannot define a source relation"));
        }
        if declaration.columns.len() != atom.terms.len() {
            return Err(invalid("atom arity mismatch"));
        }
        let keys = atom
            .terms
            .iter()
            .enumerate()
            .filter_map(|(i, term)| match term {
                Term::Literal(_) => Some(i),
                Term::Variable(v) if self.bound.contains(v) => Some(i),
                _ => None,
            })
            .collect();
        let dynamic_types = (head && atom.terms.iter().zip(&declaration.columns).any(|(term, ty)|
            matches!(term, Term::Variable(id) if self.types.get(id) == Some(&crate::Type::Any) && *ty != crate::Type::Any)))
            .then(|| Arc::from(declaration.columns.clone()));
        let columns = declaration.columns.clone();
        let terms = atom
            .terms
            .iter()
            .zip(columns)
            .map(|(term, ty)| self.term(term, ty, head, negative))
            .collect::<Result<Vec<_>>>()?;
        let domains = if head && declaration.domains.iter().any(Option::is_some) {
            Some(
                declaration
                    .domains
                    .iter()
                    .map(|domain| {
                        domain.as_ref().map(|domain| {
                            domain
                                .iter()
                                .map(|value| self.values.intern(value))
                                .collect()
                        })
                    })
                    .collect::<Vec<_>>()
                    .into(),
            )
        } else {
            None
        };
        Ok(Atom {
            dynamic_types,
            domains,
            relation: id,
            terms: terms
                .into_iter()
                .map(|term| self.values.pattern(term))
                .collect(),
            keys,
            index: None,
        })
    }
    fn term(&mut self, term: &Term, ty: crate::Type, head: bool, negative: bool) -> Result<Term> {
        match term {
            Term::Variable(variable) => {
                if (head || negative) && !self.bound.contains(variable) {
                    return Err(invalid("unbound head or negative variable"));
                }
                if let Some(old) = self.types.get(variable) {
                    if *old != ty
                        && ty != crate::Type::Any
                        && *old != crate::Type::Any
                        && !matches!(
                            (*old, ty),
                            (crate::Type::Number, crate::Type::Integer)
                                | (crate::Type::Integer, crate::Type::Number)
                        )
                    {
                        return Err(invalid("variable column type mismatch"));
                    }
                    if *old == crate::Type::Any {
                        self.types.insert(*variable, ty);
                    }
                } else {
                    self.types.insert(*variable, ty);
                }
                let next = self.variables.len();
                let slot = *self.variables.entry(*variable).or_insert(next);
                if !negative && !head {
                    self.bound.insert(*variable);
                }
                Ok(Term::Variable(
                    u32::try_from(slot).map_err(|_| invalid("too many variables"))?,
                ))
            }
            Term::Literal(value) if !ty.accepts(value) => {
                Err(invalid("literal column type mismatch"))
            }
            Term::Wildcard if head => Err(invalid("wildcard in rule head")),
            _ => Ok(term.clone()),
        }
    }
}

fn stratify(relations: &[crate::Relation], rules: &[Rule]) -> Result<Vec<usize>> {
    let count = relations.len();
    let mut strata = vec![0usize; count];
    let edges: Vec<_> = rules
        .iter()
        .flat_map(|rule| {
            rule.body.iter().filter_map(|clause| {
                clause.dependency().map(|(atom, strict)| {
                    (
                        rule.head.relation,
                        atom.relation,
                        usize::from(
                            strict
                                || (relations[atom.relation].lattice.is_some()
                                    && relations[rule.head.relation].lattice.is_none()),
                        ),
                    )
                })
            })
        })
        .collect();
    for iteration in 0..=count {
        let mut changed = false;
        for (head, dependency, negative) in &edges {
            let required = strata[*dependency] + negative;
            if strata[*head] < required {
                strata[*head] = required;
                changed = true;
            }
        }
        if !changed {
            return Ok(strata);
        }
        if iteration == count {
            return Err(invalid(
                "unstratified negation, aggregate or lattice projection recursion",
            ));
        }
    }
    unreachable!()
}
