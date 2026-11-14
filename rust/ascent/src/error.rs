//! Typed failures and resource-exhaustion results.
/// Admission or incomplete-evaluation failure; never negative logical evidence.
#[cfg_attr(
    feature = "process-runtime",
    derive(serde::Serialize, serde::Deserialize)
)]
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Error {
    InvalidProgram(String),
    InvalidUpdate(String),
    Evaluation(String),
    FactLimit,
    SourceFactLimit,
    DerivedFactLimit,
    OutputFactLimit,
    Closed,
    StateLimit,
    Timeout,
    Canceled,
}
impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidProgram(s) | Self::InvalidUpdate(s) | Self::Evaluation(s) => {
                f.write_str(s)
            }
            Self::Closed => f.write_str("owner closed"),
            Self::SourceFactLimit => f.write_str("source fact budget exceeded"),
            Self::DerivedFactLimit => f.write_str("derived fact budget exceeded"),
            Self::OutputFactLimit => f.write_str("output fact budget exceeded"),
            Self::FactLimit => f.write_str("fact budget exhausted"),
            Self::StateLimit => f.write_str("intermediate state budget exhausted"),
            Self::Timeout => f.write_str("evaluation deadline exhausted"),
            Self::Canceled => f.write_str("evaluation canceled"),
        }
    }
}
impl std::error::Error for Error {}
/// Library result preserving typed failures.
pub type Result<T> = std::result::Result<T, Error>;
