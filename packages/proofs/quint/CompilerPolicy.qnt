// Generated from CompilerCost.lean; formal CI checks exact source.
module CompilerPolicy {
  pure def compiler_input(is_c: bool, direct: bool): bool = is_c and direct
  pure def unique_parent_input(same: bool, matches: int): bool = same and matches == 1
  pure def source_attributed(expected: int, targets: List[int], arguments: Set[int]): bool =
    targets == [expected] and arguments.contains(expected)
  pure def single_host(labels: int, limit: int): bool = limit == 0 or labels <= limit
  pure def ggc_complete(expected: int, reported: int, failed: int, changed: int, errors: int): bool =
    0 < expected and expected == reported and failed == 0 and changed == 0 and errors == 0
  pure def stale_modules(current: bool, production: Set[int], requested: Set[int], cached: Set[int]): Set[int] =
    if (current) Set() else requested.union(cached).exclude(production)
}
