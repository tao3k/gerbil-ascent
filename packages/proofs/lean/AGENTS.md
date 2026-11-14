# Lean resource discipline

- Run focused file checks from the repository root with `just check-lean-file File.lean`.
- Run the complete inventory with `just check-lean-proofs`; both entries reuse the process Guard from the locked LeanPoo dependency. Never run raw `lake env lean` or an unbounded background Lean process.
- Focused file/render memory and heartbeat flags are diagnostic limits. Do not apply them as new library-wide limits; the complete library retains its existing proof budgets under the Guard deadline.
- Preserve failing logs. Do not raise recursion, heartbeat, memory or wall limits to make a failed proof pass.
- A source equality proof that exceeds its budget remains an open obligation; do not substitute `sorry`, an axiom or compiler-trusting decision for kernel checking.
