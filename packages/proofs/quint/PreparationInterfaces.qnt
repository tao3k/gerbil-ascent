// Generated from PreparationWork.lean; formal CI checks exact source.
module PreparationInterfaces {
  pure def interface_selected(admitted: bool, reload: bool, producer: bool, present: bool): bool =
    admitted and not(reload) and producer and present
}
