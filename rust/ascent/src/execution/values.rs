//! Query-owned, injective value codes keep binding copies compact.
use crate::{Term, Value as Scalar};
use std::{collections::HashMap, num::NonZeroUsize, sync::Arc};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub(crate) struct Cell(NonZeroUsize);
impl Cell {
    pub(crate) fn ordinal(self) -> usize {
        self.0.get() - 1
    }
    pub fn owned(self) -> Self {
        self
    }
}
pub(crate) type Row = Arc<[Cell]>;
#[derive(Clone, Default, Debug)]
pub(crate) struct Values {
    codes: HashMap<Scalar, Cell>,
    pub(super) values: Vec<Scalar>,
}
impl Values {
    pub fn intern(&mut self, value: &Scalar) -> Cell {
        let values = &mut self.values;
        *self.codes.entry(value.clone()).or_insert_with(|| {
            // A Vec<Scalar> cannot contain usize::MAX entries: its byte capacity
            // is bounded by isize::MAX, so this nonzero index cannot overflow.
            let cell = Cell(NonZeroUsize::new(values.len() + 1).expect("owned value index"));
            values.push(value.clone());
            cell
        })
    }
    pub fn scalar(&self, cell: Cell) -> &Scalar {
        &self.values[cell.ordinal()]
    }
    // BEGIN GENERATED OWNED ROW
    pub fn decode(&self, row: &[Cell]) -> crate::Row {
        row.iter()
            .map(|cell| self.values[cell.0.get() - 1].clone())
            .collect()
    }
    // END GENERATED OWNED ROW
    pub fn pattern(&mut self, term: Term) -> Pattern {
        match term {
            Term::Variable(slot) => Pattern::Variable(slot),
            Term::Literal(value) => Pattern::Literal(self.intern(&value)),
            Term::Wildcard => Pattern::Wildcard,
        }
    }
}
#[derive(Clone, Copy, Debug)]
pub(crate) enum Pattern {
    Variable(u32),
    Literal(Cell),
    Wildcard,
}
impl Pattern {
    pub fn is_literal(&self) -> bool {
        matches!(self, Self::Literal(_))
    }
    pub fn is_wildcard(&self) -> bool {
        matches!(self, Self::Wildcard)
    }
    pub fn literal_value(&self) -> Cell {
        match self {
            Self::Literal(value) => *value,
            _ => unreachable!("generated literal branch"),
        }
    }
    pub fn variable_index(&self) -> usize {
        match self {
            Self::Variable(slot) => *slot as usize,
            _ => unreachable!("generated variable branch"),
        }
    }
}
