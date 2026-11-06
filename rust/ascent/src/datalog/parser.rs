//! Relational surface forms lower to the same typed catalog as native Scheme DSL.
use super::lexer::{Token, tokens};
use crate::{Data, Result, invalid_data as invalid};
pub(super) fn rules(source: &str, typed: bool) -> Result<Vec<Data>> {
    let mut parser = Parser {
        tokens: tokens(source)?,
        position: 0,
        typed,
    };
    let mut rules = Vec::new();
    parser.ends();
    while parser.peek().is_some() {
        let head = parser.atom()?;
        if head.field("not")?.boolean()? {
            return Err(invalid("negative rule head"));
        }
        parser.expect(&Token::Rule)?;
        let body = parser.conjunction()?;
        if parser.peek().is_some() && parser.peek() != Some(&Token::End) {
            return Err(invalid("expected one relational rule"));
        }
        parser.ends();
        rules.push(Data::object([
            ("head", Data::List(vec![head])),
            ("body", Data::List(body)),
        ]));
    }
    Ok(rules)
}
pub(super) fn query(source: &str) -> Result<Data> {
    let mut parser = Parser {
        tokens: tokens(source)?,
        position: 0,
        typed: true,
    };
    let atom = parser.atom()?;
    parser.ends();
    if parser.peek().is_some() {
        return Err(invalid("query must be one relational atom"));
    }
    Ok(atom)
}
struct Parser {
    tokens: Vec<Token>,
    position: usize,
    typed: bool,
}
impl Parser {
    fn peek(&self) -> Option<&Token> {
        self.tokens.get(self.position)
    }
    fn take(&mut self) -> Result<Token> {
        let value = self
            .peek()
            .cloned()
            .ok_or_else(|| invalid("incomplete Datalog expression"))?;
        self.position += 1;
        Ok(value)
    }
    fn eat(&mut self, token: &Token) -> bool {
        if self.peek() == Some(token) {
            self.position += 1;
            true
        } else {
            false
        }
    }
    fn expect(&mut self, token: &Token) -> Result<()> {
        if self.eat(token) {
            Ok(())
        } else {
            Err(invalid("unexpected Datalog expression shape"))
        }
    }
    fn ends(&mut self) {
        while self.eat(&Token::End) {}
    }
    fn name(&mut self) -> Result<String> {
        let Token::Name(name) = self.take()? else {
            return Err(invalid("Datalog relation name required"));
        };
        Ok(name)
    }
    fn text(&mut self) -> Result<String> {
        let Token::Text(text) = self.take()? else {
            return Err(invalid("literal operator name required"));
        };
        Ok(text)
    }
    fn term(&mut self) -> Result<Data> {
        let value = match self.take()? {
            Token::Name(name) if name == "True" => Data::Bool(true),
            Token::Name(name) if name == "False" => Data::Bool(false),
            Token::Name(name) if name.chars().next().is_some_and(char::is_uppercase) => {
                return Ok(Data::object([("var", name.into())]));
            }
            Token::Integer(n) => Data::Integer(n),
            Token::Text(v) => Data::Text(v),
            Token::Minus => {
                let Token::Integer(n) = self.take()? else {
                    return Err(invalid("negative exact integer literal required"));
                };
                Data::Integer(-n)
            }
            _ => return Err(invalid("unsupported Datalog term")),
        };
        Ok(Data::object([("const", value)]))
    }
    fn arguments(&mut self) -> Result<Vec<Data>> {
        let mut out = Vec::new();
        if self.eat(&Token::Close) {
            return Ok(out);
        }
        loop {
            out.push(self.term()?);
            if self.eat(&Token::Close) {
                return Ok(out);
            }
            self.expect(&Token::Comma)?;
        }
    }
    fn atom(&mut self) -> Result<Data> {
        let negative = self.eat(&Token::Not);
        let name = self.name()?;
        self.expect(&Token::Open)?;
        let terms = self.arguments()?;
        Ok(Data::object([
            ("relation", name.into()),
            ("not", negative.into()),
            ("terms", Data::List(terms)),
        ]))
    }
    fn conjunction(&mut self) -> Result<Vec<Data>> {
        let mut out = self.clause()?;
        while self.eat(&Token::And) {
            out.extend(self.clause()?);
        }
        Ok(out)
    }
    fn clause(&mut self) -> Result<Vec<Data>> {
        if self.eat(&Token::Open) {
            let body = self.conjunction()?;
            self.expect(&Token::Close)?;
            return Ok(body);
        }
        if self.typed
            && let Some(Token::Name(name)) = self.peek()
        {
            match name.as_str() {
                "where" => return self.predicate().map(|c| vec![c]),
                "bind" => return self.binding().map(|c| vec![c]),
                "reduce" => return self.reduction().map(|c| vec![c]),
                _ => {}
            }
        }
        if self.peek() == Some(&Token::Not)
            || self.tokens.get(self.position + 1) == Some(&Token::Open)
        {
            return self.atom().map(|a| vec![a]);
        }
        let left = self.term()?;
        self.expect(&Token::Less)?;
        let right = self.term()?;
        Ok(vec![Data::object([
            ("mode", "where".into()),
            ("operator", "<".into()),
            ("terms", Data::List(vec![left, right])),
        ])])
    }
    fn predicate(&mut self) -> Result<Data> {
        self.name()?;
        self.expect(&Token::Open)?;
        let operator = self.text()?;
        let terms = if self.eat(&Token::Close) {
            Vec::new()
        } else {
            self.expect(&Token::Comma)?;
            self.arguments()?
        };
        Ok(Data::object([
            ("mode", "where".into()),
            ("operator", operator.into()),
            ("terms", Data::List(terms)),
        ]))
    }
    fn binding(&mut self) -> Result<Data> {
        self.name()?;
        self.expect(&Token::Open)?;
        let output = self.term()?.field("var")?.clone();
        self.expect(&Token::Comma)?;
        let first = self.term()?;
        let (operator, terms) = if self.eat(&Token::Plus) {
            ("+", vec![first, self.term()?])
        } else {
            ("identity", vec![first])
        };
        self.expect(&Token::Close)?;
        Ok(Data::object([
            ("mode", "compute".into()),
            ("operator", operator.into()),
            ("output", output),
            ("terms", Data::List(terms)),
        ]))
    }
    fn reduction(&mut self) -> Result<Data> {
        self.name()?;
        self.expect(&Token::Open)?;
        let output = self.term()?.field("var")?.clone();
        self.expect(&Token::Comma)?;
        let operator = self.text()?;
        self.expect(&Token::Comma)?;
        let atom = self.atom()?;
        if atom.field("not")?.boolean()? {
            return Err(invalid("negative reduction target"));
        }
        let mut inputs = Vec::new();
        while self.eat(&Token::Comma) {
            inputs.push(self.term()?.field("var")?.clone());
        }
        self.expect(&Token::Close)?;
        Ok(Data::object([
            ("mode", "reduce".into()),
            ("operator", operator.into()),
            ("output", output),
            ("terms", atom.field("terms")?.clone()),
            ("relation", atom.field("relation")?.clone()),
            ("inputs", Data::List(inputs)),
        ]))
    }
}
