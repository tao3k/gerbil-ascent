//! One admission transition shared by linked and exec-isolated Rust owners.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct State {
    pub(crate) work: usize,
    pub(crate) maximum: usize,
    pub(crate) accepted: bool,
    pub(crate) suspended: bool,
}
impl State {
    // BEGIN EXECUTION ADMISSION
    pub(crate) fn advance(&mut self, work: i64, interruption: impl FnOnce(bool) -> i32) -> i32 {
        if work == -2 {
            self.suspended = true;
            return 0;
        }
        if work == -3 {
            self.suspended = false;
            return 0;
        }
        if self.suspended {
            return 0;
        }
        let interrupted = interruption(self.accepted);
        if interrupted != 0 {
            return interrupted;
        }
        if self.accepted {
            return 0;
        }
        if work == -1 {
            self.accepted = true;
            return 0;
        }
        let Ok(work) = usize::try_from(work) else {
            return 3;
        };
        let Some(work) = self.work.checked_add(work) else {
            return 3;
        };
        if work > self.maximum {
            return 3;
        }
        self.work = work;
        0
    }
    // END EXECUTION ADMISSION
}
#[cfg(test)]
#[path = "../tests/unit/control_state.rs"]
mod tests;
