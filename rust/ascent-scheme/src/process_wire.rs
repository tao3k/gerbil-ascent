//! Private, versioned binary packets between exec-isolated owners; never JSON.
#[path = "process_policy.rs"]
mod policy;
use bincode::Options;
use gerbil_ascent::{Data, Result};
use serde::{Deserialize, Serialize};
use std::{
    io::{BufReader, Cursor, Read, Write},
    os::{fd::AsRawFd, unix::net::UnixStream},
};
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
    Entered {
        shared_checkpoints: bool,
    },
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
/// Buffer bytes, never checkpoint decisions. One received checkpoint still
/// requires its own original controller call and one reply.
pub(crate) struct Connection(BufReader<UnixStream>);
impl Connection {
    pub(crate) fn new(socket: UnixStream) -> Self {
        Self(BufReader::with_capacity(4096, socket))
    }
    pub(crate) fn send(&mut self, frame: &Frame) -> std::io::Result<()> {
        send(self.0.get_mut(), frame)
    }
    pub(crate) fn receive(&mut self) -> std::io::Result<Frame> {
        receive(&mut self.0)
    }
    pub(crate) fn peer_closed(&self) -> std::io::Result<bool> {
        let mut byte = 0_u8;
        // SAFETY: one live borrowed socket and one writable byte. PEEK never
        // consumes framed input; DONTWAIT does not change descriptor flags.
        let count = unsafe {
            libc::recv(
                self.0.get_ref().as_raw_fd(),
                (&raw mut byte).cast(),
                1,
                libc::MSG_PEEK | libc::MSG_DONTWAIT,
            )
        };
        let error = (count < 0).then(std::io::Error::last_os_error);
        let benign = error.as_ref().is_some_and(|error| {
            matches!(
                error.kind(),
                std::io::ErrorKind::WouldBlock | std::io::ErrorKind::Interrupted
            )
        });
        if let Some(closed) = policy::peer_probe(count == 0, count < 0, benign) {
            return Ok(closed);
        }
        if let Some(error) = error {
            return Err(error);
        }
        // Queued bytes alone cannot establish liveness: a closed peer may
        // leave a complete packet behind. Preserve the original hangup/error
        // check in that case. The hot, empty-open case avoids Darwin poll.
        let mut fd = libc::pollfd {
            fd: self.0.get_ref().as_raw_fd(),
            events: libc::POLLIN,
            revents: libc::POLLIN,
        };
        loop {
            // SAFETY: the connection owns this one pollfd throughout the
            // nonblocking call. Interrupted probes retry without consuming data.
            if unsafe { libc::poll(&raw mut fd, 1, 0) } >= 0 {
                return Ok(fd.revents & (libc::POLLHUP | libc::POLLERR | libc::POLLNVAL) != 0);
            }
            let error = std::io::Error::last_os_error();
            if error.kind() != std::io::ErrorKind::Interrupted {
                return Err(error);
            }
        }
    }
    pub(crate) fn shutdown(&self) -> std::io::Result<()> {
        self.0.get_ref().shutdown(std::net::Shutdown::Both)
    }
}
pub(crate) fn send(stream: &mut impl Write, value: &Frame) -> std::io::Result<()> {
    if matches!(
        value,
        Frame::Entered { .. } | Frame::Checkpoint { .. } | Frame::Decision(_)
    ) {
        let mut bytes = [0_u8; 64];
        let mut body = Cursor::new(&mut bytes[8..]);
        bincode::DefaultOptions::new()
            .with_fixint_encoding()
            .serialize_into(&mut body, value)
            .map_err(std::io::Error::other)?;
        let length = body.position();
        bytes[..8].copy_from_slice(&length.to_le_bytes());
        return stream
            .write_all(&bytes[..usize::try_from(length).map_err(std::io::Error::other)? + 8]);
    }
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
    if length <= 128 {
        let mut bytes = [0_u8; 128];
        stream.read_exact(&mut bytes[..length])?;
        return decode(&bytes[..length]);
    }
    let mut bytes = Vec::new();
    bytes
        .try_reserve_exact(length)
        .map_err(std::io::Error::other)?;
    bytes.resize(length, 0);
    stream.read_exact(&mut bytes)?;
    decode(&bytes)
}
fn decode(bytes: &[u8]) -> std::io::Result<Frame> {
    bincode::DefaultOptions::new()
        .with_fixint_encoding()
        .with_limit(u64::try_from(bytes.len()).map_err(std::io::Error::other)?)
        .reject_trailing_bytes()
        .deserialize(bytes)
        .map_err(std::io::Error::other)
}

#[cfg(test)]
#[path = "../tests/unit/process_wire.rs"]
mod tests;

// Test-only last-descriptor ownership barrier against concurrent fork/exec.
// The production peer endpoint is created in its separate worker process.
#[cfg(test)]
pub(crate) static PROCESS_FIXTURE_SETUP: std::sync::Mutex<()> = std::sync::Mutex::new(());
