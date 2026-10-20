use crate::process_wire::{Frame, receive, send};
use gerbil_ascent::{Data, Error};
#[test]
fn binary_roundtrip_preserves_bigints_nul_real_bits_and_every_typed_failure() {
    let value = Data::List(vec![
        Data::Null,
        Data::Bool(false),
        Data::Integer(-(num_bigint::BigInt::from(1u8) << 4096usize)),
        Data::Real(0x7ff8_0000_0000_0042),
        Data::from("\0typed 🦀"),
        Data::object([("key", Data::from(17usize))]),
    ]);
    let mut bytes = Vec::new();
    send(&mut bytes, &Frame::Request(value.clone())).unwrap();
    let Frame::Request(decoded) = receive(&mut bytes.as_slice()).unwrap() else {
        panic!("request required");
    };
    assert_eq!(decoded, value);
    for error in [
        Error::InvalidProgram("source".into()),
        Error::InvalidUpdate("update".into()),
        Error::Evaluation("eval".into()),
        Error::FactLimit,
        Error::SourceFactLimit,
        Error::DerivedFactLimit,
        Error::OutputFactLimit,
        Error::Closed,
        Error::StateLimit,
        Error::Timeout,
        Error::Canceled,
    ] {
        let mut bytes = Vec::new();
        send(
            &mut bytes,
            &Frame::Reply {
                value: Err(error.clone()),
                elapsed_ns: 1,
            },
        )
        .unwrap();
        let Frame::Reply { value, .. } = receive(&mut bytes.as_slice()).unwrap() else {
            panic!("reply required");
        };
        assert_eq!(value, Err(error));
    }
}
#[test]
fn partial_or_extended_binary_packet_is_never_a_complete_reply() {
    let mut bytes = Vec::new();
    send(
        &mut bytes,
        &Frame::Reply {
            value: Ok(Data::Bool(true)),
            elapsed_ns: 1,
        },
    )
    .unwrap();
    for length in 0..bytes.len() {
        assert!(receive(&mut &bytes[..length]).is_err());
    }
    bytes.push(0);
    let length = u64::try_from(bytes.len() - 8).unwrap();
    bytes[..8].copy_from_slice(&length.to_le_bytes());
    assert!(receive(&mut bytes.as_slice()).is_err());
}

#[test]
fn control_packets_keep_the_generated_codec_and_buffer_boundaries() {
    use bincode::Options;
    for frame in [
        Frame::Entered {
            shared_checkpoints: false,
        },
        Frame::Entered {
            shared_checkpoints: true,
        },
        Frame::Checkpoint {
            id: i64::MAX,
            work: -3,
            facts: i64::MIN,
        },
        Frame::Decision(5),
    ] {
        let payload = bincode::DefaultOptions::new()
            .with_fixint_encoding()
            .serialize(&frame)
            .unwrap();
        let mut expected = u64::try_from(payload.len()).unwrap().to_le_bytes().to_vec();
        expected.extend(payload);
        let mut actual = Vec::new();
        send(&mut actual, &frame).unwrap();
        assert_eq!(actual, expected);
    }
    for size in [111, 112, 113, 4096] {
        let value = Data::from("x".repeat(size));
        let mut bytes = Vec::new();
        send(&mut bytes, &Frame::Request(value.clone())).unwrap();
        let Frame::Request(decoded) = receive(&mut bytes.as_slice()).unwrap() else {
            panic!("request required");
        };
        assert_eq!(decoded, value);
    }
}
#[test]
fn buffered_packets_do_not_lose_readahead_or_direction_changes() {
    use crate::process_wire::Connection;
    use std::os::unix::net::UnixStream;
    let (left, right) = UnixStream::pair().unwrap();
    let mut writer = Connection::new(left);
    let mut reader = Connection::new(right);
    for id in 0..32 {
        writer
            .send(&Frame::Checkpoint {
                id,
                work: id,
                facts: 0,
            })
            .unwrap();
    }
    for expected in 0..32 {
        let Frame::Checkpoint { id, work, facts } = reader.receive().unwrap() else {
            panic!("checkpoint required");
        };
        assert_eq!((id, work, facts), (expected, expected, 0));
        reader.send(&Frame::Decision(0)).unwrap();
        assert!(matches!(writer.receive().unwrap(), Frame::Decision(0)));
    }
}

#[test]
fn checkpoint_liveness_detects_eof_without_consuming_a_pending_frame() {
    use crate::process_wire::Connection;
    let (first, second) = std::os::unix::net::UnixStream::pair().unwrap();
    let mut reader = Connection::new(first);
    let mut writer = Connection::new(second);
    assert!(!reader.peer_closed().unwrap());
    writer.send(&Frame::Decision(0)).unwrap();
    assert!(!reader.peer_closed().unwrap());
    assert!(matches!(reader.receive().unwrap(), Frame::Decision(0)));
    drop(writer);
    assert!(reader.peer_closed().unwrap());
}
