//! Statically linked ASCENT exports; registered with the upstream runtime.
use gerbil_scheme_sys as sys;
unsafe extern "C" {
    pub(crate) fn ___LNK_ascent__hybrid(
        state: *mut sys::GerbilGlobalState,
    ) -> *mut sys::GerbilModuleOrLink;
    pub(crate) fn ascent_hybrid_set_checkpoint(callback: extern "C" fn(i64, i64, i64) -> i32);
    pub(crate) fn ascent_hybrid_call(request: i64) -> i64;
}
