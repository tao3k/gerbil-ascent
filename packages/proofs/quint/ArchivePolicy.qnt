// Generated from ExecutionPolicy.lean (ArchivePolicy); formal CI checks exact source.
module ArchivePolicy {
  pure def archive_complete(starts: int, completed: int, pending: int, failed: int, invalid: int, changed: int, sources: int, builder_ok: bool, graph_ok: bool): bool = (builder_ok and (graph_ok and ((starts == completed) and ((pending == 0) and ((failed == 0) and ((invalid == 0) and ((changed == 0) and (0 < sources))))))))
}
