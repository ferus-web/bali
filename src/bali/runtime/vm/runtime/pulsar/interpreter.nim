## This file contains the "Pulsar" MIR interpreter. It's a redesign of the previous bytecode analyzer (keyword: analyzer, not interpreter)
## into a more modular and efficient form. You shouldn't import this directly, import `mirage/interpreter/prelude` instead.
##

import std/[math, tables, options, logging]
import bali/runtime/vm/heap/boehm
import bali/runtime/vm/[atom, utils]
import bali/runtime/vm/runtime/[shared, tokenizer, exceptions]
import bali/runtime/vm/runtime/pulsar/[operation, bytecodeopsetconv]
import pkg/pretty

when not defined(mirageNoSimd):
  import nimsimd/sse2
else:
  {.
    warn:
      "SIMD support has been explicitly disabled. There will be visible slowdowns in batch operations. If this was a mistake, check your build configurations for `-d:mirageNoSimd`"
  .}

type
  Clause* = object
    name*: string
    operations*: seq[Operation]

    rollback*: ClauseRollback

  InvalidRegisterRead* = object of Defect

  ClauseRollback* = object
    clause*: int = int.low
    opIndex*: uint = 1

  Registers* = object
    retVal*: Option[JSValue]
    callArgs*: seq[JSValue]

  PulsarInterpreter* = object
    tokenizer: Tokenizer
    currClause: int
    currIndex: uint = 1
    clauses: seq[Clause]
    currJumpOnErr: Option[uint]

    stack*: Table[uint, JSValue]
    locals*: Table[uint, string]
    builtins*: Table[string, proc(op: Operation)]
    errors*: seq[RuntimeException]
    halt*: bool = false
    trace: ExceptionTrace

    registers*: Registers

const SequenceBasedRegisters* = [some(1)]

proc find*(clause: Clause, id: uint): Option[Operation] =
  for op in clause.operations:
    if op.index == id:
      return some op

func getClause*(
    interpreter: PulsarInterpreter, id: Option[int] = none int
): Option[Clause] =
  let id =
    if *id:
      &id
    else:
      interpreter.currClause

  if id <= interpreter.clauses.len - 1 and id > -1:
    some(interpreter.clauses[id])
  else:
    none(Clause)

proc get*(
    interpreter: PulsarInterpreter, id: uint, ignoreLocalityRules: bool = false
): Option[JSValue] =
  if interpreter.stack.contains(id):
    return some(interpreter.stack[id])

proc getClause*(interpreter: PulsarInterpreter, name: string): Option[Clause] =
  for clause in interpreter.clauses:
    if clause.name == name:
      return clause.some()

proc analyze*(interpreter: var PulsarInterpreter) =
  var cTok = interpreter.tokenizer.deepCopy()
  while not interpreter.tokenizer.isEof:
    let
      clause = interpreter.getClause()
      tok = cTok.maybeNext()

    if *tok and (&tok).kind == tkClause:
      interpreter.clauses.add(
        Clause(name: (&tok).clause, operations: @[], rollback: ClauseRollback())
      )
      interpreter.currClause = interpreter.clauses.len - 1
      interpreter.tokenizer.pos = cTok.pos
      continue

    let op = nextOperation interpreter.tokenizer

    if *clause and *op:
      interpreter.clauses[interpreter.currClause].operations.add(&op)
      cTok.pos = interpreter.tokenizer.pos
      continue

    if *tok and (&tok).kind == tkEnd and *clause:
      interpreter.tokenizer.pos = cTok.pos
      continue

{.push checks: on, inline.}
proc addAtom*(interpreter: var PulsarInterpreter, atom: sink MAtom, id: uint) =
  interpreter.stack[id] = atom.addr
  interpreter.locals[id] = interpreter.clauses[interpreter.currClause].name

proc addAtom*(interpreter: var PulsarInterpreter, value: JSValue, id: uint) =
  if id in interpreter.stack:
    # boehmDealloc(interpreter.stack[id])
    discard

  interpreter.stack[id] = value
  interpreter.locals[id] = interpreter.clauses[interpreter.currClause].name

proc hasBuiltin*(interpreter: PulsarInterpreter, name: string): bool =
  name in interpreter.builtins

proc registerBuiltin*(
    interpreter: var PulsarInterpreter, name: string, builtin: proc(op: Operation)
) =
  interpreter.builtins[name] = builtin

proc callBuiltin*(interpreter: PulsarInterpreter, name: string, op: Operation) =
  interpreter.builtins[name](op)

{.pop.}

proc throw*(
    interpreter: var PulsarInterpreter,
    exception: RuntimeException,
    bubbling: bool = false,
) =
  if *interpreter.currJumpOnErr:
    return # TODO: implement error handling

  var exception = deepCopy(exception)

  interpreter.halt = true

  let clause =
    if not bubbling:
      interpreter.getClause(interpreter.currClause.some)
    else:
      interpreter.getClause(exception.clause)

  if *clause and not bubbling:
    exception.operation = interpreter.currIndex
    exception.clause = (&clause).name

  interpreter.errors.add(exception)

  if *clause:
    let
      rollback = (&clause).rollback
      prevClause = interpreter.getClause(rollback.clause.int.some)

    var bubblingException = deepCopy(exception)
    bubblingException.operation = rollback.opIndex

    if *prevClause:
      bubblingException.clause = (&prevClause).name
      interpreter.throw(bubblingException, bubbling = true)

  var newTrace = ExceptionTrace(
    prev:
      if interpreter.trace != nil:
        interpreter.trace.some()
      else:
        none(ExceptionTrace),
    clause: interpreter.currClause,
    index: interpreter.currIndex,
    exception: exception,
  )

  if interpreter.trace != nil:
    interpreter.trace.next = some(newTrace)

  interpreter.trace = newTrace

proc resolve*(interpreter: PulsarInterpreter, clause: Clause, op: var Operation) =
  let mRawArgs = op.rawArgs
  op.arguments.reset()

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
  of AddInt, AddStr, SubInt, MultInt, DivInt, PowerInt, MultFloat, DivFloat, PowerFloat,
      AddFloat, SubFloat:
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
  of Add, Mult, Div, Sub:
    for x in 1 .. 3:
      op.arguments &=
        op.consume(
          Integer, OpCodeToString[op.opCode] & " expects an integer at position " & $x
        )
  of Return:
    op.arguments &= op.consume(Integer, "RETURN expects an integer at position 1")
  of SetCapList:
    op.arguments &= op.consume(Integer, "SCAPL expects an integer at position 1")

    op.arguments &= op.consume(Integer, "SCAPL expects an integer at position 2")
  of JumpOnError:
    op.arguments &= op.consume(Integer, "JMPE expects an integer at position 1")
  of PopList, PopListPrefix:
    for x in 1 .. 2:
      op.arguments &=
        op.consume(
          Integer, OpCodeToString[op.opCode] & " expects an integer at position " & $x
        )
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
  of Mult3xBatch:
    for i in 1 .. 7:
      op.arguments &=
        op.consume(Integer, "THREEMULT expects an integer at position " & $i)
  of Mult2xBatch:
    for i in 1 .. 5:
      op.arguments &= op.consume(
        Integer, "TWOMULT expects an integer at position " & $i
      )
  of MarkHomogenous:
    op.arguments &= op.consume(Integer, "MARKHOMO expects an integer at position 1")
  of LoadNull:
    op.arguments &= op.consume(Integer, "LOADN expects an integer at position 1")
  of MarkGlobal:
    op.arguments &= op.consume(Integer, "GLOB expects an integer at position 1")
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

  op.rawArgs = mRawArgs

proc generateTraceback*(interpreter: PulsarInterpreter): Option[string] =
  var
    msg = "Traceback (most recent call last)"
    currTrace = interpreter.trace

  if currTrace == nil:
    return

  # traverse down the tree to find the bottom of the stack trace
  while currTrace != nil:
    if *currTrace.prev:
      currTrace = &currTrace.prev
    else:
      break

  # TODO: optimize this a bit, we could just cache the traces as we're traversing the tree downwards
  while true:
    let clause = interpreter.getClause(currTrace.clause.some)
    assert *clause, "No clause found with ID: " & $currTrace.clause

    let op = (&clause).find(currTrace.index)

    let line =
      # FIXME: weird stuff
      if currTrace.exception.operation < 2:
        currTrace.exception.operation
      else:
        currTrace.exception.operation - 1

    if not *op:
      msg &= "\n\tClause \"" & currTrace.exception.clause & "\", " & $(line)

      if *currTrace.next:
        currTrace = &currTrace.next
      else:
        msg &=
          "\n\t\t<uncomputable operation>\n\n " & $typeof(currTrace.exception) & ": " &
          currTrace.exception.message & '\n'
        break
    else:
      var operation = &op
      interpreter.resolve(&clause, operation)

      msg &= "\n\tClause \"" & currTrace.exception.clause & "\", operation " & $(line)

      if *currTrace.next:
        currTrace = &currTrace.next
      else:
        msg &=
          "\n\t\t" & operation.expand() & "\n\n" & $typeof(currTrace.exception) & ": " &
          currTrace.exception.message & '\n'
        break

  some(msg)

proc appendAtom*(interpreter: var PulsarInterpreter, src, dest: uint) =
  let
    a = interpreter.get(src)
    b = interpreter.get(dest)

  if not *a or not *b:
    return

  var
    satom = &a
    datom = &b

  case satom.kind
  of Integer:
    if datom.kind != Integer:
      interpreter.throw(wrongType(Integer, datom.kind))
      return

    let
      n1 = &satom.getInt()
      n2 = &datom.getInt()

    var aiAtom = integer(n1 + n2)

    interpreter.addAtom(aiAtom, src)
  of String:
    let
      str1 = &satom.getStr()
      str2 = &datom.getStr()

    var asAtom = str(str1 & str2)

    interpreter.addAtom(asAtom, src)
  of Sequence:
    let
      seq1 = &satom.getSequence()
      seq2 = &datom.getSequence()

    var asAtom = sequence(seq1 & seq2)

    interpreter.addAtom(asAtom, src)
  else:
    discard

proc zeroOut*(interpreter: var PulsarInterpreter, index: uint) {.inline.} =
  ## Remove a stack index.
  boehmDealloc(interpreter.stack[index])
  interpreter.stack.del(index)

proc swap*(interpreter: var PulsarInterpreter, a, b: int) {.inline.} =
  var
    atomA = interpreter.get(a.uint)
    atomB = interpreter.get(b.uint)

  if not *atomA or not *atomB:
    return

  interpreter.zeroOut(a.uint)
  interpreter.zeroOut(b.uint)

  interpreter.addAtom(&atomA, b.uint)
  interpreter.addAtom(&atomB, a.uint)

proc call*(interpreter: var PulsarInterpreter, name: string, op: Operation) =
  if interpreter.hasBuiltin(name):
    interpreter.callBuiltin(name, op)
    inc interpreter.currIndex
  else:
    let interp = interpreter.addr
    let (index, clause) = (
      proc(): tuple[index: int, clause: Option[Clause]] {.gcsafe.} =
        for i, cls in interp[].clauses:
          if cls.name == name:
            return (index: i, clause: some cls)
    )()

    if *clause:
      var newClause = &clause # get the new clause

      # setup rollback points
      newClause.rollback.clause = interpreter.currClause # points to current clause
      newClause.rollback.opIndex = interpreter.currIndex + 1
      # otherwise we'll get stuck in an infinite recursion

      # set clause pointer to new index
      interpreter.currClause = index
      interpreter.clauses[index] = newClause # store clause w/ rollback data to clauses
      interpreter.currIndex = 1
      # set execution op index to 0 to start from the beginning
    else:
      raise newException(ValueError, "Reference to unknown clause: " & name)

  if gcStats.pressure > 0.9f:
    boehmGCFullCollect()

proc execute*(interpreter: var PulsarInterpreter, op: var Operation) =
  when not defined(mirageNoJit):
    inc op.called

  case op.opCode
  of LoadStr:
    interpreter.addAtom(op.arguments[1], (&op.arguments[0].getInt()).uint)
    inc interpreter.currIndex
  of LoadInt:
    interpreter.addAtom(op.arguments[1], (&op.arguments[0].getInt()).uint)
    inc interpreter.currIndex
  of AddInt, AddStr:
    interpreter.appendAtom(
      (&op.arguments[0].getInt()).uint, (&op.arguments[1].getInt()).uint
    )
    inc interpreter.currIndex
  of Equate:
    var
      prev = interpreter.get(uint(&op.arguments[0].getInt()))
      accumulator = false

    for arg in op.arguments[1 ..< op.arguments.len]:
      let value = interpreter.get(uint(&arg.getInt()))

      if not *value:
        break

      accumulator = (&value).hash == (&prev).hash
      prev = value
      if not accumulator:
        break

    if accumulator:
      inc interpreter.currIndex
    else:
      interpreter.currIndex += 2
  of Jump:
    if gcStats.pressure > 0.9f:
      # Assuming we're in a while-loop, perhaps perform a collection
      # the GC pressure is high so it's best we try to conserve memory
      # until this memory intensive loop ends
      boehmGCFullCollect()

    let pos = op.arguments[0].getInt()

    if not *pos:
      inc interpreter.currIndex
      return

    interpreter.currIndex = (&pos).uint
  of Return:
    let clause = interpreter.getClause()

    if not *clause:
      inc interpreter.currIndex
      return

    let idx = (&op.arguments[0].getInt()).uint

    # write the return value to the `retVal` register
    interpreter.registers.retVal = interpreter.get(idx)

    # revert back to where we left off in the previous clause (or exit if this was the final clause - that's handled by the logic in `run`)
    interpreter.currClause = (&clause).rollback.clause
    interpreter.currIndex = (&clause).rollback.opIndex
  of Call:
    let name = &op.arguments[0].getStr()
    interpreter.call(name, op)
  of LoadUint:
    interpreter.addAtom(op.arguments[1], (&op.arguments[0].getInt()).uint)
    inc interpreter.currIndex
  of LoadList:
    interpreter.addAtom(sequence @[], (&op.arguments[0].getInt()).uint)
    inc interpreter.currIndex
  of AddList:
    let
      pos = (&op.arguments[0].getInt()).uint
      curr = interpreter.get(pos)
      source = interpreter.get((&op.arguments[1].getInt()).uint)

    if not *curr or not *source:
      inc interpreter.currIndex
      return

    var list = &curr

    if list.kind != Sequence:
      inc interpreter.currIndex
      return # TODO: type errors

    list.sequence.add((&source)[])

    interpreter.stack[pos] = list
    inc interpreter.currIndex
  of PopList:
    let
      pos = (&op.arguments[0].getInt()).uint
      curr = interpreter.get(pos)

    if not *curr:
      inc interpreter.currIndex
      return

    var list = &curr

    if list.kind != Sequence or list.sequence.len < 1:
      inc interpreter.currIndex
      return

    let atom = list.sequence.pop()
    interpreter.addAtom(atom, (&op.arguments[1].getInt()).uint)
    interpreter.stack[pos] = list
    inc interpreter.currIndex
  of PopListPrefix:
    let
      pos = (&op.arguments[0].getInt()).uint
      curr = interpreter.get(pos)

    if not *curr:
      inc interpreter.currIndex
      return

    var list = &curr

    if list.kind != Sequence or list.sequence.len < 1:
      inc interpreter.currIndex
      return

    let atom = list.sequence[0]
    list.sequence.del(0)

    interpreter.addAtom(atom, (&op.arguments[1].getInt()).uint)
    interpreter.stack[pos] = list
    inc interpreter.currIndex
  of LoadBool:
    interpreter.addAtom(op.arguments[1], (&op.arguments[0].getInt()).uint)
    inc interpreter.currIndex
  of Swap:
    let
      a = &op.arguments[0].getInt()
      b = &op.arguments[1].getInt()

    interpreter.swap(a, b)
    inc interpreter.currIndex
  of SubInt:
    let
      aIdx = &op.arguments[0].getInt()
      bIdx = &op.arguments[1].getInt()

      a = interpreter.get(aIdx.uint)
      b = interpreter.get(bIdx.uint)

    if not *a or not *b:
      inc interpreter.currIndex
      return

    let
      aI = (&a).getInt()
      aB = (&b).getInt()

    interpreter.stack[aIdx.uint] = integer(&aI - &aB)
    inc interpreter.currIndex
  of JumpOnError:
    let beforeExecErrors = interpreter.errors.len

    interpreter.currJumpOnErr = some(interpreter.currIndex)
    inc interpreter.currIndex
  of GreaterThanInt:
    if op.arguments.len < 2:
      inc interpreter.currIndex
      return

    let
      a = interpreter.get((&op.arguments[0].getInt()).uint)
      b = interpreter.get((&op.arguments[1].getInt()).uint)

    if not *a or not *b:
      return

    let
      aI = (&a).getInt()
      bI = (&b).getInt()

    if not *aI or not *bI:
      return

    if &aI > &bI:
      inc interpreter.currIndex
    else:
      interpreter.currIndex += 2
  of LesserThanInt:
    if op.arguments.len < 2:
      inc interpreter.currIndex
      return

    let
      a = interpreter.get((&op.arguments[0].getInt()).uint)
      b = interpreter.get((&op.arguments[1].getInt()).uint)

    if not *a or not *b:
      return

    let
      aI = (&a).getInt()
      bI = (&b).getInt()

    if not *aI or not *bI:
      return

    if &aI < &bI:
      inc interpreter.currIndex
    else:
      interpreter.currIndex += 2
  of LoadObject:
    interpreter.addAtom(obj(), (&op.arguments[0].getInt()).uint)
    inc interpreter.currIndex
  of CreateField:
    let oatomIndex = ((&op.arguments[0].getInt()).uint)

    let oatomId = interpreter.get(oatomIndex)

    if not *oatomId:
      inc interpreter.currIndex
      return

    var atom = &oatomId
    let
      fieldIndex = (&op.arguments[1].getInt())
      fieldName = &op.arguments[2].getStr()

    atom.objFields[fieldName] = fieldIndex
    atom.objValues.add(null())

    interpreter.addAtom(atom, oatomIndex)

    inc interpreter.currIndex
  of FastWriteField:
    let
      oatomIndex = (&op.arguments[0].getInt()).uint
      oatomId = interpreter.get(oatomIndex)

    if not *oatomId:
      inc interpreter.currIndex
      return

    var atom = &oatomId
    let fieldIndex = (&op.arguments[1].getInt())

    let toWrite = op.consume(Integer, "", enforce = false, some(op.rawArgs.len - 1))
    atom.objValues[fieldIndex] = toWrite

    interpreter.addAtom(atom, oatomIndex)
    inc interpreter.currIndex
  of WriteField:
    let
      oatomIndex = (&op.arguments[0].getInt()).uint
      oatomId = interpreter.get(oatomIndex)

    if not *oatomId:
      inc interpreter.currIndex
      return

    var
      atom = &oatomId
      fieldIndex = none(int)

    for field, idx in atom.objFields:
      if field == &(op.arguments[1].getStr()):
        fieldIndex = some(idx)

    if not *fieldIndex:
      inc interpreter.currIndex
      return

    let toWrite = op.consume(Integer, "", enforce = false, some(op.rawArgs.len - 1))
    atom.objValues[&fieldIndex] = toWrite

    interpreter.addAtom(atom, oatomIndex)
    inc interpreter.currIndex
  of Add:
    let
      a = &interpreter.get((&op.arguments[0].getInt()).uint)
      b = &interpreter.get((&op.arguments[1].getInt()).uint)
      storeIn = (&op.arguments[2].getInt()).uint

    if a.kind != Integer or b.kind != UnsignedInt:
      interpreter.throw(wrongType(a.kind, Integer))

    if b.kind != Integer or b.kind != UnsignedInt:
      interpreter.throw(wrongType(a.kind, Integer))

    # FIXME: properly handle this garbage
    let
      aI =
        case a.kind
        of Integer:
          &a.getInt()
        else:
          (&a.getUint()).int

      bI =
        case b.kind
        of Integer:
          &b.getInt()
        else:
          (&b.getUint()).int

    interpreter.addAtom(integer(aI + bI), storeIn)
  of CrashInterpreter:
    when defined(release):
      raise newException(
        CatchableError, "Encountered `CRASHINTERP` during execution; abort!"
      )
  of Increment:
    let atom = &interpreter.get((&op.arguments[0].getInt()).uint)

    case atom.kind
    of Integer:
      interpreter.addAtom(integer(&atom.getInt() + 1), (&op.arguments[0].getInt()).uint)
    of UnsignedInt:
      interpreter.addAtom(
        uinteger(&atom.getUint() + 1), (&op.arguments[0].getInt()).uint
      )
    else:
      discard

    inc interpreter.currIndex
  of Decrement:
    let atom = &interpreter.get((&op.arguments[0].getInt()).uint)

    case atom.kind
    of Integer:
      interpreter.addAtom(integer(&atom.getInt() - 1), (&op.arguments[0].getInt()).uint)
    of UnsignedInt:
      interpreter.addAtom(
        uinteger(&atom.getUint() - 1), (&op.arguments[0].getInt()).uint
      )
    else:
      discard

    inc interpreter.currIndex
  of Mult2xBatch:
    let
      pos1 = &op.arguments[0].getInt()
      pos2 = &op.arguments[1].getInt()

    var
      vec1 = [
        &(&interpreter.get((&op.arguments[2].getInt()).uint)).getInt(),
        &(&interpreter.get((&op.arguments[3].getInt()).uint)).getInt(),
      ]
      vec2 = [
        &(&interpreter.get((&op.arguments[4].getInt()).uint)).getInt(),
        &(&interpreter.get((&op.arguments[5].getInt()).uint)).getInt(),
      ]

    var res: array[2, int]

    when not defined(mirageNoSimd):
      # fast path via SIMD
      let
        svec1 = mm_loadu_si128(vec1.addr)
        svec2 = mm_loadu_si128(vec2.addr)
        simdMulRes = mm_mullo_epi16(svec1, svec2)

      mm_storeu_si128(res.addr, simdMulRes)
    else:
      # slow path
      res = [vec1[0] * vec2[0], vec1[1] * vec2[1]]

    interpreter.addAtom(integer(res[0]), pos1.uint)
    interpreter.addAtom(integer(res[1]), pos2.uint)
  of Mult3xBatch:
    let
      pos1 = &op.arguments[0].getInt()
      pos2 = &op.arguments[1].getInt()
      pos3 = &op.arguments[2].getInt()

    var
      vec1 = [
        &(&interpreter.get((&op.arguments[3].getInt()).uint)).getInt(),
        &(&interpreter.get((&op.arguments[4].getInt()).uint)).getInt(),
        &(&interpreter.get((&op.arguments[5].getInt()).uint)).getInt(),
      ]

      vec2 = [
        &(&interpreter.get((&op.arguments[6].getInt()).uint)).getInt(),
        &(&interpreter.get((&op.arguments[7].getInt()).uint)).getInt(),
        &(&interpreter.get((&op.arguments[8].getInt()).uint)).getInt(),
      ]

      res: array[3, int]

    when not defined(mirageNoSimd):
      # fast path via SIMD
      let
        svec1 = mm_loadu_si128(vec1.addr)
        svec2 = mm_loadu_si128(vec2.addr)
        simdMulRes = mm_mullo_epi16(svec1, svec2)

      mm_storeu_si128(res.addr, simdMulRes)
    else:
      res = [vec1[0] * vec2[0], vec1[1] * vec2[1], vec1[2] * vec2[2]]

    interpreter.addAtom(integer(res[0]), pos1.uint)
    interpreter.addAtom(integer(res[1]), pos2.uint)
    interpreter.addAtom(integer(res[2]), pos3.uint)
  of MarkHomogenous:
    let idx = (&op.arguments[0].getInt()).uint
    var atom = &interpreter.get(idx)

    interpreter.addAtom(atom, idx)
    inc interpreter.currIndex
  of LoadNull:
    let idx = (&op.arguments[0].getInt()).uint

    interpreter.addAtom(null(), idx)
    inc interpreter.currIndex
  of MarkGlobal:
    let idx = (&op.arguments[0].getInt()).uint
    interpreter.locals.del(idx)
    inc interpreter.currIndex
  of ReadRegister:
    let
      idx = (&op.arguments[0].getInt()).uint
      regIndex = if op.arguments.len > 2: 2 else: 1
      regId = (&op.arguments[regIndex].getInt())

    case regId
    of 0:
      # 0 - retval register
      interpreter.addAtom(
        if *interpreter.registers.retVal:
          &interpreter.registers.retVal
        else:
          obj(),
        idx,
      )
    of 1:
      # 1 - callargs register
      debug "vm: read call arguments register (#1); placing index " &
        $(&op.arguments[1].getInt()) & " into stack position " & $idx
      interpreter.addAtom(
        interpreter.registers.callArgs[&op.arguments[1].getInt()], idx
      )
    else:
      raise newException(
        InvalidRegisterRead, "Attempt to read from non-existant register " & $regId
      )

    inc interpreter.currIndex
  of PassArgument:
    # append to callArgs register
    let
      idx = (&op.arguments[0].getInt()).uint
      value = &interpreter.get(idx)

    interpreter.registers.callArgs.add(value)
    inc interpreter.currIndex
  of ResetArgs:
    interpreter.registers.callArgs.reset()
    inc interpreter.currIndex
  of CopyAtom:
    let
      src = (&op.arguments[0].getInt()).uint
      dest = (&op.arguments[1].getInt()).uint

    interpreter.stack[dest] = &interpreter.get(src)
    inc interpreter.currIndex
  of MoveAtom:
    let
      src = (&op.arguments[0].getInt()).uint
      dest = (&op.arguments[1].getInt()).uint

    interpreter.stack[dest] = &interpreter.get(src)
    baliDealloc(interpreter.stack[src])
    interpreter.stack[src] = null()
    inc interpreter.currIndex
  of LoadFloat:
    let
      pos = (&op.arguments[0].getInt()).uint
      value = op.arguments[1]

    interpreter.addAtom(value, pos)
    inc interpreter.currIndex
  of MultInt:
    let
      a = &(&interpreter.get(uint(&op.arguments[0].getInt()))).getInt()
      b = &(&interpreter.get(uint(&op.arguments[1].getInt()))).getInt()
      pos = uint(&op.arguments[0].getInt())

    interpreter.addAtom(integer(a * b), pos)
    inc interpreter.currIndex
  of DivInt:
    let
      a = &(&interpreter.get(uint(&op.arguments[0].getInt()))).getInt()
      b = &(&interpreter.get(uint(&op.arguments[1].getInt()))).getInt()
      pos = uint(&op.arguments[0].getInt())

    if b == 0:
      interpreter.addAtom(floating(Inf), pos)
      inc interpreter.currIndex
      return

    interpreter.addAtom(floating(a / b), pos)
    inc interpreter.currIndex
  of PowerInt:
    let
      a = &(&interpreter.get(uint(&op.arguments[0].getInt()))).getInt()
      b = &(&interpreter.get(uint(&op.arguments[1].getInt()))).getInt()
      pos = uint(&op.arguments[0].getInt())

    interpreter.addAtom(integer(a ^ b), pos)
    inc interpreter.currIndex
  of SubFloat:
    let
      a = &(&interpreter.get(uint(&op.arguments[0].getInt()))).getFloat()
      b = &(&interpreter.get(uint(&op.arguments[1].getInt()))).getFloat()
      pos = uint(&op.arguments[0].getInt())

    interpreter.addAtom(floating(a - b), pos)
    inc interpreter.currIndex
  of AddFloat:
    let
      a = &(&interpreter.get(uint(&op.arguments[0].getInt()))).getFloat()
      b = &(&interpreter.get(uint(&op.arguments[1].getInt()))).getFloat()
      pos = uint(&op.arguments[0].getInt())

    interpreter.addAtom(floating(a + b), pos)
    inc interpreter.currIndex
  of DivFloat:
    let
      a = &(&interpreter.get(uint(&op.arguments[0].getInt()))).getFloat()
      b = &(&interpreter.get(uint(&op.arguments[1].getInt()))).getFloat()
      pos = uint(&op.arguments[0].getInt())

    if b == 0f:
      interpreter.addAtom(floating(Inf), pos)
      inc interpreter.currIndex
      return

    interpreter.addAtom(floating(a / b), pos)
    inc interpreter.currIndex
  of MultFloat:
    let
      a = &(&interpreter.get(uint(&op.arguments[0].getInt()))).getFloat()
      b = &(&interpreter.get(uint(&op.arguments[1].getInt()))).getFloat()
      pos = uint(&op.arguments[0].getInt())

    if b == 0:
      interpreter.addAtom(floating(Inf), pos)
      inc interpreter.currIndex
      return

    interpreter.addAtom(floating(a * b), pos)
    inc interpreter.currIndex
  of PowerFloat:
    let
      a = &(&interpreter.get(uint(&op.arguments[0].getInt()))).getFloat()
      b = int(&(&interpreter.get(uint(&op.arguments[1].getInt()))).getFloat())
      pos = uint(&op.arguments[0].getInt())

    interpreter.addAtom(floating(a ^ b), pos)
    inc interpreter.currIndex
  of ZeroRetval:
    interpreter.registers.retVal = none(JSValue)
    inc interpreter.currIndex
  of LoadBytecodeCallable:
    let
      index = uint(&op.arguments[0].getInt())
      clause = &op.arguments[1].getStr()

    interpreter.addAtom(bytecodeCallable(clause), index)
    inc interpreter.currIndex
  of ExecuteBytecodeCallable:
    let callable = &getBytecodeClause(&interpreter.get(uint(&op.arguments[0].getInt())))

    interpreter.call(callable, op)
  of LoadUndefined:
    interpreter.addAtom(undefined(), uint(&op.arguments[0].getInt()))
    inc interpreter.currIndex
  of GreaterThanEqualInt:
    if op.arguments.len < 2:
      inc interpreter.currIndex
      return

    let
      a = interpreter.get((&op.arguments[0].getInt()).uint)
      b = interpreter.get((&op.arguments[1].getInt()).uint)

    if not *a or not *b:
      return

    let
      aI = (&a).getInt()
      bI = (&b).getInt()

    if not *aI or not *bI:
      return

    if &aI >= &bI:
      inc interpreter.currIndex
    else:
      interpreter.currIndex += 2
  of LesserThanEqualInt:
    if op.arguments.len < 2:
      inc interpreter.currIndex
      return

    let
      a = interpreter.get((&op.arguments[0].getInt()).uint)
      b = interpreter.get((&op.arguments[1].getInt()).uint)

    if not *a or not *b:
      return

    let
      aI = (&a).getInt()
      bI = (&b).getInt()

    if not *aI or not *bI:
      return

    print &ai
    print &bi

    if &aI <= &bI:
      inc interpreter.currIndex
    else:
      interpreter.currIndex += 2
  else:
    when defined(release):
      inc interpreter.currIndex
    else:
      echo "Unimplemented opcode: " & $op.opCode
      quit(1)

proc setEntryPoint*(interpreter: var PulsarInterpreter, name: string) {.inline.} =
  for i, clause in interpreter.clauses:
    if clause.name == name:
      interpreter.currClause = i
      return

  raise newException(ValueError, "setEntryPoint(): cannot find clause \"" & name & "\"")

proc run*(interpreter: var PulsarInterpreter) =
  while not interpreter.halt:
    let cls = interpreter.getClause()

    if not *cls:
      break

    let
      clause = &cls
      op = clause.find(interpreter.currIndex)

    if not *op:
      if clause.rollback.clause == int.low:
        break

      interpreter.currClause = clause.rollback.clause
      interpreter.currIndex = clause.rollback.opIndex
      continue

    var operation = &op

    interpreter.resolve(clause, operation)
    interpreter.execute(operation)

proc newPulsarInterpreter*(source: string): PulsarInterpreter =
  var interp = PulsarInterpreter(
    tokenizer: newTokenizer(source),
    clauses: @[],
    builtins: initTable[string, proc(op: Operation)](),
    locals: initTable[uint, string](),
    stack: initTable[uint, JSValue](),
  )
  interp.registerBuiltin(
    "print",
    proc(op: Operation) =
      for i, x in op.arguments:
        if i == 0:
          continue

        let val = interp.get((&x.getInt()).uint)

        if *val:
          echo (&val).crush("", quote = false)
    ,
  )

  interp

export Operation
