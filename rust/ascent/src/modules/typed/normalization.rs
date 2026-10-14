//! Beta lowering reifies lexical closures and uses conservative finite heights for function fixed points.
use super::types::{domain, kind, relation, signature, term};
use crate::modules::{
    Arena, Evaluation, Id, Object, fail, lower_operator, operator_count as count, operator_fields,
    operator_index as index, operator_limits,
};
use crate::{Result, Value};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};
#[derive(Clone)]
enum Lowered {
    Relation(Id),
    Closure(Arc<Closure>),
}
enum Closure {
    Lexical {
        parameter: Id,
        body: Id,
        environment: BTreeMap<Id, Lowered>,
    },
    Bottom(Id),
}
struct Context {
    steps: usize,
    limit: usize,
    sources: BTreeMap<Id, Id>,
    atoms: BTreeSet<Value>,
    domains: BTreeMap<String, BTreeSet<Value>>,
}
impl Context {
    fn charge(&mut self) -> Result<()> {
        self.steps = self.steps.checked_add(1).ok_or(crate::Error::StateLimit)?;
        if self.steps > self.limit {
            return Err(crate::Error::StateLimit);
        }
        Ok(())
    }
}
fn operator(value: &Lowered) -> Result<Id> {
    match value {
        Lowered::Relation(id) => Ok(*id),
        Lowered::Closure(_) => Err(fail("typed relation output required")),
    }
}
fn vector(arena: &Arena, id: Id, len: usize) -> Result<Vec<Id>> {
    match arena.get(id)? {
        Object::Vector(values) if values.len() == len => Ok(values.clone()),
        _ => Err(fail("typed metadata vector shape")),
    }
}
impl Evaluation<'_> {
    pub(super) fn normalize_typed(&mut self, args: &[Id], depth: usize) -> Result<Vec<Id>> {
        if !(4..=5).contains(&args.len()) {
            return Err(fail("typed normalization arity"));
        }
        relation(self.arena, self.term_type(args[0])?)?;
        let limit = args
            .get(4)
            .map(|id| index(self.arena, *id))
            .transpose()?
            .unwrap_or(10000);
        if limit == 0 {
            return Err(fail("typed expansion limit must be positive"));
        }
        let mut context = Context {
            steps: 0,
            limit,
            sources: BTreeMap::new(),
            atoms: BTreeSet::new(),
            domains: BTreeMap::new(),
        };
        self.check_typed(&mut context, args[0], &BTreeSet::new(), depth + 1)?;
        let root =
            operator(&self.lower_typed(&mut context, args[0], &BTreeMap::new(), depth + 1)?)?;
        let root = self.typed_output(root)?;
        let namespace = self.arena.add(Object::Void)?;
        let graph = lower_operator(
            self.arena,
            self.arena.identity,
            root,
            "output",
            namespace,
            false,
        )?;
        let mut program = graph.program;
        program.fact_limits = operator_limits(self.arena, &args[1..4])?;
        for relation in &mut program.relations {
            let domain = context
                .domains
                .get(&relation.name)
                .unwrap_or(&context.atoms);
            relation.domains = vec![Some(domain.clone()); relation.columns.len()];
        }
        crate::graph::Graph::build(program.clone())?;
        let output = self.arena.relation_name(&graph.output)?;
        let program = self
            .arena
            .add(Object::Compiled(Arc::new(program), vec![root, args[0]]))?;
        Ok(vec![program, output])
    }
    fn typed_output(&mut self, root: Id) -> Result<Id> {
        let (kind, arity, _) = operator_fields(self.arena, root)?;
        if kind != "op-source" {
            return Ok(root);
        }
        let columns = (0..arity)
            .map(|c| {
                self.arena
                    .add(Object::Number(num_rational::BigRational::from_integer(
                        c.into(),
                    )))
            })
            .collect::<Result<Vec<_>>>()?;
        let columns = self.arena.list(&columns)?;
        let values = self.operator("relational-op-project", &[root, columns], 0)?;
        Ok(values[0])
    }
    fn check_typed(
        &mut self,
        context: &mut Context,
        node: Id,
        scope: &BTreeSet<Id>,
        depth: usize,
    ) -> Result<()> {
        self.check(depth)?;
        context.charge()?;
        let fields = term(self.arena, node)?;
        self.collect_type(context, fields[0], depth + 1)?;
        let kind = kind(self.arena, fields[1])?;
        let inputs = self.arena.items(fields[2])?;
        if kind == "parameter" && !scope.contains(&node) {
            return Err(fail("typed parameter outside admitted lexical scope"));
        }
        if kind == "function" {
            count(&inputs, 1)?;
            let mut scope = scope.clone();
            scope.insert(fields[3]);
            self.check_typed(context, fields[3], &scope, depth + 1)?;
            return self.check_typed(context, inputs[0], &scope, depth + 1);
        }
        inputs
            .into_iter()
            .try_for_each(|input| self.check_typed(context, input, scope, depth + 1))
    }
    fn collect_type(&mut self, context: &mut Context, ty: Id, depth: usize) -> Result<()> {
        self.check(depth)?;
        context.charge()?;
        let fields = signature(self.arena, ty)?;
        if kind(self.arena, fields[0])? == "relation" {
            context.atoms.extend(domain(self.arena, fields[2])?);
            Ok(())
        } else {
            self.collect_type(context, fields[1], depth + 1)?;
            self.collect_type(context, fields[2], depth + 1)
        }
    }
    fn lower_typed(
        &mut self,
        context: &mut Context,
        node: Id,
        environment: &BTreeMap<Id, Lowered>,
        depth: usize,
    ) -> Result<Lowered> {
        self.check(depth)?;
        context.charge()?;
        let fields = term(self.arena, node)?;
        let kind = kind(self.arena, fields[1])?;
        let inputs = self.arena.items(fields[2])?;
        match kind.as_str() {
            "source" => self.lower_source(context, node, &fields),
            "parameter" => environment
                .get(&node)
                .cloned()
                .ok_or_else(|| fail("typed parameter missing from lexical environment")),
            "function" => Ok(Lowered::Closure(Arc::new(Closure::Lexical {
                parameter: fields[3],
                body: inputs[0],
                environment: environment.clone(),
            }))),
            "apply" => {
                let function = self.lower_typed(context, inputs[0], environment, depth + 1)?;
                let argument = self.lower_typed(context, inputs[1], environment, depth + 1)?;
                self.apply_typed(context, function, argument, depth + 1)
            }
            "fix" => self.lower_fix(context, &fields, inputs[0], environment, depth + 1),
            _ => self.lower_relation(context, &fields, &inputs, environment, depth + 1),
        }
    }
    fn lower_source(&mut self, context: &mut Context, node: Id, fields: &[Id]) -> Result<Lowered> {
        if let Some(id) = context.sources.get(&node) {
            return Ok(Lowered::Relation(*id));
        }
        let data = vector(self.arena, fields[3], 2)?;
        let (arity, atoms) = relation(self.arena, fields[0])?;
        let width = self
            .arena
            .add(Object::Number(num_rational::BigRational::from_integer(
                arity.into(),
            )))?;
        let values = self.operator("relational-op-source", &[data[0], width, data[1]], 0)?;
        context.domains.insert(
            self.arena.checked_name(data[0])?,
            domain(self.arena, atoms)?,
        );
        context.sources.insert(node, values[0]);
        Ok(Lowered::Relation(values[0]))
    }
    fn apply_typed(
        &mut self,
        context: &mut Context,
        function: Lowered,
        argument: Lowered,
        depth: usize,
    ) -> Result<Lowered> {
        self.check(depth)?;
        context.charge()?;
        let Lowered::Closure(closure) = function else {
            return Err(fail("typed function descriptor required"));
        };
        match &*closure {
            Closure::Lexical {
                parameter,
                body,
                environment,
            } => {
                let mut environment = environment.clone();
                environment.insert(*parameter, argument);
                self.lower_typed(context, *body, &environment, depth + 1)
            }
            Closure::Bottom(output) => self.typed_bottom(context, *output, depth + 1),
        }
    }
    fn typed_bottom(&mut self, context: &mut Context, ty: Id, depth: usize) -> Result<Lowered> {
        self.check(depth)?;
        context.charge()?;
        let fields = signature(self.arena, ty)?;
        if kind(self.arena, fields[0])? == "arrow" {
            return Ok(Lowered::Closure(Arc::new(Closure::Bottom(fields[2]))));
        }
        let nonce = self.arena.add(Object::Void)?;
        let name = self.arena.symbol(&format!("typed-bottom-{nonce}"), false)?;
        let rows = self.arena.list(&[])?;
        let values = self.operator("relational-op-source", &[name, fields[1], rows], depth + 1)?;
        context.domains.insert(
            self.arena.checked_name(name)?,
            domain(self.arena, fields[2])?,
        );
        Ok(Lowered::Relation(values[0]))
    }
    fn lower_fix(
        &mut self,
        context: &mut Context,
        fields: &[Id],
        input: Id,
        environment: &BTreeMap<Id, Lowered>,
        depth: usize,
    ) -> Result<Lowered> {
        let function = self.lower_typed(context, input, environment, depth + 1)?;
        let ty = fields[0];
        if let Ok((arity, _)) = relation(self.arena, ty) {
            let parameter = self.descriptor("op-parameter", arity, &[])?;
            let body = operator(&self.apply_typed(
                context,
                function,
                Lowered::Relation(parameter),
                depth + 1,
            )?)?;
            return self
                .descriptor("op-fix", arity, &[parameter, body])
                .map(Lowered::Relation);
        }
        let cap = context.limit.saturating_add(1);
        let height = height(self.arena, ty, cap, 0)?;
        if height > context.limit - context.steps {
            return Err(crate::Error::StateLimit);
        }
        let mut value = self.typed_bottom(context, ty, depth + 1)?;
        for _ in 0..height {
            value = self.apply_typed(context, function.clone(), value, depth + 1)?;
        }
        Ok(value)
    }
    fn lower_relation(
        &mut self,
        context: &mut Context,
        fields: &[Id],
        inputs: &[Id],
        environment: &BTreeMap<Id, Lowered>,
        depth: usize,
    ) -> Result<Lowered> {
        let kind = kind(self.arena, fields[1])?;
        let mut arguments = inputs
            .iter()
            .map(|input| {
                self.lower_typed(context, *input, environment, depth + 1)
                    .and_then(|value| operator(&value))
            })
            .collect::<Result<Vec<_>>>()?;
        let name = match kind.as_str() {
            "union" => "relational-op-union",
            "join" => {
                arguments.extend(vector(self.arena, fields[3], 2)?);
                "relational-op-join"
            }
            "project" => {
                arguments.push(fields[3]);
                "relational-op-project"
            }
            "select-eq" => {
                arguments.extend(vector(self.arena, fields[3], 2)?);
                "relational-op-select-eq"
            }
            "flatmap" => {
                let (arity, _) = relation(self.arena, fields[0])?;
                arguments.push(self.arena.add(Object::Number(
                    num_rational::BigRational::from_integer(arity.into()),
                ))?);
                arguments.push(fields[3]);
                "relational-op-flatmap"
            }
            _ => return Err(fail("unsupported finite typed relation node")),
        };
        self.operator(name, &arguments, depth + 1)
            .map(|v| Lowered::Relation(v[0]))
    }
}
fn power(cap: usize, base: usize, mut exponent: usize) -> usize {
    let mut value = 1usize;
    let mut factor = base.min(cap);
    while exponent != 0 {
        if exponent & 1 != 0 {
            value = value.saturating_mul(factor).min(cap);
        }
        exponent >>= 1;
        if exponent != 0 {
            factor = factor.saturating_mul(factor).min(cap);
        }
    }
    value
}
fn height(arena: &Arena, ty: Id, cap: usize, depth: usize) -> Result<usize> {
    if depth > 128 {
        return Err(fail("finite type height depth"));
    }
    let fields = signature(arena, ty)?;
    if kind(arena, fields[0])? == "relation" {
        Ok(power(
            cap,
            arena.items(fields[2])?.len(),
            index(arena, fields[1])?,
        ))
    } else {
        Ok(cardinality(arena, fields[1], cap, depth + 1)?
            .saturating_mul(height(arena, fields[2], cap, depth + 1)?)
            .min(cap))
    }
}
fn cardinality(arena: &Arena, ty: Id, cap: usize, depth: usize) -> Result<usize> {
    if depth > 128 {
        return Err(fail("finite type cardinality depth"));
    }
    let fields = signature(arena, ty)?;
    if kind(arena, fields[0])? == "relation" {
        Ok(power(cap, 2, height(arena, ty, cap, depth + 1)?))
    } else {
        Ok(power(
            cap,
            cardinality(arena, fields[2], cap, depth + 1)?,
            cardinality(arena, fields[1], cap, depth + 1)?,
        ))
    }
}
