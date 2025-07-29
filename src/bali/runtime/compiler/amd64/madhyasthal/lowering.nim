## Routines to lower VM structures to Madhyasthal's IR structures
## This essentially analyzes common bytecode patterns and translates
## them into Madhyasthal's specialized ops.
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import std/[options]
import pkg/[shakar]
import pkg/bali/runtime/compiler/amd64/madhyasthal/ir,
       pkg/bali/runtime/vm/[atom, shared],
       pkg/bali/runtime/vm/interpreter/[types, operation]

type
  OpStream* = object
    ops*: seq[operation.Operation]
    cursor*: int = 0

func eof*(stream: OpStream): bool {.inline.} =
  stream.cursor > stream.ops.len - 1

func consume*(stream: var OpStream): Operation =
  result = stream.ops[stream.cursor]
  stream.cursor.inc

func advance*(stream: var OpStream, cnt: uint = 1'u) =
  stream.cursor += cnt.int

func peekKind*(stream: OpStream): Ops {.inline.} =
  stream.ops[stream.cursor].opcode

proc lowerLoadStrPatterns*(fn: Function, stream: var OpStream, startOp: Operation): bool =
  if stream.peekKind() != PassArgument:
    return
  
  stream.advance()

  if stream.peekKind() != Call:
    return

  let call = stream.consume()
  if &call.arguments[0].getStr() != "BALI_CONSTRUCTOR_STRING":
    return

  fn.insts &= loadStr(uint32(&startOp.arguments[0].getInt()), &startOp.arguments[1].getStr())

proc lowerStream*(fn: Function, stream: var OpStream): bool =
  template bailout(msg: static string) =
    echo msg
    return false

  while not stream.eof:
    case stream.peekKind()
    of LoadUndefined:
      # Just load undefined
      let op = stream.consume()
      fn.insts &= loadUndefined(uint32(&op.arguments[0].getInt()))
    of CreateField: stream.advance
    of LoadBool:
      let op = stream.consume()

      fn.insts &= loadBoolean(
        uint32(&op.arguments[0].getInt()),
        &op.arguments[1].getBool()
      )
    of LoadNull:
      stream.advance
      # fn.insts &= loadNull()
    of ResetArgs:
      stream.advance
    of LoadBytecodeCallable, ReadRegister, ZeroRetval:
      stream.advance
    of PassArgument, Invoke: stream.advance
    of LoadStr:
      if not lowerLoadStrPatterns(fn, stream, stream.consume()):
        discard
    of LoadUint, LoadInt, LoadFloat:
      let op = stream.consume()

      fn.insts &= loadNumber(
        uint32(&op.arguments[0].getInt()),
        &op.arguments[1].getNumeric()
      )
    else: echo stream.peekkind(); bailout "cannot find predictable pattern"

  true

proc lower*(clause: Clause): Option[ir.Function] =
  var fn = Function(name: clause.name)
  var stream = OpStream(ops: clause.operations)

  discard lowerStream(fn, stream)
  return some(fn)
