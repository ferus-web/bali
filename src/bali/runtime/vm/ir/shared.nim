## Shared code for the entire IR generation suite.
##

import std/hashes
import ../runtime/shared, ../atom

type
  Register* = enum
    ReturnValue = 0
    CallArgument = 1

  IROperation* = object
    opCode*: Ops
    arguments*: seq[MAtom]

  CodeModule* = object
    name*: string
    operations*: seq[IROperation]

  IRGenerator* = ref object
    name*: string
    modules*: seq[CodeModule]
    currModule*: string

proc hash*(operation: IROperation): Hash {.inline.} =
  hash((operation.opCode, operation.arguments))

proc hash*(gen: IRGenerator): Hash {.inline.} =
  var h: Hash

  for module in gen.modules:
    for op in module.operations:
      h = h !& hash op

  h
