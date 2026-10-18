//! Bounded Scheme datum reader for inert runtime rule sources.
use crate::{Error, Result};
use std::iter::Peekable;
use std::str::Chars;

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub(crate) enum Datum {
    Atom(String),
    Text(String),
    List(Vec<Self>),
    Vector(Vec<Self>),
}
pub(super) fn read(text: &str) -> Result<Datum> {
    if text.len() > 65_536 {
        return Err(invalid("rule source byte bound"));
    }
    let mut reader = Reader(text.chars().peekable(), false);
    let datum = reader.datum(0)?;
    reader.space();
    if reader.0.peek().is_some() {
        return Err(invalid("one ASCENT fragment required"));
    }
    Ok(datum)
}
pub(super) fn read_all(text: &str) -> Result<Vec<Datum>> {
    let mut reader = Reader(text.chars().peekable(), false);
    let mut forms = Vec::new();
    loop {
        reader.space();
        if reader.0.peek().is_none() {
            return Ok(forms);
        }
        forms.push(reader.datum(0)?);
    }
}
pub(super) fn invalid(detail: &str) -> Error {
    Error::InvalidProgram(detail.into())
}
struct Reader<'a>(Peekable<Chars<'a>>, bool);
impl Reader<'_> {
    fn space(&mut self) {
        loop {
            while self.0.peek().is_some_and(|c| c.is_whitespace()) {
                self.0.next();
            }
            if self.0.peek() != Some(&';') {
                break;
            }
            for c in self.0.by_ref() {
                if c == '\n' {
                    break;
                }
            }
        }
    }
    fn datum(&mut self, depth: usize) -> Result<Datum> {
        if depth > 128 {
            return Err(invalid("rule source nesting bound"));
        }
        self.space();
        match self.0.next().ok_or_else(|| invalid("missing datum"))? {
            '(' => self.list(')', depth),
            '[' => self.list(']', depth),
            '#' if self.0.peek() == Some(&'(') => {
                self.0.next();
                let Datum::List(items) = self.list(')', depth)? else {
                    unreachable!()
                };
                Ok(Datum::Vector(items))
            }
            ')' | ']' => Err(invalid("unexpected closing delimiter")),
            '\'' => Ok(Datum::List(vec![
                Datum::Atom("quote".into()),
                self.datum(depth + 1)?,
            ])),
            '"' => self.string(),
            first => {
                let mut atom = String::from(first);
                while let Some(c) = self.0.peek().copied() {
                    if c.is_whitespace() || "()[];'\"".contains(c) {
                        break;
                    }
                    atom.push(c);
                    self.0.next();
                }
                if atom.starts_with("#%module-macro-") || atom.starts_with("__ascent_") {
                    return Err(invalid("reserved expansion identifier"));
                }
                if (atom == "." && !self.1)
                    || (atom.contains('|') && !(self.1 && atom.starts_with("#\\")))
                    || (atom.contains('\\') && !(self.1 && atom.starts_with("#\\")))
                {
                    return Err(invalid("unsupported Scheme identifier syntax"));
                }
                Ok(Datum::Atom(atom))
            }
        }
    }
    fn list(&mut self, close: char, depth: usize) -> Result<Datum> {
        let mut items = Vec::new();
        loop {
            self.space();
            if self.0.peek() == Some(&close) {
                self.0.next();
                return Ok(Datum::List(items));
            }
            if items.len() >= 256 {
                return Err(invalid("ASCENT form length bound"));
            }
            items.push(self.datum(depth + 1)?);
        }
    }
    fn string(&mut self) -> Result<Datum> {
        let mut text = String::new();
        loop {
            match self
                .0
                .next()
                .ok_or_else(|| invalid("unterminated string"))?
            {
                '"' => return Ok(Datum::Text(text)),
                '\\' => match self
                    .0
                    .next()
                    .ok_or_else(|| invalid("unterminated escape"))?
                {
                    'n' => text.push('\n'),
                    't' => text.push('\t'),
                    'r' => text.push('\r'),
                    '"' => text.push('"'),
                    '\\' => text.push('\\'),
                    _ => return Err(invalid("unsupported Scheme string escape")),
                },
                c => text.push(c),
            }
        }
    }
}
