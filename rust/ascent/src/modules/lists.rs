//! Bounded Scheme list operations preserve structural equality and ordinary short circuiting.
use super::{
    evaluation::Evaluation,
    objects::{Id, Object, fail},
};
use crate::Result;
impl Evaluation<'_> {
    pub(super) fn list_algorithms(
        &mut self,
        name: &str,
        args: &[Id],
        depth: usize,
    ) -> Result<Vec<Id>> {
        match name {
            "append" => self.append_lists(args),
            "member" => self.member_list(args),
            "assq" | "assoc" => self.association(name, args),
            "andmap" | "ormap" => self.quantified_list(name, args, depth),
            _ => Err(fail("unknown list operation")),
        }
    }
    pub(super) fn mapped_lists(
        &mut self,
        name: &str,
        args: &[Id],
        depth: usize,
    ) -> Result<Vec<Id>> {
        if args.len() < 2 {
            return Err(fail("map requires procedure and lists"));
        }
        let lists = args[1..]
            .iter()
            .map(|id| self.arena.items(*id))
            .collect::<Result<Vec<_>>>()?;
        let len = lists[0].len();
        if lists.iter().any(|list| list.len() != len) {
            return Err(fail("map list lengths differ"));
        }
        if name == "for-each" {
            (0..len).try_for_each(|i| {
                self.apply(
                    args[0],
                    &lists.iter().map(|list| list[i]).collect::<Vec<_>>(),
                    depth + 1,
                )
                .map(|_| ())
            })?;
            return self.arena.add(Object::Void).map(|id| vec![id]);
        }
        let out = (0..len)
            .map(|i| {
                let values = self.apply(
                    args[0],
                    &lists.iter().map(|list| list[i]).collect::<Vec<_>>(),
                    depth + 1,
                )?;
                match values.as_slice() {
                    [value] => Ok(*value),
                    _ => Err(fail("map requires single return value")),
                }
            })
            .collect::<Result<Vec<_>>>()?;
        self.arena.list(&out).map(|id| vec![id])
    }

    fn append_lists(&mut self, args: &[Id]) -> Result<Vec<Id>> {
        let Some((last, heads)) = args.split_last() else {
            return self.arena.list(&[]).map(|id| vec![id]);
        };
        let mut values = Vec::new();
        for root in heads {
            values.extend(self.arena.items(*root)?);
        }
        let mut tail = *last;
        for value in values.into_iter().rev() {
            tail = self.arena.add(Object::Pair(value, tail))?;
        }
        Ok(vec![tail])
    }
    fn association(&mut self, name: &str, args: &[Id]) -> Result<Vec<Id>> {
        let [key, list] = args else {
            return Err(fail("association arity"));
        };
        for pair in self.arena.items(*list)? {
            let Object::Pair(candidate, _) = self.arena.get(pair)? else {
                return Err(fail("association requires pairs"));
            };
            if if name == "assq" {
                *candidate == *key
            } else {
                self.equal(*candidate, *key, 0)?
            } {
                return Ok(vec![pair]);
            }
        }
        self.arena.add(Object::Boolean(false)).map(|id| vec![id])
    }
    fn member_list(&mut self, args: &[Id]) -> Result<Vec<Id>> {
        let [value, list] = args else {
            return Err(fail("member arity"));
        };
        let mut tail = *list;
        for _ in 0..1_000_000 {
            let (head, next) = match self.arena.get(tail)? {
                Object::Null => return self.arena.add(Object::Boolean(false)).map(|id| vec![id]),
                Object::Pair(head, next) => (*head, *next),
                _ => return Err(fail("member requires a proper list")),
            };
            if self.equal(*value, head, 0)? {
                return Ok(vec![tail]);
            }
            tail = next;
        }
        Err(fail("member traversal bound"))
    }
    fn quantified_list(&mut self, name: &str, args: &[Id], depth: usize) -> Result<Vec<Id>> {
        let [procedure, list] = args else {
            return Err(fail("list quantifier arity"));
        };
        let all = name == "andmap";
        let mut result = self.arena.add(Object::Boolean(all))?;
        for item in self.arena.items(*list)? {
            let values = self.apply(*procedure, &[item], depth + 1)?;
            let [value] = values.as_slice() else {
                return Err(fail("single predicate result required"));
            };
            result = *value;
            let truth = !matches!(self.arena.get(result)?, Object::Boolean(false));
            if truth != all {
                break;
            }
        }
        Ok(vec![result])
    }
}
