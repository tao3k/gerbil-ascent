// Generated from PreparationWork.lean; formal CI checks exact source.
module PreparationSupport {
  pure def support_roots(source_suites: bool, base: List[str], requested: List[str], cached: List[str]): List[str] =
    (if (source_suites) List() else base).concat(requested).concat(cached)
}
