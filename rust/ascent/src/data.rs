//! Owned structured data for library workflows; no serialized transport or Python state.
use crate::{Error, Result};
use num_bigint::BigInt;
use num_traits::{Signed, ToPrimitive};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
/// Owned typed packets for deterministic workflow identities and detached observations.
#[cfg_attr(
    feature = "process-runtime",
    derive(serde::Serialize, serde::Deserialize)
)]
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Data {
    Null,
    Bool(bool),
    Integer(BigInt),
    Real(u64),
    Text(String),
    List(Vec<Self>),
    Map(BTreeMap<String, Self>),
}
impl From<&str> for Data {
    fn from(v: &str) -> Self {
        Self::Text(v.into())
    }
}
impl From<String> for Data {
    fn from(v: String) -> Self {
        Self::Text(v)
    }
}
impl From<usize> for Data {
    fn from(v: usize) -> Self {
        Self::Integer(v.into())
    }
}
impl From<u64> for Data {
    fn from(v: u64) -> Self {
        Self::Integer(v.into())
    }
}
impl From<bool> for Data {
    fn from(v: bool) -> Self {
        Self::Bool(v)
    }
}
impl Data {
    #[must_use]
    pub fn object<const N: usize>(fields: [(&str, Self); N]) -> Self {
        Self::Map(fields.into_iter().map(|(k, v)| (k.into(), v)).collect())
    }
    /// # Errors
    /// Rejects values of the wrong native kind.
    pub fn map(&self) -> Result<&BTreeMap<String, Self>> {
        if let Self::Map(v) = self {
            Ok(v)
        } else {
            Err(invalid("object required"))
        }
    }
    /// # Errors
    /// Rejects missing fields.
    pub fn field(&self, key: &str) -> Result<&Self> {
        self.map()?
            .get(key)
            .ok_or_else(|| invalid(&format!("missing field: {key}")))
    }
    #[must_use]
    pub fn get(&self, key: &str) -> Option<&Self> {
        if let Self::Map(v) = self {
            v.get(key)
        } else {
            None
        }
    }
    /// # Errors
    /// Rejects values of the wrong native kind.
    pub fn list(&self) -> Result<&[Self]> {
        if let Self::List(v) = self {
            Ok(v)
        } else {
            Err(invalid("array required"))
        }
    }
    /// # Errors
    /// Rejects values of the wrong native kind.
    pub fn text(&self) -> Result<&str> {
        if let Self::Text(v) = self {
            Ok(v)
        } else {
            Err(invalid("text required"))
        }
    }
    /// # Errors
    /// Rejects empty/nontext identities.
    pub fn identity(&self) -> Result<&str> {
        let v = self.text()?;
        if v.is_empty() {
            Err(invalid("nonempty identity required"))
        } else {
            Ok(v)
        }
    }
    /// # Errors
    /// Rejects integers, nulls or other truthy nonbooleans.
    pub fn boolean(&self) -> Result<bool> {
        if let Self::Bool(v) = self {
            Ok(*v)
        } else {
            Err(invalid("Boolean required"))
        }
    }
    /// # Errors
    /// Rejects negative/noninteger values and counter overflow.
    pub fn natural(&self) -> Result<&BigInt> {
        if let Self::Integer(v) = self
            && !v.is_negative()
        {
            Ok(v)
        } else {
            Err(invalid("nonnegative exact integer required"))
        }
    }
    /// # Errors
    /// Rejects negative/noninteger values or machine-size overflow.
    pub fn index(&self) -> Result<usize> {
        self.natural()?.to_usize().ok_or(Error::StateLimit)
    }
    /// Stable typed identity; map ordering is canonical, and type tags distinguish values.
    #[must_use]
    pub fn digest(&self) -> String {
        let mut hash = Sha256::new();
        hash.update(b"ascent.data.v1\0");
        self.hash_into(&mut hash);
        format!("{:x}", hash.finalize())
    }
    pub(crate) fn digest_slice(values: &[Self]) -> String {
        let mut hash = Sha256::new();
        hash.update(b"ascent.data.v1\0");
        Self::hash_list(values, &mut hash);
        format!("{:x}", hash.finalize())
    }
    fn hash_into(&self, hash: &mut Sha256) {
        match self {
            Self::Null => hash.update([0]),
            Self::Bool(v) => hash.update([1, u8::from(*v)]),
            Self::Integer(v) => {
                hash.update([2]);
                let (sign, bytes) = v.to_bytes_be();
                hash.update([match sign {
                    num_bigint::Sign::Minus => 0,
                    num_bigint::Sign::NoSign => 1,
                    num_bigint::Sign::Plus => 2,
                }]);
                hash.update((bytes.len() as u64).to_be_bytes());
                hash.update(bytes);
            }
            Self::Real(bits) => {
                hash.update([6]);
                hash.update(bits.to_be_bytes());
            }
            Self::Text(v) => {
                hash.update([3]);
                hash.update((v.len() as u64).to_be_bytes());
                hash.update(v.as_bytes());
            }
            Self::List(v) => Self::hash_list(v, hash),
            Self::Map(v) => Self::hash_map(v, hash),
        }
    }
    fn hash_list(values: &[Self], hash: &mut Sha256) {
        hash.update([4]);
        hash.update((values.len() as u64).to_be_bytes());
        for value in values {
            value.hash_into(hash);
        }
    }
    fn hash_map(values: &BTreeMap<String, Self>, hash: &mut Sha256) {
        hash.update([5]);
        hash.update((values.len() as u64).to_be_bytes());
        for (key, value) in values {
            hash.update((key.len() as u64).to_be_bytes());
            hash.update(key.as_bytes());
            value.hash_into(hash);
        }
    }
}
pub(crate) fn invalid(message: &str) -> Error {
    Error::InvalidUpdate(message.into())
}
