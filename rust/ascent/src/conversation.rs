//! Provider history retains opaque items and enforces atomic, uniquely paired tool responses.
use crate::{Data, Result, invalid_data as invalid};
use std::collections::{BTreeMap, BTreeSet};
/// Opaque nonempty identity supplied by the external provider, never executable authority.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ToolCallId(String);
impl ToolCallId {
    /// # Errors
    /// Rejects empty provider call identities.
    pub fn new(value: &str) -> Result<Self> {
        if value.is_empty() {
            return Err(invalid("tool call identity required"));
        }
        Ok(Self(value.into()))
    }
}
/// Provider observations have no inference or execution authority in the relational engine.
pub struct ResponseHistory {
    items: Vec<Data>,
    pending: BTreeMap<String, Data>,
    seen: BTreeSet<String>,
}
impl ResponseHistory {
    #[must_use]
    pub fn new(question: Data) -> Self {
        Self {
            items: vec![Data::object([
                ("role", "user".into()),
                ("content", question),
            ])],
            pending: BTreeMap::new(),
            seen: BTreeSet::new(),
        }
    }
    /// # Errors
    /// Rejects unpaired tool calls before exposing the next provider input.
    pub fn input(&self) -> Result<Data> {
        self.ready()?;
        Ok(Data::List(self.items.clone()))
    }
    fn ready(&self) -> Result<()> {
        if self.pending.is_empty() {
            Ok(())
        } else {
            Err(invalid("every function call requires a paired output"))
        }
    }
    /// # Errors
    /// Rejects unsupported items and duplicate IDs without changing retained history.
    pub fn append_response(&mut self, response: &Data) -> Result<Data> {
        self.ready()?;
        let output = response.field("output")?.list()?;
        let mut calls = BTreeMap::new();
        let mut ordered = Vec::new();
        for item in output {
            if let Some(id) = tool_call(item)? {
                if self.seen.contains(id) || calls.insert(id.to_string(), item.clone()).is_some() {
                    return Err(invalid("tool call identity must be unique"));
                }
                ordered.push(item.clone());
            }
        }
        self.items.extend_from_slice(output);
        self.seen.extend(calls.keys().cloned());
        self.pending = calls;
        Ok(Data::List(ordered))
    }
    /// # Errors
    /// Rejects unknown/completed calls. JSON is used only for the external provider protocol.
    pub fn append_result(&mut self, call_id: &ToolCallId, result: &Data) -> Result<()> {
        let call_id = call_id.0.as_str();
        if !self.pending.contains_key(call_id) {
            return Err(invalid("unknown or already completed tool call"));
        }
        let output = provider_json(result)?;
        self.items.push(Data::object([
            ("type", "function_call_output".into()),
            ("call_id", call_id.into()),
            ("output", output.into()),
        ]));
        self.pending.remove(call_id);
        Ok(())
    }
    /// # Errors
    /// Rejects feedback while tool responses remain unpaired.
    pub fn append_feedback(&mut self, result: &Data) -> Result<()> {
        self.ready()?;
        let content = provider_json(result)?;
        self.items.push(Data::object([
            ("role", "user".into()),
            ("content", content.into()),
        ]));
        Ok(())
    }
    #[must_use]
    pub fn reasoning_items(&self) -> usize {
        self.items
            .iter()
            .filter(|i| i.get("type") == Some(&Data::Text("reasoning".into())))
            .count()
    }
}
fn tool_call(item: &Data) -> Result<Option<&str>> {
    match item.field("type")?.text()? {
        "function_call" => item.field("call_id")?.identity().map(Some),
        "reasoning" | "message" => Ok(None),
        _ => Err(invalid("unsupported response output item")),
    }
}
/// External provider formatting is separate from typed engine program/result transport.
fn provider_json(value: &Data) -> Result<String> {
    let mut output = String::new();
    json_value(value, &mut output, 0)?;
    Ok(output)
}
fn json_value(value: &Data, out: &mut String, depth: usize) -> Result<()> {
    if depth > 128 {
        return Err(invalid("provider item depth bound"));
    }
    match value {
        Data::Null => out.push_str("null"),
        Data::Bool(v) => out.push_str(if *v { "true" } else { "false" }),
        Data::Integer(v) => out.push_str(&v.to_string()),
        Data::Real(v) => {
            let v = f64::from_bits(*v);
            if !v.is_finite() {
                return Err(invalid("finite provider number required"));
            }
            out.push_str(&v.to_string());
        }
        Data::Text(v) => quoted(v, out),
        Data::List(values) => json_list(values, out, depth + 1)?,
        Data::Map(values) => json_map(values, out, depth + 1)?,
    }
    Ok(())
}
fn json_list(values: &[Data], out: &mut String, depth: usize) -> Result<()> {
    out.push('[');
    for (i, value) in values.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        json_value(value, out, depth)?;
    }
    out.push(']');
    Ok(())
}
fn json_map(values: &BTreeMap<String, Data>, out: &mut String, depth: usize) -> Result<()> {
    out.push('{');
    for (i, (key, value)) in values.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        quoted(key, out);
        out.push(':');
        json_value(value, out, depth)?;
    }
    out.push('}');
    Ok(())
}
fn quoted(value: &str, out: &mut String) {
    use std::fmt::Write;
    out.push('"');
    for c in value.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            c if c < '\u{20}' => {
                write!(out, "\\u{:04x}", u32::from(c)).expect("string output");
            }
            c => out.push(c),
        }
    }
    out.push('"');
}
