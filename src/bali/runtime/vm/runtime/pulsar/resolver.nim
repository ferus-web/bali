import std/[options, tables]
import pkg/bali/runtime/vm/runtime/pulsar/[types, operation],
       pkg/bali/runtime/vm/runtime/shared,
       pkg/bali/runtime/vm/atom

const SequenceBasedRegisters* = [some(1)]

proc resolve*(clause: Clause, op: var Operation) =
  case op.opCode
  of LoadStr:
    op.arguments &= op.consume(Integer, "LOADS expects an integer at position 1")

    op.arguments &= op.consume(String, "LOADS expects a string at position 2")
  of LoadInt, LoadUint:
    for x in 1 .. 2:
      op.arguments &=
        op.consume(
          Integer, OpCodeToString[op.opCode] & " expects an integer at position " & $x
        )
  of Equate:
    for x, _ in op.rawArgs.deepCopy():
      op.arguments &= op.consume(Integer, "EQU expects an integer at position " & $x)
  of GreaterThanInt, LesserThanInt, GreaterThanEqualInt, LesserThanEqualInt:
    for x in 1 .. 2:
      op.arguments &=
        op.consume(
          Integer, OpCodeToString[op.opCode] & " expects an integer at position " & $x
        )
  of Call:
    op.arguments &= op.consume(String, "CALL expects an ident/string at position 1")

    for i, x in deepCopy(op.rawArgs):
      op.arguments &= op.consume(Integer, "CALL expects an integer at position " & $i)
  of Jump:
    op.arguments &=
      op.consume(Integer, "JUMP expects exactly one integer as an argument")
  of Add, Mult, Div, Sub, AddInt, SubInt, MultInt, DivInt, PowerInt, MultFloat,
      DivFloat, PowerFloat, AddFloat, SubFloat:
    for x in 1 .. 2:
      op.arguments &=
        op.consume(
          Integer, OpCodeToString[op.opCode] & " expects an integer at position " & $x
        )
  of LoadList:
    op.arguments &= op.consume(Integer, "LOADL expects an integer at position 1")
  of AddList:
    op.arguments &= op.consume(Integer, "ADDL expects an integer at position 1")

    op.arguments &= op.consume(Integer, "ADDL expects an integer at position 2")
  of LoadBool:
    op.arguments &= op.consume(Integer, "LOADB expects an integer at position 1")

    op.arguments &= op.consume(Boolean, "LOADB expects a boolean at position 2")
  of Swap:
    for x in 1 .. 2:
      op.arguments &= op.consume(Integer, "SWAP expects an integer at position " & $x)
  of Return:
    op.arguments &= op.consume(Integer, "RETURN expects an integer at position 1")
  of JumpOnError:
    op.arguments &= op.consume(Integer, "JMPE expects an integer at position 1")
  of LoadObject:
    op.arguments &= op.consume(Integer, "LOADO expects an integer at position 1")
  of LoadUndefined:
    op.arguments &= op.consume(Integer, "LOADUD expects an integer at position 1")
  of CreateField:
    for x in 1 .. 2:
      op.arguments &= op.consume(Integer, "CFIELD expects an integer at position " & $x)

    op.arguments &= op.consume(String, "CFIELD expects a string at position 3")
  of FastWriteField:
    for x in 1 .. 2:
      op.arguments &= op.consume(
        Integer, "FWFIELD expects an integer at position " & $x
      )
  of WriteField:
    op.arguments &= op.consume(Integer, "WFIELD expects an integer at position 1")

    op.arguments &= op.consume(String, "WFIELD expects a string at position 2")
  of Increment, Decrement:
    op.arguments &=
      op.consume(
        Integer, OpCodeToString[op.opCode] & " expects an integer at position 1"
      )
  of CrashInterpreter:
    discard
  of LoadNull:
    op.arguments &= op.consume(Integer, "LOADN expects an integer at position 1")
  of ReadRegister:
    op.arguments &= op.consume(Integer, "RREG expects an integer at position 1")

    op.arguments &= op.consume(Integer, "RREG expects an integer at position 2")

    try:
      op.arguments &=
        op.consume(
          Integer,
          "RREG expects an integer at position 3 when accessing a sequence based register",
        )
    except ValueError as exc:
      if op.arguments[1].getInt() in SequenceBasedRegisters:
        raise exc
  of PassArgument:
    op.arguments &= op.consume(Integer, "PARG expects an integer at position 1")
  of ResetArgs, ZeroRetval:
    discard
  of CopyAtom:
    op.arguments &= op.consume(Integer, "COPY expects an integer at position 1")

    op.arguments &= op.consume(Integer, "COPY expects an integer at position 2")
  of MoveAtom:
    op.arguments &= op.consume(Integer, "MOVE expects an integer at position 1")

    op.arguments &= op.consume(Integer, "MOVE expects an integer at position 2")
  of LoadFloat:
    op.arguments &= op.consume(Integer, "LOADF expects an integer at position 1")

    op.arguments &= op.consume(Float, "LOADF expects an integer at position 2")
  of LoadBytecodeCallable:
    op.arguments &= op.consume(Integer, "LOADBC expects an integer at position 1")
    op.arguments &= op.consume(String, "LOADBC expects a string at position 2")
  of ExecuteBytecodeCallable:
    op.arguments &= op.consume(Integer, "EXEBC expects an integer at position 1")
  of Invoke:
    if op.rawArgs[0].kind == tkInteger:
      # Bytecode callable
      op.arguments &= op.consume(Integer, "INVK expects an integer at position 1")
    elif op.rawArgs[0].kind in {tkIdent, tkQuotedString}:
      # Clause/Builtin
      op.arguments &= op.consume(String, "INVK expects an ident/string at position 1")
