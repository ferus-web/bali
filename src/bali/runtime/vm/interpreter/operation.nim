import std/[options, tables, strutils]
import pkg/bali/runtime/vm/[atom, shared]
import pkg/shakar

const MirageOperationJitThreshold* {.intdefine.} = 8
  # FIXME: set this to something higher

type Operation* = object
  index*: uint64

  opcode*: Ops
  rawArgs*: seq[Token] # should be zero'd out once `computeArgs` is called

  arguments*: seq[JSValue]
  consumed*: bool = false
  lastConsume: int = 0

  resolved*: bool = false

  when not defined(mirageNoJit) and defined(amd64):
    called*: int
      ## How many times has this operation been called this clause execution? (used to determine if it should be JIT'd)

proc expand*(operation: Operation): string {.inline.} =
  assert operation.consumed,
    "Attempt to expand operation that hasn't been consumed. This was most likely caused by a badly initialized exception."
  var expanded = OpCodeToString[operation.opCode]

  for arg in operation.arguments:
    expanded &= ' ' & $arg.crush("")

  expanded

proc shouldCompile*(operation: Operation): bool {.inline, noSideEffect, gcsafe.} =
  operation.called >= MirageOperationJitThreshold

proc consume*(
    operation: var Operation,
    kind: MAtomKind,
    expects: string,
    enforce: bool = true,
    position: Option[int] = none(int),
): JSValue {.inline.} =
  operation.consumed = true

  let
    pos =
      if *position:
        &position
      else:
        0
    raw = operation.rawArgs[pos]
    rawType =
      case raw.kind
      of tkQuotedString: String
      of tkInteger: Integer
      of tkDouble: Float
      else: Null

  if not *position and operation.rawArgs.len > 1:
    operation.rawArgs = deepCopy(operation.rawArgs[1 ..< operation.rawArgs.len])

  if rawType != kind and raw.kind != tkIdent and enforce:
    raise newException(ValueError, expects & ", got " & $rawType & " instead.")

  case raw.kind
  of tkQuotedString:
    return str raw.str
  of tkIdent:
    # if it is a boolean, return it as such
    # otherwise, return as a string

    if raw.ident == "true" or raw.ident == "false":
      return boolean(parseBool(raw.ident))

    return str raw.ident
  of tkInteger:
    return integer raw.integer
  of tkDouble:
    return floating raw.double.float64
  else:
    discard
