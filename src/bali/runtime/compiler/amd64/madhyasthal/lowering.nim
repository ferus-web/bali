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
    dec stream.cursor
    return

  let call = stream.consume()
  if &call.arguments[0].getStr() != "BALI_CONSTRUCTOR_STRING":
    stream.cursor -= 2
    return

  fn.insts &= loadStr(uint32(&startOp.arguments[0].getInt()), &startOp.arguments[1].getStr())

proc lowerLoadNullPatterns*(fn: Function, stream: var OpStream, op: Operation): bool =
  let uintLoad = stream.consume()
  if uintLoad.opcode != LoadUint:
    stream.cursor.dec
    return

  let source = uint32(&uintLoad.arguments[1].getInt())
  
  let passArg1 = stream.consume()
  if passArg1.opcode != PassArgument:
    stream.cursor -= 2
    return
  
  let uintLoad2 = stream.consume()
  if uintLoad2.opcode != LoadUint:
    stream.cursor -= 3
    return

  let dest = uint32(&uintLoad2.arguments[1].getInt())
  let passArg2 = stream.consume()
  if passArg2.opcode != PassArgument:
    stream.cursor -= 4
    return
  
  let strLoadFieldName = stream.consume()
  if strLoadFieldName.opcode != LoadStr:
    stream.cursor -= 5
    return

  let field = &strLoadFieldName.arguments[1].getStr()
  
  let passArg3 = stream.consume()
  if passArg3.opcode != PassArgument:
    stream.cursor -= 6
    return
  
  let resolverCall = stream.consume()
  if resolverCall.opcode != Call:
    stream.cursor -= 7
    return
  
  let resetArgsInv = stream.consume()
  if resetArgsInv.opcode != ResetArgs:
    stream.cursor -= 8
    return
  
  fn.insts &= readProperty(source, field)
  fn.insts &= readScalarRegister(Register.ReturnValue, dest)

  true

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
      let op = stream.consume()
      
      if not lowerLoadNullPatterns(fn, stream, op):
        fn.insts &= loadNull(
          uint32(&op.arguments[0].getInt())
        )
    of ResetArgs:
      stream.advance
    of LoadBytecodeCallable, ReadRegister, ZeroRetval:
      stream.advance
    of PassArgument, Invoke: stream.advance
    of LoadStr:
      let op = stream.consume()
      if not lowerLoadStrPatterns(fn, stream, op):
        fn.insts &= loadStr(uint32(&op.arguments[0].getInt()), &op.arguments[1].getStr())
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
