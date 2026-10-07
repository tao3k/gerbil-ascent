// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
use super::pipe_capture::capture;
use std::collections::VecDeque;
use std::io::{self, Read};

enum Event {
    Bytes(Vec<u8>),
    Error(io::ErrorKind),
    Eof,
}
struct Script(VecDeque<Event>);
impl Read for Script {
    fn read(&mut self, target: &mut [u8]) -> io::Result<usize> {
        match self.0.pop_front().expect("complete read script") {
            Event::Bytes(bytes) => {
                target[..bytes.len()].copy_from_slice(&bytes);
                Ok(bytes.len())
            }
            Event::Error(kind) => Err(io::Error::from(kind)),
            Event::Eof => Ok(0),
        }
    }
}

#[test]
fn interruptions_preserve_utf8_split_chunks_and_only_bytes_advance_progress() {
    let mut progress = Vec::new();
    let reader = Script(VecDeque::from([
        Event::Error(io::ErrorKind::Interrupted),
        Event::Bytes(vec![0xe4]),
        Event::Error(io::ErrorKind::Interrupted),
        Event::Bytes(vec![0xb8, 0xad, b'\n']),
        Event::Error(io::ErrorKind::Interrupted),
        Event::Eof,
    ]));
    let result = capture(reader, |count| progress.push(count));
    assert!(result.error.is_none());
    assert_eq!(
        String::from_utf8(result.bytes)
            .unwrap()
            .chars()
            .map(u32::from)
            .collect::<Vec<_>>(),
        [0x4e2d, 10]
    );
    assert_eq!(progress, [1, 4]);
}

#[test]
fn terminal_failure_preserves_partial_rows_and_is_not_successful_eof() {
    let mut progress = Vec::new();
    let reader = Script(VecDeque::from([
        Event::Bytes(b"row\t1\n".to_vec()),
        Event::Error(io::ErrorKind::BrokenPipe),
    ]));
    let result = capture(reader, |count| progress.push(count));
    assert_eq!(result.bytes, b"row\t1\n");
    assert_eq!(
        result.error.expect("reject incomplete stream").kind(),
        io::ErrorKind::BrokenPipe
    );
    assert_eq!(progress, [6]);
}

#[test]
fn empty_eof_is_complete_without_inventing_progress() {
    let result = capture(Script(VecDeque::from([Event::Eof])), |_| {
        panic!("no bytes read")
    });
    assert!(result.bytes.is_empty());
    assert!(result.error.is_none());
}

#[test]
fn panic_cause_is_retained_outside_shared_stderr() {
    super::install_panic_receipt();
    let result = std::thread::spawn(|| panic!("CONTROLLED-PANIC receipt witness")).join();
    assert!(result.is_err());
    let saved = std::fs::read_to_string(super::panic_receipt_path()).expect("retained panic cause");
    assert!(saved.contains("CONTROLLED-PANIC receipt witness"));
}
