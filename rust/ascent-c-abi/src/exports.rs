//! Fixed C entry, lifetime transfer and panic containment around existing Core.
use crate::{operations, reachability, transport};
use gerbil_scheme_python::{
    ValueLimits,
    c_abi::{self, RawCallable, RawValue, View},
};
use std::{
    ffi::c_void,
    panic::{AssertUnwindSafe, catch_unwind},
    thread::ThreadId,
};
struct Context {
    owner: ThreadId,
    poisoned: bool,
    core: Core,
}
#[derive(Clone, Copy)]
enum Entry {
    Evidence,
    Reachability,
}
enum Core {
    Evidence(Box<operations::Owner>),
    Reachability(reachability::Owner),
}
impl Core {
    fn trace(&mut self) -> &mut crate::diagnostics::Trace {
        match self {
            Self::Evidence(owner) => &mut owner.trace,
            Self::Reachability(owner) => &mut owner.trace,
        }
    }
    fn invoke(
        &mut self,
        input: &gerbil_ascent::Data,
    ) -> gerbil_ascent::Result<gerbil_ascent::Data> {
        match self {
            Self::Evidence(owner) => owner.invoke(input),
            Self::Reachability(owner) => owner.invoke(input),
        }
    }
}

/// Bind the statically linked fixed producer through the upstream owner adapter.
/// # Errors
/// Rejects invalid captures, failed Core initialization or malformed ABI ownership.
pub fn open(
    input: &gerbil_scheme_python::OwnedValue,
) -> Result<c_abi::ForeignCallable, c_abi::Error> {
    // SAFETY: this exact linked producer has no VM entry, transfers one context,
    // and uses the shared immutable-result and release contract. Rust linking
    // retains this code for every value returned by the function.
    unsafe { c_abi::ForeignCallable::create(ascent_core_open, input) }
}
/// Bind only the existing compressed closure algorithm, not a generic factory.
/// # Errors
/// Rejects invalid captures and ABI ownership.
pub fn open_reachability(
    input: &gerbil_scheme_python::OwnedValue,
) -> Result<c_abi::ForeignCallable, c_abi::Error> {
    // SAFETY: this fixed, linked, no-VM producer uses the same owned ABI contract.
    unsafe { c_abi::ForeignCallable::create(ascent_reachability_open, input) }
}

/// Shared layout version; function bodies are the existing Library Core.
#[unsafe(no_mangle)]
pub extern "C" fn ascent_core_abi_version() -> u32 {
    c_abi::ABI_VERSION
}

/// Open a fixed Evidence session and transfer one owner-thread callable context.
/// # Safety
/// Input spans must be valid for the call, output must be a writable zeroed slot.
/// The caller must retain this artifact and release/call on the creating thread.
/// No aliased/concurrent call or release is permitted; the bridge enforces this.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ascent_core_open(input: *const View, output: *mut RawCallable) -> i32 {
    // SAFETY: the public caller guarantees the borrowed input and writable output.
    unsafe { create(input, output, Entry::Evidence) }
}
/// Open the existing closure algorithm with immutable cut handles.
/// # Safety
/// The same owner-thread, span and exact-once release rules as `ascent_core_open` apply.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ascent_reachability_open(
    input: *const View,
    output: *mut RawCallable,
) -> i32 {
    // SAFETY: the public caller guarantees the borrowed input and writable output.
    unsafe { create(input, output, Entry::Reachability) }
}
unsafe fn create(input: *const View, output: *mut RawCallable, entry: Entry) -> i32 {
    if output.is_null() {
        return 3;
    }
    let owner = catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: input has the exact borrowed-span contract of this function.
        let input = unsafe { c_abi::read_input(input, ValueLimits::default()) }
            .map_err(|e| e.to_string())?;
        let input = transport::read(input).map_err(|e| e.to_string())?;
        match entry {
            Entry::Evidence => operations::Owner::open(&input)
                .map(Box::new)
                .map(Core::Evidence),
            Entry::Reachability => reachability::Owner::open(&input).map(Core::Reachability),
        }
        .map_err(|e| e.to_string())
    }));
    let Ok(Ok(core)) = owner else {
        return 3;
    };
    let context = Box::new(Context {
        owner: std::thread::current().id(),
        poisoned: false,
        core,
    });
    // SAFETY: one context and release right are transferred into a caller-owned slot.
    unsafe {
        output.write(RawCallable {
            abi_version: c_abi::ABI_VERSION,
            flags: c_abi::NO_VM,
            context: Box::into_raw(context).cast(),
            call: Some(invoke),
            release: Some(release),
        });
    }
    0
}
unsafe extern "C" fn invoke(
    context: *mut c_void,
    input: *const View,
    output: *mut RawValue,
) -> i32 {
    if context.is_null() || output.is_null() {
        return 3;
    }
    // SAFETY: exclusive live context access is an explicit C contract, checked by
    // the upstream owner lease. Core invokes no user foreign callbacks.
    let context = unsafe { &mut *context.cast::<Context>() };
    if context.owner != std::thread::current().id() || context.poisoned {
        return 3;
    }
    let result = catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: the caller borrows all input spans throughout this invocation.
        let started = context.core.trace().start();
        let input = unsafe { c_abi::read_input(input, ValueLimits::default()) }?;
        let decoded = started.map(|v| v.elapsed().as_nanos());
        let started = context.core.trace().start();
        let input = transport::read(input);
        let packet = started.map(|v| v.elapsed().as_nanos());
        let observing = input
            .as_ref()
            .is_ok_and(|v| v.get("method").and_then(|v| v.text().ok()) == Some("diagnose"));
        if !observing {
            context.core.trace().elapsed("abi.inputDecode", decoded);
            context.core.trace().elapsed("abi.inputPacket", packet);
        }
        let response = input.and_then(|input| context.core.invoke(&input));
        let response = match response {
            Ok(value) => gerbil_ascent::Data::object([("ok", true.into()), ("value", value)]),
            Err(error) => gerbil_ascent::Data::object([
                ("ok", false.into()),
                ("error", error.to_string().into()),
            ]),
        };
        let started = context.core.trace().start();
        let response = transport::write(&response);
        if !observing {
            context
                .core
                .trace()
                .record("abi.outputOwnedPacket", started);
        }
        let started = context.core.trace().start();
        let result = c_abi::publish_value(&response);
        if !observing {
            context.core.trace().record("abi.outputEncode", started);
        }
        result
    }));
    match result {
        Ok(Ok(value)) => {
            // SAFETY: the caller provides one writable output slot.
            unsafe {
                output.write(value);
            }
            0
        }
        Ok(Err(_)) => 3,
        Err(_) => {
            context.poisoned = true;
            3
        }
    }
}
unsafe extern "C" fn release(context: *mut c_void) {
    if !context.is_null() {
        // SAFETY: exactly one release right for this producer allocation is held.
        let context = unsafe { Box::from_raw(context.cast::<Context>()) };
        let _ = catch_unwind(AssertUnwindSafe(|| drop(context)));
    }
}
