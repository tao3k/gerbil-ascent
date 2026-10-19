// Generated from PreparationWork.lean; formal CI checks exact source.
module PreparationInterfaces {
  pure def interface_selected(admitted: bool, reload: bool, compiling: bool, producer: bool, present: bool): bool =
    admitted and not(reload) and not(compiling) and producer and present
}
