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
