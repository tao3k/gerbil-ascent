//! Compile the actual decoder source and measure its own allocator boundary.
//! No alternate decoder, VM or Python interpreter implements the candidate.
pub use gerbil_ascent::{Row, Term, Value};
#[path = "../../../ascent/src/execution/values.rs"]
mod owned_values;
use sha2::Digest;
use std::{
    alloc::{GlobalAlloc, Layout, System},
    cell::Cell,
    hint::black_box,
    mem::size_of,
};

#[derive(Clone, Copy, Debug, Default)]
struct Cost {
    calls: usize,
    bytes: usize,
}
thread_local! {
    static COST: Cell<Option<Cost>> = const { Cell::new(None) };
}
fn record(bytes: usize) {
    let _ = COST.try_with(|slot| {
        if let Some(mut cost) = slot.get() {
            cost.calls = cost.calls.saturating_add(1);
            cost.bytes = cost.bytes.saturating_add(bytes);
            slot.set(Some(cost));
        }
    });
}
struct Allocator;
// SAFETY: every allocation operation delegates unchanged pointers, layouts and
// sizes to System. Recording uses only const thread-local Copy cells and cannot
// allocate, call the VM or unwind from an allocator callback.
unsafe impl GlobalAlloc for Allocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        record(layout.size());
        // SAFETY: GlobalAlloc supplied the allocation layout unchanged.
        unsafe { System.alloc(layout) }
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        record(layout.size());
        // SAFETY: System preserves the requested layout and zeroing contract.
        unsafe { System.alloc_zeroed(layout) }
    }
    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        // SAFETY: the allocation's original pointer and layout are unchanged.
        unsafe { System.dealloc(pointer, layout) }
    }
    unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        record(size);
        // SAFETY: GlobalAlloc's original allocation and requested size pass through.
        unsafe { System.realloc(pointer, layout, size) }
    }
}
#[global_allocator]
static ALLOCATOR: Allocator = Allocator;
struct Reset;
impl Drop for Reset {
    fn drop(&mut self) {
        COST.with(|slot| slot.set(None));
    }
}
fn measured(action: impl FnOnce() -> Row) -> (Row, Cost) {
    COST.with(|slot| {
        assert!(slot.get().is_none(), "nested allocation scope");
        slot.set(Some(Cost::default()));
    });
    let reset = Reset;
    let row = action();
    let cost = COST.with(|slot| slot.take().expect("active allocation scope"));
    drop(reset);
    (row, cost)
}

#[test]
fn actual_decoder_eliminates_only_the_temporary_row_allocation() {
    let palette = [
        Value::from(0),
        Value::Boolean(false),
        Value::from("same"),
        Value::Symbol("same".into()),
        Value::Integer(num_bigint::BigInt::from(1_u8) << 320_usize),
        Value::number("3/2").unwrap(),
        Value::inexact(-0.0).unwrap(),
    ];
    let mut values = owned_values::Values::default();
    let literal = values.pattern(Term::Literal(Value::from(7)));
    assert!(literal.is_literal());
    assert!(!literal.is_wildcard());
    assert_eq!(
        values.scalar(literal.literal_value().owned()),
        &Value::from(7)
    );
    assert_eq!(values.pattern(Term::Variable(3)).variable_index(), 3);
    assert!(values.pattern(Term::Wildcard).is_wildcard());
    let mut retained = Vec::new();
    let mut removed_calls = 0;
    let mut removed_bytes = 0;
    for width in 0..=32 {
        let expected: Vec<_> = (0..width)
            .map(|column| palette[column % palette.len()].clone())
            .collect();
        let cells: owned_values::Row = expected
            .iter()
            .map(|value| values.intern(value))
            .collect::<Vec<_>>()
            .into();
        let cells = black_box(cells.as_ref());
        let (actual, direct) = measured(|| values.decode(cells));
        // Frozen pre-change implementation. Both paths clone the same cells,
        // including heap integers and frozen values, in precisely the same order.
        let (reference, staged) = measured(|| {
            cells
                .iter()
                .map(|cell| values.scalar(*cell).clone())
                .collect::<Vec<_>>()
                .into()
        });
        assert_eq!(&*actual, expected);
        assert_eq!(actual, reference);
        assert_eq!(staged.calls, direct.calls + usize::from(width != 0));
        assert_eq!(staged.bytes, direct.bytes + width * size_of::<Value>());
        removed_calls += staged.calls - direct.calls;
        removed_bytes += staged.bytes - direct.bytes;
        let expected =
            gerbil_ascent::Catalog::observe_rows(std::slice::from_ref(&reference)).unwrap();
        retained.push((actual, expected));
    }
    values.intern(&Value::from("later input"));
    drop(values);
    drop(palette);
    for (actual, expected) in retained {
        assert_eq!(
            gerbil_ascent::Catalog::observe_rows(std::slice::from_ref(&actual)).unwrap(),
            expected
        );
    }
    eprintln!(
        "ROW-COST-OK widths=33 value_bytes={} removed_allocations={} removed_requested_payload_bytes={} decoder_source_sha256={:x}",
        size_of::<Value>(),
        removed_calls,
        removed_bytes,
        sha2::Sha256::digest(include_bytes!("../../../ascent/src/execution/values.rs")),
    );
}
