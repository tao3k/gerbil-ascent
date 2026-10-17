//! Scheme occurrence ceilings. None means unlimited, never a large sentinel.
use crate::{Error, Result};
/// Optional native input, derived and output occurrence ceilings.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct FactLimits {
    pub input: Option<usize>,
    pub derived: Option<usize>,
    pub output: Option<usize>,
}
impl FactLimits {
    /// Caller policy may tighten a declaration, never loosen it.
    /// # Errors
    /// Finite ceilings must be positive.
    pub fn tighten(self, caller: Self) -> Result<Self> {
        let combine = |a: Option<usize>, b: Option<usize>| -> Result<Option<usize>> {
            if a == Some(0) || b == Some(0) {
                return Err(Error::InvalidProgram(
                    "finite fact limits must be positive".into(),
                ));
            }
            Ok(match (a, b) {
                (Some(a), Some(b)) => Some(a.min(b)),
                (a, b) => a.or(b),
            })
        };
        Ok(Self {
            input: combine(self.input, caller.input)?,
            derived: combine(self.derived, caller.derived)?,
            output: combine(self.output, caller.output)?,
        })
    }
}
