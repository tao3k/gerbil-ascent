// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Byte-preserving pipe capture. An interrupted syscall is neither EOF nor
//! progress. A terminal read error retains its partial bytes and rejects capture.
use std::io::{self, Read};

pub(crate) struct Capture {
    pub(crate) bytes: Vec<u8>,
    pub(crate) error: Option<io::Error>,
}

pub(crate) fn capture(mut input: impl Read, mut progress: impl FnMut(usize)) -> Capture {
    let mut bytes = Vec::new();
    let mut chunk = [0u8; 8192];
    loop {
        match input.read(&mut chunk) {
            Ok(0) => return Capture { bytes, error: None },
            Ok(count) => {
                bytes.extend_from_slice(&chunk[..count]);
                progress(bytes.len());
            }
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(error) => {
                return Capture {
                    bytes,
                    error: Some(error),
                };
            }
        }
    }
}
