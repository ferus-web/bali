## Routines to lower VM structures to Madhyasthal's IR structures
## This essentially analyzes common bytecode patterns and translates
## them into Madhyasthal's specialized ops.
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import std/[algorithm, options, logging, tables]
import pkg/[shakar]
import
  pkg/bali/runtime/compiler/madhyasthal/ir,
  pkg/bali/runtime/vm/[atom, shared],
  pkg/bali/runtime/vm/interpreter/[types, operation]

type OpStream* = object
  ops*: seq[operation.Operation]
  cursor*: int = 0

  opToIrMap*: Table[int, int]

func eof*(stream: OpStream): bool {.inline.} =
  stream.cursor > stream.ops.len - 1

func consume*(stream: var OpStream): Operation =
  result = stream.ops[stream.cursor]
  stream.cursor.inc

func hasAhead*(stream: OpStream, cnt: uint = 1'u): bool =
  uint(stream.ops.len - stream.cursor) >= cnt

func advance*(stream: var OpStream, cnt: uint = 1'u) =
  stream.cursor += cnt.int

func peekKind*(stream: OpStream): Ops {.inline.} =
  stream.ops[stream.cursor].opcode

func peek*(stream: OpStream): operation.Operation {.inline.} =
  stream.ops[stream.cursor]

proc lowerLoadStrPatterns*(
    fn: var Function, stream: var OpStream, startOp: Operation
): bool =
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

  fn.insts &=
    loadStr(uint32(&startOp.arguments[0].getInt()), &startOp.arguments[1].getStr())
  true

proc lowerLoadNullPatterns*(
    fn: var Function, stream: var OpStream, op: Operation
): bool =
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

proc lowerPassArgPatterns*(
    fn: var Function, stream: var OpStream, startIdx: uint32
): bool =
  let
    arg1 = startIdx
    arg2 = uint32(&(stream.consume().arguments[0]).getInt())

  let next = stream.consume()
  if next.opcode == Call and &next.arguments[0].getStr() != "BALI_EQUATE_ATOMS":
    return false

  fn.insts &= equate(arg1, arg2)

  return true

proc patchJumps*(fn: var Function, stream: OpStream) =
  var toDelete = newSeqOfCap[int](1)

  for i, inst in fn.insts:
    if inst.kind != InstKind.Jump:
      continue

    let index = inst.args[0].vint
    if not stream.opToIrMap.contains(index):
      toDelete.add(i)
    else:
      fn.insts[i].args[0] = ArgVariant(kind: avkInt, vint: stream.opToIrMap[index] - 1)

    # echo "Patch jump. bytecode=" & $index & ", ir=" & $(stream.optoirmap[index] - 1)
    # echo dumpinst(fn.insts[stream.opToIrMap[index] - 1])

  for del in toDelete.reversed:
    fn.insts.delete(del)

proc lowerStream*(fn: var Function, stream: var OpStream): bool =
  template bailout(msg: string) =
    debug "jit/amd64: midtier jit is bailing out: " & msg

    when not defined(baliExplosiveBailouts):
      return false
    else:
      raise newException(Defect, "Bailout in midtier JIT: " & msg)

  while not stream.eof:
    let op = stream.peek()
    # debugEcho $op.index & ") " & $op.opcode
    stream.opToIrMap[op.index.int] = fn.insts.len

    case op.opcode
    of LoadUndefined:
      # Just load undefined
      let op = stream.consume()
      fn.insts &= loadUndefined(uint32(&op.arguments[0].getInt()))
    of CreateField:
      stream.advance
    of LoadBool:
      let op = stream.consume()

      fn.insts &=
        loadBoolean(uint32(&op.arguments[0].getInt()), &op.arguments[1].getBool())
    of LoadNull:
      let op = stream.consume()

      if not lowerLoadNullPatterns(fn, stream, op):
        fn.insts &= loadNull(uint32(&op.arguments[0].getInt()))
    of ResetArgs:
      stream.advance()

      fn.insts &= resetArgs()
    of ReadRegister, ZeroRetval:
      stream.advance
    of LoadBytecodeCallable:
      let
        op = stream.consume()
        dest = uint32(&op.arguments[0].getInt())
        name = &op.arguments[1].getStr()

      fn.insts &= loadBytecodeCallable(dest, name)
    of PassArgument:
      let
        op = stream.consume()
        index = uint32(&op.arguments[0].getInt())

      if stream.hasAhead(2) and stream.peekKind() == PassArgument and
          lowerPassArgPatterns(fn, stream, index):
        continue

      fn.insts &= passArgument(index)
    of Invoke:
      let
        op = stream.consume()
        index = uint32(&op.arguments[0].getInt())

      fn.insts &= invoke(index)
    of LoadStr:
      let op = stream.consume()
      fn.insts &= loadStr(uint32(&op.arguments[0].getInt()), &op.arguments[1].getStr())
    of LoadUint, LoadInt, LoadFloat:
      let op = stream.consume()

      fn.insts &=
        loadNumber(uint32(&op.arguments[0].getInt()), &op.arguments[1].getNumeric())
    of Add:
      let op = stream.consume()

      fn.insts &=
        add(uint32(&op.arguments[0].getInt()), uint32(&op.arguments[1].getInt()))
    of CopyAtom:
      let op = stream.consume()

      fn.insts &=
        copy(uint32(&op.arguments[0].getInt()), uint32(&op.arguments[1].getInt()))
    of Sub:
      let op = stream.consume()

      fn.insts &=
        sub(uint32(&op.arguments[0].getInt()), uint32(&op.arguments[1].getInt()))
    of Mult:
      let op = stream.consume()

      fn.insts &=
        mult(uint32(&op.arguments[0].getInt()), uint32(&op.arguments[1].getInt()))
    of Div:
      let op = stream.consume()

      fn.insts &=
        divide(uint32(&op.arguments[0].getInt()), uint32(&op.arguments[1].getInt()))
    of Return:
      let op = stream.consume()

      fn.insts &= returnV(uint32(&op.arguments[0].getInt()))
    of Call:
      let op = stream.consume()
      let name = &op.arguments[0].getStr()

      fn.insts &= call(name)
    of Jump:
      let op = stream.consume()

      # We need to "patch" this once the IR is fully lowered
      fn.insts &= jump(&op.arguments[0].getInt())
    of LesserThanInt:
      let op = stream.consume()

      # just like Jump, we need to patch this
      fn.insts &=
        lesserThanI(
          uint32(&op.arguments[0].getInt()), uint32(&op.arguments[1].getInt())
        )
    of Increment:
      let op = stream.consume()

      fn.insts &= increment(uint32(&op.arguments[0].getInt()))
    else:
      bailout "cannot find predictable pattern for op: " & $stream.peekKind()

  patchJumps(fn, stream)

  true

proc lower*(clause: Clause): Option[ir.Function] =
  var fn = Function(name: clause.name)
  var stream = OpStream(ops: clause.operations)

  if lowerStream(fn, stream):
    return some(fn)
