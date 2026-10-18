//! Clue exchange over the existing declarative Session, without a consumer VM.
use crate::{Cancellation, Data, Engine, FactLimits, Limits, Result, Row, SourceSession, Value};
use std::collections::{BTreeMap, BTreeSet};

pub(super) const RULES: &str = include_str!("../../../../python/src/ascent/clue_query_rules.ss");

/// Source-bound observations and untrusted hypotheses share query rules, not authority.
/// The host supplies source attestations; this owner never executes or admits work.
pub struct ClueExchange {
    pub(super) engine: Engine,
    pub(super) facts: BTreeMap<String, Vec<Row>>,
    pub(super) identity: String,
    session: SourceSession,
}

pub(super) fn invalid(message: &str) -> crate::Error {
    crate::invalid_data(message)
}

pub(super) fn rows(value: &Data) -> Result<Vec<Row>> {
    value
        .list()?
        .iter()
        .map(|row| {
            row.list()?
                .iter()
                .map(|cell| Ok(Value::from(cell.text()?)))
                .collect::<Result<Vec<_>>>()
                .map(Row::from)
        })
        .collect()
}

pub(super) fn data_rows(rows: &[Row]) -> Result<Data> {
    Ok(Data::List(
        rows.iter()
            .map(|row| {
                Ok(Data::List(
                    row.iter()
                        .map(|cell| match cell {
                            Value::Text(text) => Ok(Data::from(text.as_ref())),
                            _ => Err(invalid("Clue relations require text cells")),
                        })
                        .collect::<Result<_>>()?,
                ))
            })
            .collect::<Result<_>>()?,
    ))
}

pub(super) fn evaluate(
    session: &mut SourceSession,
    facts: BTreeMap<String, Vec<Row>>,
    limits: &Limits,
    cancel: &Cancellation,
) -> Result<BTreeMap<String, Vec<Row>>> {
    session.replace(facts, limits, cancel)?;
    let result = session.run(None, limits, cancel)?;
    session.result(result.result_handle)?.close();
    if !result.complete {
        return Err(invalid("incomplete Clue evaluation"));
    }
    Ok(result.relations)
}

impl ClueExchange {
    pub(super) fn check(&self) -> Result<()> {
        self.engine.check()?;
        if self.session.is_closed() {
            Err(crate::Error::Closed)
        } else {
            Ok(())
        }
    }

    /// Release the Session; detached reads remain data, not live authority.
    pub fn close(&mut self) {
        self.session.close();
    }

    /// Partial vocabulary for discovery, never an admissible-question whitelist.
    /// # Errors
    /// Rejects invalid retained cell types.
    pub fn inventory(&self) -> Result<Data> {
        self.check()?;
        let factors: BTreeSet<_> = self.facts["factor"]
            .iter()
            .map(|row| Row::from(vec![row[2].clone(), row[3].clone()]))
            .collect();
        let claims: BTreeSet<_> = self.facts["clue"]
            .iter()
            .map(|row| Row::from(vec![row[2].clone()]))
            .collect();
        Ok(Data::object([
            (
                "factors",
                data_rows(&factors.into_iter().collect::<Vec<_>>())?,
            ),
            (
                "claims",
                data_rows(&claims.into_iter().collect::<Vec<_>>())?,
            ),
            ("inventoryComplete", false.into()),
        ]))
    }
    /// Project trusted host facts with caller-owned Scheme declarations.
    /// `attestations` maps source labels to the host-checked current content digest.
    /// Neither Agent hints nor projected hypotheses can attest observations.
    /// # Errors
    /// Rejects malformed declarations, unbound sources and ambiguous clue identities.
    pub fn new(
        engine: &Engine,
        sources: &[&str],
        constructor: &str,
        supplied: &Data,
        attestations: &Data,
        limits: &Limits,
        cancel: &Cancellation,
    ) -> Result<Self> {
        let mut projection =
            engine.open_evidence_sources(sources, Some(constructor), FactLimits::default())?;
        let inputs = supplied
            .map()?
            .iter()
            .map(|(name, value)| Ok((name.clone(), rows(value)?)))
            .collect::<Result<_>>()?;
        let projected = evaluate(&mut projection, inputs, limits, cancel)?;
        let mut facts = BTreeMap::new();
        for name in ["clue", "factor", "link"] {
            facts.insert(
                name.into(),
                projected
                    .get(name)
                    .ok_or_else(|| invalid("projection requires clue, factor and link outputs"))?
                    .clone(),
            );
        }
        let mut ids = BTreeSet::new();
        let mut identities = BTreeSet::new();
        let mut attested = Vec::new();
        for row in &facts["clue"] {
            let packet = data_rows(std::slice::from_ref(row))?;
            let fields = packet.list()?[0].list()?;
            if fields.len() != 6 || !ids.insert(fields[0].identity()?.to_owned()) {
                return Err(invalid("unique six-field clues required"));
            }
            let id = fields[0].text()?;
            let digest = fields[1].identity()?;
            fields[2].identity()?;
            if !matches!(fields[3].text()?, "support" | "counter") {
                return Err(invalid("unknown clue polarity"));
            }
            match fields[4].text()? {
                "observation" => {
                    let source = fields[5].identity()?;
                    if attestations.get(source).map(Data::text).transpose()? != Some(digest) {
                        return Err(invalid(
                            "observation does not match host source attestation",
                        ));
                    }
                    let receipt =
                        Data::object([("source", source.into()), ("digest", digest.into())])
                            .digest();
                    attested.push(Row::from(vec![
                        id.into(),
                        digest.into(),
                        receipt.as_str().into(),
                    ]));
                }
                "hypothesis" => {}
                _ => return Err(invalid("unknown clue role")),
            }
            identities.insert((id.to_owned(), digest.to_owned()));
        }
        for (name, arity, offset) in [("factor", 4, 0), ("link", 5, 3)] {
            for row in &facts[name] {
                let packet = data_rows(std::slice::from_ref(row))?;
                let fields = packet.list()?[0].list()?;
                if fields.len() != arity
                    || !identities.contains(&(
                        fields[offset].text()?.into(),
                        fields[offset + 1].text()?.into(),
                    ))
                {
                    return Err(invalid("factor or link lacks its clue identity"));
                }
            }
        }
        facts.insert("attested".into(), attested);
        facts.insert("question".into(), vec![]);
        let identity = Data::object([
            (
                "declarations",
                Data::List(sources.iter().map(|v| Data::from(*v)).collect()),
            ),
            ("constructor", constructor.into()),
            ("facts", supplied.clone()),
            ("attestations", attestations.clone()),
            ("rules", RULES.into()),
        ])
        .digest();
        let session = engine.open_evidence_sources(
            &[RULES],
            Some("make-clue-query-evidence"),
            FactLimits::default(),
        )?;
        Ok(Self {
            engine: engine.clone(),
            facts,
            identity,
            session,
        })
    }

    /// Read exact Agent claims or caller-selected claims. Unknown claims remain visible.
    /// # Errors
    /// Propagates Session limits, cancellation and type failures.
    pub fn read(
        &mut self,
        questions: &[String],
        limits: &Limits,
        cancel: &Cancellation,
    ) -> Result<Data> {
        self.check()?;
        if questions.iter().any(String::is_empty) {
            return Err(invalid("nonempty questions required"));
        }
        let mut facts = self.facts.clone();
        facts.insert(
            "question".into(),
            questions
                .iter()
                .map(|q| Row::from(vec![q.as_str().into()]))
                .collect(),
        );
        let answers = evaluate(&mut self.session, facts, limits, cancel)?;
        let mut result = answers
            .iter()
            .map(|(name, value)| Ok((name.clone(), data_rows(value)?)))
            .collect::<Result<BTreeMap<_, _>>>()?;
        result.insert("sourceIdentity".into(), self.identity.clone().into());
        result.insert(
            "questions".into(),
            Data::List(questions.iter().cloned().map(Data::from).collect()),
        );
        result.insert("executionAuthorized".into(), false.into());
        result.insert("runtimeAdmitted".into(), false.into());
        Ok(Data::Map(result))
    }

    /// Evaluate an application-owned selector, not a Library-mandated navigation policy.
    /// # Errors
    /// Invalid selectors or missing question outputs are rejected, never guessed.
    pub fn select(
        &self,
        sources: &[&str],
        constructor: &str,
        bindings: &Data,
        limits: &Limits,
        cancel: &Cancellation,
    ) -> Result<Data> {
        self.check()?;
        let mut declarations = Vec::with_capacity(sources.len() + 1);
        declarations.push(RULES);
        declarations.extend_from_slice(sources);
        let mut session = self.engine.open_evidence_sources(
            &declarations,
            Some(constructor),
            FactLimits::default(),
        )?;
        let mut facts = BTreeMap::from([
            ("clue".into(), self.facts["clue"].clone()),
            ("factor".into(), self.facts["factor"].clone()),
            ("binding".into(), rows(bindings)?),
            ("link".into(), self.facts["link"].clone()),
            ("attested".into(), self.facts["attested"].clone()),
        ]);
        let sources: BTreeSet<_> = session
            .descriptors()
            .iter()
            .filter(|r| r.source)
            .map(|r| r.name.clone())
            .collect();
        facts.retain(|name, _| sources.contains(name));
        let result = evaluate(&mut session, facts, limits, cancel)?;
        if !result.contains_key("question") {
            return Err(invalid("selector requires question output"));
        }
        Ok(Data::Map(
            result
                .iter()
                .map(|(k, v)| Ok((k.clone(), data_rows(v)?)))
                .collect::<Result<_>>()?,
        ))
    }

    /// Agent hypotheses are immutable, never observation receipts. No factor vocabulary is closed.
    /// # Errors
    /// Reusing an id or changing its body is rejected atomically.
    pub fn submit(&mut self, hypotheses: &Data) -> Result<()> {
        self.check()?;
        let mut candidate = self.facts.clone();
        let mut ids: BTreeSet<String> = candidate["clue"]
            .iter()
            .map(|row| match &row[0] {
                Value::Text(text) => text.to_string(),
                _ => unreachable!(),
            })
            .collect();
        for hint in hypotheses.list()? {
            if hint.map()?.keys().any(|key| {
                !matches!(
                    key.as_str(),
                    "id" | "claim" | "polarity" | "source" | "factors"
                )
            }) {
                return Err(invalid("hypotheses cannot supply authority fields"));
            }
            let id = hint.field("id")?.identity()?;
            if !ids.insert(id.into()) {
                return Err(invalid("duplicate clue identity"));
            }
            let claim = hint.field("claim")?.identity()?;
            let polarity = hint.field("polarity")?.text()?;
            if !matches!(polarity, "support" | "counter") {
                return Err(invalid("unknown clue polarity"));
            }
            let source = hint.field("source")?.identity()?;
            let digest = hint.digest();
            candidate
                .entry("clue".into())
                .or_default()
                .push(Row::from(vec![
                    id.into(),
                    digest.as_str().into(),
                    claim.into(),
                    polarity.into(),
                    "hypothesis".into(),
                    source.into(),
                ]));
            if let Some(factors) = hint.get("factors") {
                for pair in factors.list()? {
                    let pair = pair.list()?;
                    if pair.len() != 2 {
                        return Err(invalid("factor name/value pair required"));
                    }
                    candidate
                        .entry("factor".into())
                        .or_default()
                        .push(Row::from(vec![
                            id.into(),
                            digest.as_str().into(),
                            pair[0].identity()?.into(),
                            pair[1].text()?.into(),
                        ]));
                }
            }
        }
        self.facts = candidate;
        Ok(())
    }

    /// Compose independent caller projections without sharing consumer code.
    /// # Errors
    /// Identity collisions reject the whole addition; observations are re-attested.
    pub fn include(&mut self, other: Self) -> Result<()> {
        self.check()?;
        other.check()?;
        let current: BTreeSet<_> = self.facts["clue"].iter().map(|row| &row[0]).collect();
        if other.facts["clue"]
            .iter()
            .any(|row| current.contains(&row[0]))
        {
            return Err(invalid("clue identity collision between projections"));
        }
        let identity =
            Data::List(vec![self.identity.clone().into(), other.identity.into()]).digest();
        for name in ["clue", "factor", "link", "attested"] {
            self.facts
                .entry(name.into())
                .or_default()
                .extend(other.facts[name].iter().cloned());
        }
        self.identity = identity;
        Ok(())
    }

    /// Bind and read through a caller's selector in one progressive exchange.
    /// # Errors
    /// Missing or malformed selector question projections are not silently ignored.
    pub fn read_selected(
        &mut self,
        sources: &[&str],
        constructor: &str,
        bindings: &Data,
        limits: &Limits,
        cancel: &Cancellation,
    ) -> Result<Data> {
        let selection = self.select(sources, constructor, bindings, limits, cancel)?;
        let questions = selection
            .field("question")?
            .list()?
            .iter()
            .map(|row| {
                let row = row.list()?;
                if row.len() != 1 {
                    return Err(invalid("selector question arity must be one"));
                }
                Ok(row[0].identity()?.to_owned())
            })
            .collect::<Result<Vec<_>>>()?;
        let mut result = self.read(&questions, limits, cancel)?.map()?.clone();
        result.insert("selection".into(), selection);
        result.insert(
            "selectorIdentity".into(),
            Data::object([
                ("schema", Data::from(RULES).digest().into()),
                (
                    "declarations",
                    Data::List(sources.iter().map(|source| Data::from(*source)).collect()),
                ),
                ("constructor", constructor.into()),
                ("bindings", bindings.clone()),
            ])
            .digest()
            .into(),
        );
        Ok(Data::Map(result))
    }
}

/// Decode the existing Clue request fields using the Library's bounded datum
/// reader. This transports data, never evaluates a Scheme form or a query rule.
/// # Errors
/// Rejects malformed, duplicate, unknown or executable request data.
pub fn read_clue_request(source: &str) -> Result<Data> {
    use crate::source::{Datum, read_datum};
    fn value(datum: Datum) -> Result<Data> {
        match datum {
            Datum::Text(text) => Ok(Data::Text(text)),
            Datum::Atom(text) => match text.as_str() {
                "#t" => Ok(Data::Bool(true)),
                "#f" => Ok(Data::Bool(false)),
                _ => text
                    .parse()
                    .map(Data::Integer)
                    .map_err(|_| invalid("inert Clue request value required")),
            },
            Datum::List(items) => items
                .into_iter()
                .map(value)
                .collect::<Result<Vec<_>>>()
                .map(Data::List),
            Datum::Vector(_) => Err(invalid("Clue request lists required")),
        }
    }
    let Datum::List(fields) = read_datum(source)? else {
        return Err(invalid("Clue request association list required"));
    };
    let mut request = std::collections::BTreeMap::new();
    for field in fields {
        let Datum::List(mut pair) = field else {
            return Err(invalid("Clue request key/value pair required"));
        };
        if pair.len() != 2 {
            return Err(invalid("Clue request key/value pair required"));
        }
        let data = value(pair.pop().unwrap())?;
        let (Datum::Atom(key) | Datum::Text(key)) = pair.pop().unwrap() else {
            return Err(invalid("Clue request field name required"));
        };
        if !matches!(
            key.as_str(),
            "bindings"
                | "questions"
                | "expand"
                | "checkpoint"
                | "displayBytes"
                | "selector"
                | "constructor"
        ) {
            return Err(invalid("unknown Clue request field"));
        }
        match key.as_str() {
            "bindings" => {
                for row in data.list()? {
                    let pair = row.list()?;
                    if pair.len() != 2 {
                        return Err(invalid("binding name/value pair required"));
                    }
                    pair[0].text()?;
                    pair[1].text()?;
                }
            }
            "questions" | "expand" => {
                for item in data.list()? {
                    item.text()?;
                }
            }
            "checkpoint" | "selector" | "constructor" => {
                data.text()?;
            }
            "displayBytes" if !matches!(&data, Data::Integer(n) if n > &0.into()) => {
                return Err(invalid("positive displayBytes required"));
            }
            _ => {}
        }
        if request.insert(key, data).is_some() {
            return Err(invalid("duplicate Clue request field"));
        }
    }
    if request.contains_key("constructor") && !request.contains_key("selector") {
        return Err(invalid("constructor requires a caller-written selector"));
    }
    Ok(Data::Map(request))
}

/// Inert Scheme data rendering for Agent-facing exchange; no executable forms.
#[must_use]
pub fn clue_sexpr(value: &Data) -> String {
    match value {
        Data::Null => "()".into(),
        Data::Bool(v) => if *v { "#t" } else { "#f" }.into(),
        Data::Integer(v) => v.to_string(),
        Data::Real(v) => f64::from_bits(*v).to_string(),
        Data::Text(v) => format!(
            "\"{}\"",
            v.replace('\\', "\\\\")
                .replace('"', "\\\"")
                .replace('\n', "\\n")
                .replace('\r', "\\r")
                .replace('\t', "\\t")
        ),
        Data::List(v) => format!(
            "({})",
            v.iter().map(clue_sexpr).collect::<Vec<_>>().join(" ")
        ),
        Data::Map(v) => format!(
            "({})",
            v.iter()
                .map(|(k, v)| format!("({} {})", clue_sexpr(&k.as_str().into()), clue_sexpr(v)))
                .collect::<Vec<_>>()
                .join(" ")
        ),
    }
}
