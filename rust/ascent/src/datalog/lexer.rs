//! Bounded inert expression tokens; no Python parser, evaluation, imports or attributes.
use crate::{Result, invalid_data as invalid};
use num_bigint::BigInt;
#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) enum Token {
    Name(String),
    Integer(BigInt),
    Text(String),
    Open,
    Close,
    Comma,
    And,
    Not,
    Less,
    Rule,
    Plus,
    Minus,
    End,
}
struct Lexer {
    chars: Vec<char>,
    position: usize,
    depth: usize,
}
pub(super) fn tokens(source: &str) -> Result<Vec<Token>> {
    if source.len() > 1_048_576 {
        return Err(invalid("Datalog source size bound"));
    }
    let mut lexer = Lexer {
        chars: source.chars().collect(),
        position: 0,
        depth: 0,
    };
    let mut out = Vec::new();
    while let Some(token) = lexer.next()? {
        if out.len() >= 262_144 {
            return Err(invalid("Datalog token bound"));
        }
        out.push(token);
    }
    if lexer.depth != 0 {
        return Err(invalid("unclosed Datalog parentheses"));
    }
    Ok(out)
}
impl Lexer {
    fn peek(&self) -> Option<char> {
        self.chars.get(self.position).copied()
    }
    fn take(&mut self) -> Option<char> {
        let value = self.peek()?;
        self.position += 1;
        Some(value)
    }
    fn next(&mut self) -> Result<Option<Token>> {
        while let Some(c) = self.take() {
            match c {
                '\n' | ';' if self.depth == 0 => return Ok(Some(Token::End)),
                c if c.is_whitespace() => {}
                '#' => {
                    while self.peek().is_some_and(|c| c != '\n') {
                        self.position += 1;
                    }
                }
                '(' => {
                    self.depth += 1;
                    if self.depth > 128 {
                        return Err(invalid("Datalog expression depth bound"));
                    }
                    return Ok(Some(Token::Open));
                }
                ')' => {
                    self.depth = self
                        .depth
                        .checked_sub(1)
                        .ok_or_else(|| invalid("unexpected Datalog closing parenthesis"))?;
                    return Ok(Some(Token::Close));
                }
                '\'' | '"' => return self.string(c).map(Token::Text).map(Some),
                c if c.is_ascii_digit() => return self.integer(c).map(Token::Integer).map(Some),
                c if c == '_' || c.is_alphabetic() => return Ok(Some(Token::Name(self.name(c)))),
                '<' => {
                    return Ok(Some(if self.peek() == Some('=') {
                        self.position += 1;
                        Token::Rule
                    } else {
                        Token::Less
                    }));
                }
                ',' => return Ok(Some(Token::Comma)),
                '&' => return Ok(Some(Token::And)),
                '~' => return Ok(Some(Token::Not)),
                '+' => return Ok(Some(Token::Plus)),
                '-' => return Ok(Some(Token::Minus)),
                _ => return Err(invalid("unsupported Datalog token")),
            }
        }
        Ok(None)
    }
    fn name(&mut self, first: char) -> String {
        let mut out = String::from(first);
        while self.peek().is_some_and(|c| c == '_' || c.is_alphanumeric()) {
            out.push(self.take().expect("peeked name character"));
        }
        out
    }
    fn integer(&mut self, first: char) -> Result<BigInt> {
        let mut out = String::from(first);
        while self.peek().is_some_and(|c| c.is_ascii_digit()) {
            if out.len() >= 4096 {
                return Err(invalid("Datalog integer magnitude bound"));
            }
            out.push(self.take().expect("peeked digit"));
        }
        out.parse()
            .map_err(|_| invalid("exact Datalog integer required"))
    }
    fn string(&mut self, quote: char) -> Result<String> {
        let mut out = String::new();
        while let Some(c) = self.take() {
            match c {
                c if c == quote => return Ok(out),
                '\\' => out.push(self.escape()?),
                c => out.push(c),
            }
        }
        Err(invalid("unterminated Datalog string"))
    }
    fn escape(&mut self) -> Result<char> {
        match self
            .take()
            .ok_or_else(|| invalid("unterminated string escape"))?
        {
            'n' => Ok('\n'),
            'r' => Ok('\r'),
            't' => Ok('\t'),
            'b' => Ok('\u{8}'),
            'f' => Ok('\u{c}'),
            '\\' => Ok('\\'),
            '\'' => Ok('\''),
            '"' => Ok('"'),
            'u' => self.unicode(4),
            'U' => self.unicode(8),
            'x' => self.unicode(2),
            _ => Err(invalid("unsupported Datalog string escape")),
        }
    }
    fn unicode(&mut self, width: usize) -> Result<char> {
        let mut value = 0u32;
        for _ in 0..width {
            let digit = self
                .take()
                .and_then(|c| c.to_digit(16))
                .ok_or_else(|| invalid("invalid Unicode escape"))?;
            value = value
                .checked_mul(16)
                .and_then(|v| v.checked_add(digit))
                .ok_or_else(|| invalid("Unicode escape overflow"))?;
        }
        char::from_u32(value).ok_or_else(|| invalid("Unicode scalar required"))
    }
}
