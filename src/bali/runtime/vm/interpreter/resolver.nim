import std/[options, tables]
import
  pkg/bali/runtime/vm/interpreter/[types, operation],
  pkg/bali/runtime/vm/shared,
  pkg/bali/runtime/vm/atom,
  pkg/bali/runtime/vm/heap/manager

const SequenceBasedRegisters* = [some(1)]

proc resolve*(clause: Clause, op: var Operation, heap: HeapManager) =
  if op.resolved:
    return

  case op.opCode
  of LoadStr:
    op.arguments &=
      op.consume(Integer, "LOADS expects an integer at position 1", heap = heap)
    op.arguments &=
      op.consume(String, "LOADS expects a string at position 2", heap = heap)
  of LoadInt, LoadUint:
    for x in 1 .. 2:
      op.arguments &=
        op.consume(
          Integer,
          OpCodeToString[op.opCode] & " expects an integer at position " & $x,
          heap = heap,
        )
  #of Equate:
  #  for x, _ in op.rawArgs.deepCopy():
  #    op.arguments &=
  #      op.consume(Integer, "EQU expects an integer at position " & $x, heap = heap)
  of GreaterThanInt, LesserThanInt, GreaterThanEqualInt, LesserThanEqualInt:
    for x in 1 .. 2:
      op.arguments &=
        op.consume(
          Integer,
          OpCodeToString[op.opCode] & " expects an integer at position " & $x,
          heap = heap,
        )
  of Call:
    op.arguments &=
      op.consume(String, "CALL expects an ident/string at position 1", heap = heap)

    for i, x in deepCopy(op.rawArgs):
      op.arguments &=
        op.consume(Integer, "CALL expects an integer at position " & $i, heap = heap)
  of Jump:
    op.arguments &=
      op.consume(
        Integer, "JUMP expects exactly one integer as an argument", heap = heap
      )
  of Add, Mult, Div, Sub, Power:
    for x in 1 .. 2:
      op.arguments &=
        op.consume(
          Integer,
          OpCodeToString[op.opCode] & " expects an integer at position " & $x,
          heap = heap,
        )
  of LoadList:
    op.arguments &=
      op.consume(Integer, "LOADL expects an integer at position 1", heap = heap)
  of AddList:
    op.arguments &=
      op.consume(Integer, "ADDL expects an integer at position 1", heap = heap)

    op.arguments &=
      op.consume(Integer, "ADDL expects an integer at position 2", heap = heap)
  of LoadBool:
    op.arguments &=
      op.consume(Integer, "LOADB expects an integer at position 1", heap = heap)

    op.arguments &=
      op.consume(Boolean, "LOADB expects a boolean at position 2", heap = heap)
  of Swap:
    for x in 1 .. 2:
      op.arguments &=
        op.consume(Integer, "SWAP expects an integer at position " & $x, heap = heap)
  of Return:
    op.arguments &=
      op.consume(Integer, "RETURN expects an integer at position 1", heap = heap)
  of JumpOnError:
    op.arguments &=
      op.consume(Integer, "JMPE expects an integer at position 1", heap = heap)
  of LoadObject:
    op.arguments &=
      op.consume(Integer, "LOADO expects an integer at position 1", heap = heap)
  of LoadUndefined:
    op.arguments &=
      op.consume(Integer, "LOADUD expects an integer at position 1", heap = heap)
  of CreateField:
    for x in 1 .. 2:
      op.arguments &=
        op.consume(Integer, "CFIELD expects an integer at position " & $x, heap = heap)

    op.arguments &=
      op.consume(String, "CFIELD expects a string at position 3", heap = heap)
  of FastWriteField:
    for x in 1 .. 2:
      op.arguments &=
        op.consume(Integer, "FWFIELD expects an integer at position " & $x, heap = heap)
  of WriteField:
    op.arguments &=
      op.consume(Integer, "WFIELD expects an integer at position 1", heap = heap)

    op.arguments &=
      op.consume(String, "WFIELD expects a string at position 2", heap = heap)
  of Increment, Decrement:
    op.arguments &=
      op.consume(
        Integer,
        OpCodeToString[op.opCode] & " expects an integer at position 1",
        heap = heap,
      )
  of CrashInterpreter:
    discard
  of LoadNull:
    op.arguments &=
      op.consume(Integer, "LOADN expects an integer at position 1", heap = heap)
  of ReadRegister:
    op.arguments &=
      op.consume(Integer, "RREG expects an integer at position 1", heap = heap)

    op.arguments &=
      op.consume(Integer, "RREG expects an integer at position 2", heap = heap)

    try:
      op.arguments &=
        op.consume(
          Integer,
          "RREG expects an integer at position 3 when accessing a sequence based register",
          heap = heap,
        )
    except ValueError as exc:
      if op.arguments[1].getInt() in SequenceBasedRegisters:
        raise exc
  of PassArgument:
    op.arguments &=
      op.consume(Integer, "PARG expects an integer at position 1", heap = heap)
  of ResetArgs, ZeroRetval:
    discard
  of CopyAtom:
    op.arguments &=
      op.consume(Integer, "COPY expects an integer at position 1", heap = heap)

    op.arguments &=
      op.consume(Integer, "COPY expects an integer at position 2", heap = heap)
  of MoveAtom:
    op.arguments &=
      op.consume(Integer, "MOVE expects an integer at position 1", heap = heap)

    op.arguments &=
      op.consume(Integer, "MOVE expects an integer at position 2", heap = heap)
  of LoadFloat:
    op.arguments &=
      op.consume(Integer, "LOADF expects an integer at position 1", heap = heap)

    op.arguments &=
      op.consume(Float, "LOADF expects an integer at position 2", heap = heap)
  of LoadBytecodeCallable:
    op.arguments &=
      op.consume(Integer, "LOADBC expects an integer at position 1", heap = heap)
    op.arguments &=
      op.consume(String, "LOADBC expects a string at position 2", heap = heap)
  of ExecuteBytecodeCallable:
    op.arguments &=
      op.consume(Integer, "EXEBC expects an integer at position 1", heap = heap)
  of Invoke:
    if op.rawArgs[0].kind == tkInteger:
      # Bytecode callable
      op.arguments &=
        op.consume(Integer, "INVK expects an integer at position 1", heap = heap)
    elif op.rawArgs[0].kind in {tkIdent, tkQuotedString}:
      # Clause/Builtin
      op.arguments &=
        op.consume(String, "INVK expects an ident/string at position 1", heap = heap)
  of ThrowReferenceError:
    op.arguments &=
      op.consume(Integer, "THROWREF expects a string at position 1", heap = heap)
