import std/options
import pkg/bali/runtime/vm/interpreter/operation

type
  Clause* = object
    name*: string
    operations*: seq[Operation]

    rollback*: ClauseRollback
    compiled*: bool = false

    profIterationsSpent*: uint64 ## The number of ops spent executing this clause
    cachedJudgement*: Option[CompilationJudgement]

  CompilationJudgement* {.pure, size: sizeof(uint8).} = enum
    DontCompile ## This function is not worth compiling.
    Ineligible
      ## This function has caused the JIT to bail out before - do not attempt to compile it. It'll just waste time.
    Eligible ## This function might be worth compiling.

    WarmingUp ## This function is warming up - it's best compiled with the midtier JIT.

  InvalidRegisterRead* = object of Defect

  ClauseRollback* = object
    clause*: int = int.low
    opIndex*: uint = 1
