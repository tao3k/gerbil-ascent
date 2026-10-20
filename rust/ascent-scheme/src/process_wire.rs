//! Private, versioned binary packets between exec-isolated owners; never JSON.
use bincode::Options;
use gerbil_ascent::{Data, Result};
use serde::{Deserialize, Serialize};
use std::io::{Read, Write};
#[derive(Serialize, Deserialize)]
pub(crate) enum Frame {
    Ready {
        protocol: u32,
        pid: u32,
        processors: u32,
        domain: u64,
        identity: Data,
    },
    Request(Data),
    Entered,
    Reply {
        value: Result<Data>,
        elapsed_ns: u64,
    },
    Checkpoint {
        id: i64,
        work: i64,
        facts: i64,
    },
    Decision(i32),
}
pub(crate) fn send(stream: &mut impl Write, value: &Frame) -> std::io::Result<()> {
    let mut bytes = Vec::with_capacity(256);
    bytes.extend_from_slice(&[0; 8]);
    bincode::DefaultOptions::new()
        .with_fixint_encoding()
        .serialize_into(&mut bytes, value)
        .map_err(std::io::Error::other)?;
    let length = u64::try_from(bytes.len() - 8).map_err(std::io::Error::other)?;
    bytes[..8].copy_from_slice(&length.to_le_bytes());
    stream.write_all(&bytes)
}
pub(crate) fn receive(stream: &mut impl Read) -> std::io::Result<Frame> {
    let mut header = [0; 8];
    stream.read_exact(&mut header)?;
    let length = usize::try_from(u64::from_le_bytes(header)).map_err(std::io::Error::other)?;
    let mut bytes = Vec::new();
    bytes
        .try_reserve_exact(length)
        .map_err(std::io::Error::other)?;
    bytes.resize(length, 0);
    stream.read_exact(&mut bytes)?;
    bincode::DefaultOptions::new()
        .with_fixint_encoding()
        .with_limit(u64::try_from(length).map_err(std::io::Error::other)?)
        .reject_trailing_bytes()
        .deserialize(&bytes)
        .map_err(std::io::Error::other)
}

#[cfg(test)]
#[path = "../tests/unit/process_wire.rs"]
mod tests;
