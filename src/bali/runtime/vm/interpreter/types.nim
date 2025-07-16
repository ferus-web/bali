import pkg/bali/runtime/vm/interpreter/operation

type
  Clause* = object
    name*: string
    operations*: seq[Operation]

    rollback*: ClauseRollback
    compiled*: bool = false

  InvalidRegisterRead* = object of Defect

  ClauseRollback* = object
    clause*: int = int.low
    opIndex*: uint = 1
