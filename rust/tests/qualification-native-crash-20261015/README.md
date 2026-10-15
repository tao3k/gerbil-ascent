# Native gxi crash diagnosis — 2026-10-15

The unchanged Ubuntu corpus crashed in two different long-lived batches at
`a346550`. This directory records the subsequent native diagnosis, not a retry
accepted as a repair. The original assertions, 120-second test boundary, heap
limit and corpus were retained.

## Actual native fault

Diagnostic commit `b8bd7c2` enabled core generation and post-failure GDB extraction.
[Run 38668399927](https://github.com/tao3k/gerbil-ascent/actions/runs/38668399927)
produced a core from the failing original batch. The compressed GDB transcript
is retained here; the 1.2 GB core remains in
[artifact 11943004189](https://github.com/tao3k/gerbil-ascent/actions/runs/38668399927/artifacts/11943004189).
The artifact has 30-day retention. Its original digest and ELF identification
are retained separately. The matching Linux SDK was downloaded and verified
against SHA-256 `9844ba362fdf6f1c5e8a4411e462a466d52dee0d541f8e84f61091cec0e5e740`.

The native stack is `___H___kernel -> ___call -> ___run -> ___setup`. The fault
is `___H___kernel+10448` (`0x55dde193c405`). The instruction sequence is:

```text
call ___stack_overflow_undo_if_possible
cmp  $-4, %rax
jne  ...
mov  (%rsp), %rax
mov  (%rax), %rcx       # SIGSEGV; rax = 0xfffffffffffffffc
```

The saved caller-frame pointer is the Scheme false value, not a valid frame
address. The current undo call has already returned false; the core does not
claim that this particular call performed the earlier damaging reuse. The
failure is in Gambit's continuation/break-frame machinery before the Rust/PyO3
CI gate is reached. The active break is `0x7f1fc081cbd0`, below
the first break at `0x7f1fc081d010`; the first break still has nonzero
STACK_MSECTION eligibility (`0x7f1fc1228018`). This is the nested-break case
covered by the upstream ownership control. `first-break.log.gz` retains these
core bytes; they do not identify every earlier writer. `offline-frame.log.gz` records the same core loaded on the Mac
with the exact Linux ELF, plus processor-state memory and disassembly.

## Stale SDK and the upstream ownership repair

| Environment | Gerbil | Gambit | Configuration |
| --- | --- | --- | --- |
| Old Ubuntu CI release | 2591dcd | dcd677cd3e40860bdd27dfbdbf5e3ce46ab03813 | single VM default; no SMP configure option |
| Qualified local Mac release | 1cfb032 | ea114fc3d2f120abbe20393c1f9aeafdd3f8c89f | multiple VMs, SMP scheduler; one OS thread per VM |

The relevant runtime-source difference is upstream commit
`ea114fc3d2f120abbe20393c1f9aeafdd3f8c89f`, **Invalidate stack overflow undo
across continuation ownership changes**. Its original patch and commit message
are retained in `undo-regression/upstream-fix.patch.gz`.

An overflow break retains a previous stack section. Capturing a continuation
can leave live frames in it, and restoring/grafting a continuation can replace
NEXT while leaving stale overflow ownership metadata. Undo can then reuse
frames still owned by the saved continuation. The repair clears the first
break's undo eligibility at thread save/restore and continuation
capture/graft/return, including nested breaks. Ordinary private overflow undo
remains available; the existing break handler copies frames after ownership
changes. This is not a blanket disablement of the optimization.

The missing SMP/multiple-VM flags expose SDK drift but alone do not establish
this corruption mechanism. The old SDK also lacks this specific ownership
repair. An instruction-site backtrace does not identify every historical
corrupting write; validation must therefore include the upstream invariant
regression and the unchanged original corpus on the repaired runtime.

## Matched upstream regression

`undo-regression/stack-overflow-undo.c` is the unmodified regression from the
upstream repair. Both controls use the same configured Mac SDK header and
compiler options. The negative control reverses only the 15-line upstream
repair, preserving the other configuration and patches.

Both compile with GCC 16, `-O1 -Wall -Wextra -Werror`, and the matching Apple SDK.
The fixed header passes all five operations with first/nested breaks and
present/absent metadata (20 combinations). The old behavior exits 1 at line 111:
continuation ownership changed without clearing the first break's undo
eligibility. Commands, header digests, compiler logs and actual exits are in the
regression receipt. The fixture's assertions were not modified.

## Mac evidence boundary

The previous normal complete Mac run passed 169 modules / 1,349 cases in 79s.
A full original long batch under LLDB hit the unchanged 120s boundary and is
retained as a diagnostic timeout. It is not counted as a pass. Each of the two
last-active modules (`scoped-query` and `scoped-reachability-mask`) subsequently
ran separately under LLDB: eight cases each, normal exit 0. This does not prove
that the complete long-lived batches are safe on every platform.

## Repair qualification

The user authorized rebuilding and publishing the Linux capability with the
same immutable upstream recipe as the qualified Mac SDK (gerbil-bazel commit
`7f7a1b9877ceb49134a2942dceea492811538741`).
[Upstream build 38670345873](https://github.com/tao3k/gerbil-bazel/actions/runs/38670345873)
completed compilation, focused runtime contracts, source-toolchain validation,
packaging and relocated-byte validation successfully. Its final publication
failed with HTTP 403 from the Action token. Creating the exact tag with the
authorized account and restoring the cache did not resolve that permission
failure; it is retained as a delivery failure, not a native test failure.

That historical workflow did not export an artifact, and its tag-scoped cache
has no supported CLI download path. An isolated helper branch therefore adds
the standard artifact upload instead of publication. It checks out the same
`7f7a1b9` recipe and retains every original build and validation step.
[Artifact producer 38674508991](https://github.com/tao3k/gerbil-bazel/actions/runs/38674508991)
completed all build, runtime, packaging, relocation and artifact steps successfully. The helper does not alter upstream main or any
other task's checkout. The resulting SDK was published by the authorized account after artifact
verification.

The verified bundle is now [published](https://github.com/tao3k/gerbil-bazel/releases/tag/gerbil-v0.19-1cfb032c7a1612637da6205f5f8a15683eba3ba0-linux-x86_64-portable-full-single-host-unlimited-multiple-vms-patch9599b09b82f8) with archive SHA-256
`143c691fee5af4f9f631fd339f69a66f562e42e0bfc1d4ee2cda5fa8d35c35ee`. GitHub's artifact ZIP digest and the downloaded ZIP
match. The archive's own digest, source receipts, platform, exact Gambit argument,
multiple-VM definition and all five invalidation sites were checked before
account-authorized publication. The helper's Action token did not publish it.

The actual installer guard accepts the fixed Mac and Linux receipts/headers
and rejects the old Linux SDK with `SDK-ADMISSION-ERROR` (exit 65). These are
metadata/header admission controls, not Linux execution on a Mac.

Original-corpus and full CI qualification of the new ASCENT pin is a separate
gate, pending at this report's publication. Its authoritative result belongs to
the current PR commit's checks. ASCENT's cancellation, resource, occurrence and
provenance code is unchanged by this dependency repair.
