// Waiting is advisory: changing its bounded work cannot grant a decision.
module CheckpointSpin {
  const Mutation: str
  var ready: bool
  action init = ready' = false
  action step = ready' = true
  pure def Budget(cpus: int, owners: int): int =
    if ((cpus >= 3 or Mutation == "ignore-cpu-pressure") and
        (owners == 1 or Mutation == "ignore-owner-pressure")) {
      if (Mutation == "unbounded-spin") 1025 else 1024
    } else 32
  val CpuPressure = not(ready) or Set(0,1,2).forall(cpus => Set(0,1,2,12).forall(owners => Budget(cpus,owners) == 32))
  val OwnerPressure = not(ready) or Set(0,1,2,3,12).forall(cpus => Set(0,2,12).forall(owners => Budget(cpus,owners) == 32))
  val Bounded = not(ready) or Set(0,1,2,3,12).forall(cpus => Set(0,1,2,12).forall(owners =>
    Budget(cpus,owners) >= 32 and Budget(cpus,owners) <= 1024))
}
