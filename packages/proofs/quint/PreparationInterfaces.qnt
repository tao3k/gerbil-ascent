// Generated from PreparationWork.lean; formal CI checks exact source.
module PreparationInterfaces {
  pure def interface_selected(admitted: bool, reload: bool, compiling: bool, producer: bool, present: bool): bool =
    admitted and not(reload) and not(compiling) and producer and present
  pure def request_interface_selected(request: int, admitted: bool, reload: bool, compiling: bool, producer: bool, present: bool): bool =
    Set(0, 1, 2).contains(request) and interface_selected(admitted, reload, compiling, producer, present)
  // Two possibly aliased entries: reverse insertion must retain the first.
  pure def first_alias(k0: int, v0: int, k1: int, v1: int, key: int): int =
    if (k0 == key) v0 else if (k1 == key) v1 else -1
  pure def batch_width(entries: int, workers: int): int =
    if (entries == 0) 0 else (entries - 1) / workers + 1
  pure def native_source_workers(entries: int, cores: int): int =
    if (entries < cores) entries else cores
  pure def source_batch_width(darwin: bool, entries: int, workers: int): int =
    if (darwin) {
      val width = batch_width(entries, workers)
      if (width < 8) width else 8
    } else batch_width(entries, workers)
  pure def source_live_ratio(darwin: bool, parallel_source: bool): int =
    if (darwin and parallel_source) 90 else 50
  pure val complete_packed_starts =
    9 + 12
  pure val complete_darwin_starts =
    9 + 2 * 12
}
