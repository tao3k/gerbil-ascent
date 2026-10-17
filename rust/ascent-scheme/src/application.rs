//! Scheme application entry; the upstream runtime owns all lifecycle checks.
use crate::{
    ffi::{___LNK_ascent__hybrid, ascent_hybrid_call},
    values,
};
use gerbil_ascent::{Data, Error, Result};
use gerbil_scheme::{GerbilRuntime, LinkedGerbilProgram};
/// One native Scheme VM owned and checked by the upstream runtime.
/// Neither this owner nor its values can cross a thread boundary.
pub struct Runtime {
    pub(crate) runtime: GerbilRuntime,
}

impl Runtime {
    /// Initialize the library-built Scheme module graph on the calling thread.
    /// # Errors
    /// Propagates upstream one-shot lifecycle, ABI or native initialization errors.
    pub fn initialize() -> Result<Self> {
        // SAFETY: build.rs packages this compiler-generated graph, containing
        // exactly the pinned bridge and ASCENT application exports.
        let program = unsafe { LinkedGerbilProgram::from_linker(___LNK_ascent__hybrid) };
        GerbilRuntime::initialize_program(program)
            .map(|runtime| {
                // SAFETY: the process-lived callback takes only integer request
                // identities; registration and calls stay on the VM owner thread.
                unsafe {
                    crate::ffi::ascent_hybrid_set_checkpoint(
                        crate::control::ascent_hybrid_checkpoint,
                    );
                }
                Self { runtime }
            })
            .map_err(scheme_error)
    }

    /// Enter the native ASCENT application with owned typed data, without JSON.
    /// # Errors
    /// Preserves native validation/evaluation failures. Roots never leave this VM.
    pub fn call(&self, request: &Data) -> Result<Data> {
        if request.get("executionControl").is_some() {
            return self.invoke_rooted(request);
        }
        let limits = gerbil_ascent::Limits {
            max_states: usize::MAX,
            max_facts: usize::MAX,
            ..Default::default()
        };
        let control =
            crate::control::Control::new(&limits, &gerbil_ascent::Cancellation::default())?;
        let mut payload = request.map()?.clone();
        payload.insert("executionControl".into(), control.id());
        self.invoke_rooted(&Data::Map(payload))
    }
    fn invoke_rooted(&self, request: &Data) -> Result<Data> {
        let request = values::encode(&self.runtime, request)?;
        // SAFETY: this linked export borrows a strong input and transfers one
        // fresh upstream root; gerbil-rs-rooted-call contains every exception.
        let export =
            unsafe { self.runtime.bind_object_export(ascent_hybrid_call) }.map_err(scheme_error)?;
        let response = export.call(&request).into_result().map_err(scheme_error)?;
        let response = values::decode(response, 0)?;
        let values = response.list()?;
        if values.len() != 2 {
            return Err(failure("native response arity"));
        }
        if values[0] == Data::Bool(true) {
            Ok(values[1].clone())
        } else {
            Err(scheme_failure(values[1].text()?))
        }
    }
}
pub(crate) fn failure(message: &str) -> Error {
    Error::Evaluation(message.into())
}
fn scheme_failure(message: &str) -> Error {
    match message {
        "ASCENT execution canceled" => Error::Canceled,
        "ASCENT execution deadline exhausted" => Error::Timeout,
        "ASCENT execution work exhausted" => Error::StateLimit,
        "ASCENT execution control closed" => Error::Closed,
        "ASCENT trrel output fact budget exceeded"
        | "ASCENT eqrel output fact budget exceeded"
        | "ASCENT output fact budget exceeded"
        | "ASCENT session output fact budget exceeded"
        | "output fact budget exceeded" => Error::OutputFactLimit,
        "ASCENT source fact budget exceeded"
        | "ASCENT session input fact budget exceeded"
        | "ASCENT actor Session input fact budget exceeded"
        | "source fact budget exceeded" => Error::SourceFactLimit,
        "ASCENT derived fact budget exceeded" | "derived fact budget exceeded" => {
            Error::DerivedFactLimit
        }
        _ => failure(message),
    }
}
pub(crate) fn scheme_error(error: gerbil_scheme::NativeError) -> Error {
    failure(&error.to_string())
}
