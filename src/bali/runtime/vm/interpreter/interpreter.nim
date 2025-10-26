## Bytecode interpreter implementation
##
## Copyright (C) 2024-2025 Trayambak Rai (xtrayambak at disroot dot org)

import std/[math, tables, strutils, options]
import pkg/bali/runtime/vm/heap/[manager, boehm]
import pkg/bali/runtime/vm/[atom, debugging, exceptions]
import pkg/bali/runtime/vm/interpreter/[operation, types, resolver]
import pkg/bali/runtime/vm/ir/shared
import pkg/bali/runtime/normalize
import pkg/bali/runtime/compiler/base
import pkg/bali/runtime/atom_helpers
import pkg/[shakar]

when hasJITSupport:
  when defined(amd64):
    import bali/runtime/compiler/amd64/[common, baseline, midtier]
  else:
    {.
      error:
        "Platform is marked as having JIT support but the VM is not introduced to the codegen module."
    .}

const
  BaliVMInitialPreallocatedStackSize* {.intdefine.} = 16
  BaliVMPreallocatedStackSize* {.intdefine.} = 4

type
  Registers* = object
    retVal*: Option[JSValue]
    callArgs*: seq[JSValue]
    error*: Option[JSValue]

  Builtin* = proc(op: Operation) {.gcsafe.}

  EquationHook* = proc(a, b: JSValue): bool {.gcsafe.}
  TypeErrorHook* = proc() {.gcsafe.}
  AddAtomsOpImpl* = proc(a, b: JSValue): JSValue {.gcsafe.}

  PulsarInterpreter* = object
    currClause: int
    currIndex*: uint = 0
    clauses: seq[Clause]
    currJumpOnErr: Option[uint]

    stack*: seq[JSValue]
    builtins*: Table[string, proc(op: Operation) {.gcsafe.}]
    errors*: seq[RuntimeException]
    halt*: bool = false
    trace*: ExceptionTrace

    heapManager*: HeapManager

    registers*: Registers

    equationHook*: EquationHook
    typeErrorHook*: TypeErrorHook
    addOpImpl*: AddAtomsOpImpl

    when defined(amd64):
      baseline*: BaselineJIT
      midtier*: MidtierJIT
      useJit*: bool = true

    trapped*: bool = false
    runningCompiled*: bool = false
      ## `true` if the current code segment is compiled, `false` if it's interpreted
    profTotalFrames: uint64

    #               clause      op index        error     source position/line
    #                  V             V            V               V
    sourceMap*: Table[string, Table[uint, tuple[message: string, line: uint]]]

proc `=destroy`*(vm: PulsarInterpreter) =
  # FIXME: Why is this called for no reason?
  # I think we're somehow confusing ORC.
  discard

proc find*(clause: Clause, id: uint): Option[Operation] =
  vmd "find-op-in-clause", "target = " & $id & "; len = " & $clause.operations.len
  if clause.operations.len.uint <= id:
    vmd "find-op-in-clause", "id is beyond op len of " & $clause.operations.len.uint
    return

  vmd "find-op-in-clause", "found op: " & $clause.operations[id].opcode
  some(clause.operations[id])

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
    interpreter: PulsarInterpreter, id: int, ignoreLocalityRules: bool = false
): Option[JSValue] =
  if id < interpreter.stack.len:
    return some(interpreter.stack[id])

proc getClause*(interpreter: PulsarInterpreter, name: string): Option[Clause] =
  for clause in interpreter.clauses:
    if clause.name == name:
      return clause.some()

{.push checks: on, inline.}
proc addAtom*(interpreter: var PulsarInterpreter, value: JSValue, id: int) {.cdecl.} =
  if id > interpreter.stack.len - 1:
    # We need to allocate more slots.
    interpreter.stack.setLen(id + BaliVMPreallocatedStackSize)

  interpreter.stack[id] = value

proc hasBuiltin*(interpreter: PulsarInterpreter, name: string): bool =
  name in interpreter.builtins

proc registerBuiltin*(
    interpreter: var PulsarInterpreter, name: string, builtin: Builtin
) =
  interpreter.builtins[name] = builtin

proc callBuiltin*(
    interpreter: PulsarInterpreter, name: string, op: Operation
) {.gcsafe.} =
  interpreter.builtins[name](op)

{.pop.}

proc throw*(
    interpreter: var PulsarInterpreter,
    exception: RuntimeException,
    bubbling: bool = false,
) =
  if *interpreter.currJumpOnErr:
    interpreter.currIndex = &interpreter.currJumpOnErr - 2
    interpreter.currJumpOnErr = none(uint)
    return

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
    let rollback = (&clause).rollback

    let prevClause = interpreter.getClause(rollback.clause.int.some)

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

    let cls = &clause
    let op = cls.find(currTrace.index)

    let line =
      # FIXME: weird stuff
      if currTrace.exception.operation < 2:
        currTrace.exception.operation
      else:
        currTrace.exception.operation - 1

    if not *op:
      msg &= "\n\tFunction <" & currTrace.exception.clause & '>'

      if *currTrace.next:
        currTrace = &currTrace.next
      else:
        msg &=
          "\n\t\t<uncomputable operation>\n\n " & $typeof(currTrace.exception) & ": " &
          currTrace.exception.message & '\n'
        break
    else:
      let operation = &op

      var
        sourceLine: string
        codeLine: uint

      let opIndex = operation.index
      var
        minRange = opIndex.int
        maxRange = 0

      for opIdx, sourceInfo in interpreter.sourceMap[cls.name]:
        let idx = opIdx.int
        if minRange == -1:
          minRange = idx
          continue

        if maxRange < idx:
          maxRange = idx
          continue

        if minRange > idx:
          minRange = idx
          continue

      for opIdx, sourceInfo in interpreter.sourceMap[cls.name]:
        let opIdx = opIdx.int
        if opIdx == minRange or opIdx == maxRange:
          sourceLine = sourceInfo.message
          codeLine = sourceInfo.line
          break

        if opIdx > maxRange:
          continue

        if opIdx < minRange:
          continue

        sourceLine = sourceInfo.message
        codeLine = sourceInfo.line
        break

      msg &= "\n\tFunction <" & currTrace.exception.clause & ">, line " & $(
        codeLine + 1
      )

      if *currTrace.next:
        currTrace = &currTrace.next
      else:
        if sourceLine.len < 1:
          sourceLine = "<failed to find mapped source, report this as a bug>"

        msg &= "\n\t\t" & sourceLine
        msg &= "\n\t\t" & repeat('^', sourceLine.len - 1)
        msg &= "\n\n" & currTrace.exception.message
        break

  some(ensureMove(msg))

proc appendAtom*(interpreter: var PulsarInterpreter, src, dest: int) =
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

    var aiAtom = integer(interpreter.heapManager, n1 + n2)

    interpreter.addAtom(aiAtom, src)
  of String:
    let
      str1 = &satom.getStr()
      str2 = &datom.getStr()

    var asAtom = str(interpreter.heapManager, str1 & str2)

    interpreter.addAtom(asAtom, src)
  of Sequence:
    let
      seq1 = &satom.getSequence()
      seq2 = &datom.getSequence()

    var asAtom = sequence(interpreter.heapManager, seq1 & seq2)

    interpreter.addAtom(asAtom, src)
  else:
    discard

proc zeroOut*(interpreter: var PulsarInterpreter, index: int) {.inline.} =
  ## Remove a stack index.
  boehmDealloc(interpreter.stack[index])
  interpreter.stack.del(index)

proc swap*(interpreter: var PulsarInterpreter, a, b: int) {.inline.} =
  var
    atomA = interpreter.get(a)
    atomB = interpreter.get(b)

  if not *atomA or not *atomB:
    return

  interpreter.zeroOut(a)
  interpreter.zeroOut(b)

  interpreter.addAtom(&atomA, b)
  interpreter.addAtom(&atomB, a)

proc call*(interpreter: var PulsarInterpreter, name: string, op: Operation) {.gcsafe.} =
  msg "calling function " & name
  msg "trapped? " & $interpreter.trapped

  if interpreter.hasBuiltin(name):
    msg name & " is a builtin, calling it"
    interpreter.callBuiltin(name, op)
    inc interpreter.currIndex
  else:
    msg name & " is not a builtin, finding bytecode clause"
    let (index, clause) = (
      proc(
          interp: PulsarInterpreter
      ): tuple[index: int, clause: Option[Clause]] {.gcsafe.} =
        for i, cls in interp.clauses:
          if cls.name == name or cls.name == normalizeIRName(name):
            # FIXME: Ugly, no good, terrible hack.
            return (index: i, clause: some cls)
    )(interpreter)

    if *clause:
      msg "found bytecode clause " & name
      var newClause = &clause # get the new clause

      # setup rollback points
      newClause.rollback.clause = interpreter.currClause # points to current clause
      newClause.rollback.opIndex = interpreter.currIndex + 1
      # otherwise we'll get stuck in an infinite recursion

      # set clause pointer to new index
      interpreter.currClause = index
      interpreter.clauses[index] = newClause # store clause w/ rollback data to clauses
      interpreter.currIndex = 0
      msg "new op to execute chosen @ " & newClause.name & '/' & $interpreter.currIndex
      # set execution op index to 0 to start from the beginning
    else:
      raise newException(ValueError, "Reference to unknown clause: " & name)

proc invoke*(interpreter: var PulsarInterpreter, value: JSValue) {.gcsafe.} =
  if value.kind == Integer:
    let index = &getInt(value)
    msg "atom is integer/ref to atom: " & $index
    let callable = &interpreter.get(index)

    if callable.kind == BytecodeCallable:
      msg "atom is bytecode segment"
      interpreter.call(&getBytecodeClause(callable), default(Operation))
    elif callable.kind == NativeCallable:
      msg "atom is native segment"
      callable.fn()
      inc interpreter.currIndex
    else:
      interpreter.typeErrorHook()
  elif value.kind == String:
    msg "atom is string/ref to native function"
    interpreter.call(&getStr(value), default(Operation))
  elif value.kind == NativeCallable:
    # FIXME: this is stupid.
    msg "atom is native segment"
    value.fn()
    inc interpreter.currIndex
  elif value.kind == BytecodeCallable:
    # FIXME: this is stupid too
    interpreter.call(&getBytecodeClause(value), default(Operation))
    assert not interpreter.halt
    assert interpreter.trapped
  else:
    raise newException(ValueError, "INVK cannot deal with atom: " & $value.kind)

proc readRegister*(interpreter: var PulsarInterpreter, store, register, index: int) =
  case register
  of 0:
    # 0 - retval register
    msg "read retval register"
    interpreter.addAtom(
      if *interpreter.registers.retVal:
        &interpreter.registers.retVal
      else:
        undefined(interpreter.heapManager),
      store,
    )
    interpreter.registers.retVal = none(JSValue)
  of 1:
    # 1 - callargs register
    msg "read callargs register"
    if interpreter.registers.callArgs.len > index:
      interpreter.addAtom(interpreter.registers.callArgs[index], store)
    else:
      interpreter.addAtom(undefined(interpreter.heapManager), store)
  of 2:
    # 2 - error register
    msg "read error register"
    interpreter.addAtom(
      if *interpreter.registers.error:
        &interpreter.registers.error
      else:
        undefined(interpreter.heapManager),
      store,
    )
  else:
    raise newException(
      InvalidRegisterRead, "Attempt to read from non-existant register " & $register
    )

{.push cdecl, gcsafe.}
proc opCall(interpreter: var PulsarInterpreter, op: var Operation) =
  let name = &op.arguments[0].getStr()
  msg "call " & name
  interpreter.call(name, op)

proc opLoadInt(interpreter: var PulsarInterpreter, op: var Operation) =
  msg "load int"
  interpreter.addAtom(op.arguments[1], &op.arguments[0].getInt())
  inc interpreter.currIndex

proc opLoadStr(interpreter: var PulsarInterpreter, op: var Operation) =
  msg "load str"
  interpreter.addAtom(op.arguments[1], &op.arguments[0].getInt())
  inc interpreter.currIndex

proc opJump(interpreter: var PulsarInterpreter, op: var Operation) =
  let pos = op.arguments[0].getInt()

  if not *pos:
    msg "got jump but index is not given, ignoring"
    inc interpreter.currIndex
    return

  msg "jump to " & $(&pos)
  interpreter.currIndex = (&pos).uint - 1'u

proc opAdd(interpreter: var PulsarInterpreter, op: var Operation) =
  let
    aPos = (&op.arguments[0].getInt())
    a = &interpreter.get(aPos)
    b = &interpreter.get((&op.arguments[1].getInt()))

  if a.kind in {Integer, Float} and b.kind in {Integer, Float}:
    # fast-path for numerics
    interpreter.addAtom(
      floating(interpreter.heapManager, &a.getNumeric() + &b.getNumeric()), aPos
    )
  else:
    # slow-path for everything else
    interpreter.addAtom(interpreter.addOpImpl(a, b), aPos)
  inc interpreter.currIndex

proc opMult(interpreter: var PulsarInterpreter, op: var Operation) =
  let
    posA = (&op.arguments[0].getInt())
    a = &(&interpreter.get(posA)).getNumeric()
    b = &(&interpreter.get((&op.arguments[1].getInt()))).getNumeric()

  interpreter.addAtom(floating(interpreter.heapManager, a * b), posA)
  inc interpreter.currIndex

proc opDiv(interpreter: var PulsarInterpreter, op: var Operation) =
  let
    posA = (&op.arguments[0].getInt())
    a = &(&interpreter.get(posA)).getNumeric()
    b = &(&interpreter.get((&op.arguments[1].getInt()))).getNumeric()

  if b == 0f:
    interpreter.addAtom(floating(interpreter.heapManager, Inf), posA)
    inc interpreter.currIndex
    return

  interpreter.addAtom(floating(interpreter.heapManager, a / b), posA)
  inc interpreter.currIndex

proc opSub(interpreter: var PulsarInterpreter, op: var Operation) =
  let posA = (&op.arguments[0].getInt())

  let a = &(&interpreter.get(posA)).getNumeric()
  let b = &(&interpreter.get((&op.arguments[1].getInt()))).getNumeric()

  interpreter.addAtom(floating(interpreter.heapManager, a - b), posA)
  inc interpreter.currIndex

#[proc opEquate(interpreter: var PulsarInterpreter, op: var Operation) =
  msg "equate"
  var
    prev = interpreter.get(&op.arguments[0].getInt())
    accumulator = false

  for arg in op.arguments[1 ..< op.arguments.len]:
    let value = interpreter.get(&arg.getInt())

    if not *value:
      break

    accumulator = (&value).hash == (&prev).hash
    prev = value
    if not accumulator:
      break

  if accumulator:
    inc interpreter.currIndex
  else:
    interpreter.currIndex += 2]#

proc opReturn(interpreter: var PulsarInterpreter, op: var Operation) =
  let clause = interpreter.getClause()

  if not *clause:
    msg "got return but we are not in any clause"
    inc interpreter.currIndex
    return

  let idx = &getInt(op.arguments[0])

  # write the return value to the `retVal` register
  interpreter.registers.retVal = interpreter.get(idx)

  # revert back to where we left off in the previous clause (or exit if this was the final clause - that's handled by the logic in `run`)

  msg "rolling back to clause " & $((&clause).rollback.clause)
  interpreter.currClause = (&clause).rollback.clause

  msg "rolling back to index " & $((&clause).rollback.opIndex)
  interpreter.currIndex = (&clause).rollback.opIndex

proc opLoadList(interpreter: var PulsarInterpreter, op: var Operation) =
  msg "load list"
  interpreter.addAtom(sequence(interpreter.heapManager, @[]), &op.arguments[0].getInt())
  inc interpreter.currIndex

proc opAddList(interpreter: var PulsarInterpreter, op: var Operation) =
  msg "add list"
  let
    pos = (&op.arguments[0].getInt())
    curr = interpreter.get(pos)
    source = interpreter.get((&op.arguments[1].getInt()))

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

proc opLoadUint(interpreter: var PulsarInterpreter, op: var Operation) =
  msg "load uint"
  interpreter.addAtom(
    integer(interpreter.heapManager, (&op.arguments[1].getInt())),
    &op.arguments[0].getInt(),
  )
  inc interpreter.currIndex

proc opLoadBool(interpreter: var PulsarInterpreter, op: var Operation) =
  msg "load bool"
  interpreter.addAtom(op.arguments[1], (&op.arguments[0].getInt()))
  inc interpreter.currIndex

proc opSwap(interpreter: var PulsarInterpreter, op: var Operation) =
  msg "swap"
  let
    a = &op.arguments[0].getInt()
    b = &op.arguments[1].getInt()

  interpreter.swap(a, b)
  inc interpreter.currIndex

proc opJumpOnError(interpreter: var PulsarInterpreter, op: var Operation) =
  interpreter.currJumpOnErr = some(uint(&op.arguments[0].getInt()))
  inc interpreter.currIndex

proc opGreaterThanInt(interpreter: var PulsarInterpreter, op: var Operation) =
  if op.arguments.len < 2:
    msg "gti: expected 2 args, got " & $op.arguments.len & "; ignoring"
    inc interpreter.currIndex
    return

  let
    a = interpreter.get(&op.arguments[0].getInt())
    b = interpreter.get(&op.arguments[1].getInt())

  if not *a or not *b:
    msg "gti: a is empty=" & $(*a) & "; b is empty=" & $(*b)

    return

  let
    aI = (&a).getNumeric()
    bI = (&b).getNumeric()

  if not *aI or not *bI:
    msg "gti: aI is empty=" & $(*aI) & "; bI is empty=" & $(*bI)
    return

  msg "gti: a=" & $(&aI) & "; b=" & $(&bI)

  if &aI > &bI:
    msg "gti: a > b; pc++"
    inc interpreter.currIndex
  else:
    msg "gti: a <= b; pc += 2"
    interpreter.currIndex += 2

proc opLesserThanInt(interpreter: var PulsarInterpreter, op: var Operation) =
  if op.arguments.len < 2:
    inc interpreter.currIndex
    return

  let
    a = interpreter.get((&op.arguments[0].getInt()))
    b = interpreter.get((&op.arguments[1].getInt()))

  if not *a or not *b:
    return

  let
    aI = (&a).getNumeric()
    bI = (&b).getNumeric()

  if not *aI or not *bI:
    return

  if &aI < &bI:
    inc interpreter.currIndex
  else:
    interpreter.currIndex += 2

proc opLoadObject(interpreter: var PulsarInterpreter, op: var Operation) =
  interpreter.addAtom(obj(interpreter.heapManager), (&op.arguments[0].getInt()))
  inc interpreter.currIndex

proc opCreateField(interpreter: var PulsarInterpreter, op: var Operation) =
  let oatomIndex = ((&op.arguments[0].getInt()))

  let oatomId = interpreter.get(oatomIndex)

  if not *oatomId:
    inc interpreter.currIndex
    return

  var atom = &oatomId
  let
    fieldIndex = (&op.arguments[1].getInt())
    fieldName = &op.arguments[2].getStr()

  atom.objFields[fieldName] = fieldIndex
  atom.objValues.add(null(interpreter.heapManager))

  interpreter.addAtom(atom, oatomIndex)

  inc interpreter.currIndex

proc opFastWriteField(interpreter: var PulsarInterpreter, op: var Operation) =
  let
    oatomIndex = (&op.arguments[0].getInt())
    oatomId = interpreter.get(oatomIndex)

  if not *oatomId:
    inc interpreter.currIndex
    return

  var atom = &oatomId
  let fieldIndex = (&op.arguments[1].getInt())

  let toWrite = op.consume(
    Integer, "", enforce = false, some(op.rawArgs.len - 1), interpreter.heapManager
  )
  atom.objValues[fieldIndex] = toWrite

  interpreter.addAtom(atom, oatomIndex)
  inc interpreter.currIndex

proc opWriteField(interpreter: var PulsarInterpreter, op: var Operation) =
  let
    oatomIndex = (&op.arguments[0].getInt())
    oatomId = interpreter.get(oatomIndex)
    fieldName = &op.arguments[1].getStr()
    sourceAtom = interpreter.get(&op.arguments[2].getInt())

  if not *oatomId:
    inc interpreter.currIndex
    return

  var
    atom = &oatomId
    fieldIndex = none(int)

  for field, idx in atom.objFields:
    if field == fieldName:
      fieldIndex = some(idx)

  if not *fieldIndex:
    atom.objValues &= undefined(interpreter.heapManager)
    fieldIndex = some(atom.objValues.len - 1)

  atom.objValues[&fieldIndex] = &sourceAtom

  interpreter.addAtom(atom, oatomIndex)
  inc interpreter.currIndex

proc opCrashInterpreter(interpreter: var PulsarInterpreter, op: var Operation) =
  when defined(release):
    raise
      newException(CatchableError, "Encountered `CRASHINTERP` during execution; abort!")

proc opInc(interpreter: var PulsarInterpreter, op: var Operation) =
  let atom = &interpreter.get((&op.arguments[0].getInt()))

  case atom.kind
  of Integer:
    interpreter.addAtom(
      integer(interpreter.heapManager, &atom.getInt() + 1), (&op.arguments[0].getInt())
    )
  else:
    interpreter.addAtom(
      floating(interpreter.heapManager, NaN), (&op.arguments[0].getInt())
    ) # If an invalid atom is attempted to be incremented, set its value to NaN.

  inc interpreter.currIndex

proc opDec(interpreter: var PulsarInterpreter, op: var Operation) =
  let atom = &interpreter.get((&op.arguments[0].getInt()))

  case atom.kind
  of Integer:
    interpreter.addAtom(
      integer(interpreter.heapManager, &atom.getInt() - 1), (&op.arguments[0].getInt())
    )
  else:
    interpreter.addAtom(
      floating(interpreter.heapManager, NaN), (&op.arguments[0].getInt())
    ) # If an invalid atom is attempted to be decremented, set its value to NaN.

  inc interpreter.currIndex

proc opLoadNull(interpreter: var PulsarInterpreter, op: var Operation) =
  let idx = (&op.arguments[0].getInt())

  interpreter.addAtom(null(interpreter.heapManager), idx)
  inc interpreter.currIndex

proc opReadReg(interpreter: var PulsarInterpreter, op: var Operation) =
  let
    idx = (&op.arguments[0].getInt())
    register = (&op.arguments[1].getInt())
    index =
      if op.arguments.len > 2:
        (&op.arguments[2].getInt())
      else:
        0

  msg "idx: " & $idx & ", register: " & $register & ", index: " & $index
  interpreter.readRegister(idx, register, index)
  inc interpreter.currIndex

proc opPassArg(interpreter: var PulsarInterpreter, op: var Operation) =
  # append to callArgs register
  let idx = (&op.arguments[0].getInt())
  msg "passing to args register: " & $idx
  let value = &interpreter.get(idx)

  interpreter.registers.callArgs.add(value)
  inc interpreter.currIndex

proc opResetArgs(interpreter: var PulsarInterpreter, op: var Operation) =
  interpreter.registers.callArgs.reset()
  inc interpreter.currIndex

proc opCopyAtom(interpreter: var PulsarInterpreter, op: var Operation) =
  let
    src = (&op.arguments[0].getInt())
    dest = (&op.arguments[1].getInt())

  msg "copy " & $src & " -> " & $dest

  interpreter.addAtom(&interpreter.get(src), dest)
  inc interpreter.currIndex

proc opMoveAtom(interpreter: var PulsarInterpreter, op: var Operation) =
  let
    src = (&op.arguments[0].getInt())
    dest = (&op.arguments[1].getInt())

  interpreter.stack[dest] = &interpreter.get(src)
  interpreter.stack[src] = null(interpreter.heapManager)
  inc interpreter.currIndex

proc opLoadFloat(interpreter: var PulsarInterpreter, op: var Operation) =
  let
    pos = (&op.arguments[0].getInt())
    value = op.arguments[1]

  interpreter.addAtom(value, pos)
  inc interpreter.currIndex

proc opZeroRetval(interpreter: var PulsarInterpreter, op: var Operation) =
  msg "zero retval"
  interpreter.registers.retVal = none(JSValue)
  inc interpreter.currIndex

proc opLoadBytecodeCallable(interpreter: var PulsarInterpreter, op: var Operation) =
  msg "load bytecode segment"
  let
    index = (&op.arguments[0].getInt())
    clause = &op.arguments[1].getStr()

  msg "index is " & $index
  msg "clause is " & clause

  interpreter.addAtom(bytecodeCallable(interpreter.heapManager, clause), index)
  inc interpreter.currIndex

proc opExecuteBytecodeCallable(interpreter: var PulsarInterpreter, op: var Operation) =
  msg "exec bytecode segment"
  let callable = &getBytecodeClause(&interpreter.get((&op.arguments[0].getInt())))

  interpreter.call(callable, op)

proc opLoadUndefined(interpreter: var PulsarInterpreter, op: var Operation) =
  msg "load undefined"
  interpreter.addAtom(undefined(interpreter.heapManager), (&op.arguments[0].getInt()))
  inc interpreter.currIndex

proc opGreaterThanEqualInt(interpreter: var PulsarInterpreter, op: var Operation) =
  if op.arguments.len < 2:
    inc interpreter.currIndex
    return

  let
    a = interpreter.get((&op.arguments[0].getInt()))
    b = interpreter.get((&op.arguments[1].getInt()))

  if not *a or not *b:
    return

  let
    aI = (&a).getNumeric()
    bI = (&b).getNumeric()

  if not *aI or not *bI:
    inc interpreter.currIndex
    return

  if &aI >= &bI:
    inc interpreter.currIndex
  else:
    interpreter.currIndex += 2

proc opLesserThanEqualInt(interpreter: var PulsarInterpreter, op: var Operation) =
  msg "ltei"
  if op.arguments.len < 2:
    msg "expected 2 args, ignoring"
    inc interpreter.currIndex
    return

  let
    a = interpreter.get((&op.arguments[0].getInt()))

    b = interpreter.get((&op.arguments[1].getInt()))

  if not *a or not *b:
    return

  let
    aI = (&a).getNumeric()
    bI = (&b).getNumeric()

  if not *aI or not *bI:
    msg "either of the 2 vals don't exist (or both don't)"
    return

  if &aI <= &bI:
    msg "a <= b; pc++"
    inc interpreter.currIndex
  else:
    msg "a >= b; pc += 2"
    interpreter.currIndex += 2

proc opInvoke(interpreter: var PulsarInterpreter, op: var Operation) =
  interpreter.invoke(op.arguments[0])

proc opPower(interpreter: var PulsarInterpreter, op: var Operation) =
  let
    posA = (&op.arguments[0].getInt())
    a = &(&interpreter.get(posA)).getNumeric()
    b = &(&interpreter.get((&op.arguments[1].getInt()))).getNumeric()

  interpreter.addAtom(floating(interpreter.heapManager, a ^ b.int), posA)
  inc interpreter.currIndex

{.pop.}

proc execute*(interpreter: var PulsarInterpreter, op: var Operation) {.gcsafe.} =
  const OpDispatchTable = [
    opCall, opLoadInt, opLoadStr, opJump, opAdd, opMult, opDiv, opSub, opReturn,
    opLoadList, opAddList, opLoadUint, opLoadBool, opSwap, opJumpOnError,
    opGreaterThanInt, opLesserThanInt, opLoadObject, opCreateField, opFastWriteField,
    opWriteField, opCrashInterpreter, opInc, opDec, opLoadNull, opReadReg, opPassArg,
    opResetArgs, opCopyAtom, opMoveAtom, opLoadFloat, opZeroRetval,
    opLoadBytecodeCallable, opExecuteBytecodeCallable, opLoadUndefined,
    opGreaterThanEqualInt, opLesserThanEqualInt, opInvoke, opPower,
  ]
  OpDispatchTable[cast[uint8](op.opcode)](interpreter, op)

proc setEntryPoint*(interpreter: var PulsarInterpreter, name: string) {.inline.} =
  for i, clause in interpreter.clauses:
    if clause.name == name:
      interpreter.currClause = i
      return

  raise newException(ValueError, "setEntryPoint(): cannot find clause \"" & name & "\"")

proc getCompilationJudgement*(
    interpreter: PulsarInterpreter, clause: Clause
): CompilationJudgement =
  # If we haven't executed 50K frames yet, don't bother
  # optimizing yet. The dispatch ratio for this function will
  # be _obscenely_ high (and inaccurate!) below this threshold.
  #
  # Beyond 50K dispatches, we can start to make educated
  # guesses properly.
  #
  # (Also, we really shouldn't be JITting short-lived
  # scripts anyways.)
  if interpreter.profTotalFrames < 50_000:
    # TODO: Make this a configurable value. Don't make it variable during
    # the runtime for deterministicness' sake.
    return CompilationJudgement.DontCompile

  let dispatchRatio =
    float(clause.profIterationsSpent.int / interpreter.profTotalFrames.int) * 100f

  jitd "profiler",
    "dispatch ratio (" & clause.name & "): " & $dispatchRatio & "% (total frames: " &
      $interpreter.profTotalFrames & "; dominated: " & $clause.profIterationsSpent & ')'

  # These totally scientific and empirical values are used as thresholds to see when a function is worth
  # compiling and with what tier. The source is a secret, just to make sure the likes of Google cannot steal
  # my hard, impressive work.

  if dispatchRatio > 25f and dispatchRatio < 35f:
    return CompilationJudgement.Eligible
  elif dispatchRatio >= 35f:
    return CompilationJudgement.WarmingUp

proc shouldCompile*(
    interpreter: PulsarInterpreter, clause: var Clause
): tuple[gettingCompiled: bool, tier: Option[Tier]] =
  ## This routine takes in a clause and decides
  ## whether it is worthy of getting compiled.
  ##
  ## It also caches the result to prevent the expensive
  ## judgement-calculation logic from being executed
  ## constantly.
  ##
  ## **NOTE**: This routine will _NEVER_ ask for a
  ## clause to be demoted to a lower tier compiler.
  if *clause.cachedJudgement and
      &clause.cachedJudgement == CompilationJudgement.Ineligible:
    return (gettingCompiled: false, tier: none(Tier))

  var judgement = interpreter.getCompilationJudgement(clause)

  # Don't demote highly optimized functions. We already have fast versions,
  # why bother spending time deoptimizing them (or worse,
  # running them in the interpreter) for no reason?
  if *clause.cachedJudgement and judgement < &clause.cachedJudgement:
    judgement = &clause.cachedJudgement
  elif judgement != CompilationJudgement.DontCompile:
    # Only cache the judgement if it isn't due to the code
    # not being warm enough, otherwise code that doesn't
    # get warm enough in a short period of time will never
    # get compiled.
    clause.cachedJudgement = some(judgement)

  # TODO: implement more heuristics
  case judgement
  of CompilationJudgement.Eligible:
    return (gettingCompiled: true, tier: some(Tier.Baseline))
  of CompilationJudgement.WarmingUp:
    return (gettingCompiled: true, tier: some(Tier.Midtier))
  else:
    discard

proc run*(interpreter: var PulsarInterpreter) {.gcsafe.} =
  while not interpreter.halt:
    inc interpreter.profTotalFrames
    vmd "fetch", "new frame " & $interpreter.currIndex
    let cls = interpreter.getClause()

    if not *cls:
      break

    var clause = &cls
    if clause.compiled and interpreter.trapped:
      # FIXME: this is broken!!! :^(
      #        i'm losing my mind and i have zero clue as to why
      #        this is borked.
      break

    vmd "fetch", "got clause " & clause.name

    let op = clause.find(interpreter.currIndex)

    if not *op:
      vmd "rollback", "no op to exec"

      if clause.rollback.clause == int.low:
        vmd "rollback", "clause == int.low; exec has finished"
        break

      vmd "rollback",
        "rollback clause: " & $interpreter.clauses[clause.rollback.clause].name
      vmd "rollback", "rollback pc: " & $clause.rollback.opIndex
      interpreter.currClause = clause.rollback.clause
      interpreter.currIndex = clause.rollback.opIndex
      continue

    # If this clause is considered hot, consider compiling it.
    # TODO: A massive weakness of our JIT is that it currently
    # only accounts for entire functions and not sub-sections of
    # a function. This means that we cannot, say, optimize an infinite loop AT ALL
    # or optimize a really slow loop as soon as viable. Ideally, we should have a way
    # to compile the entire function then make the CPU's IP jump to the compiled
    # instruction where `interpreter.currIndex` is at
    if interpreter.currIndex == 0 and hasJITSupport and interpreter.useJit and
        not interpreter.trapped:
      let (gettingCompiled, tier) = interpreter.shouldCompile(clause)
      if gettingCompiled:
        # TODO: JIT'd functions should be able to call other JIT'd segments
        jitd "fetch",
          "has jit support, compiling clause " & clause.name & " with JIT tier `" & $tier &
            '`'
        let compiled =
          case &tier
          of Tier.Baseline:
            interpreter.baseline.compile(clause)
          of Tier.Midtier:
            interpreter.midtier.compile(clause)
          else:
            unreachable
            none(JITSegment)

        if *compiled:
          clause.compiled = true
          interpreter.clauses[interpreter.currClause] = clause

          vmd "execute", "entering JIT'd segment"
          interpreter.runningCompiled = true
          clause.profIterationsSpent += uint64(clause.operations.len - 2)
          (&compiled)()
          interpreter.runningCompiled = false

          interpreter.currIndex = clause.rollback.opIndex
          interpreter.currClause = clause.rollback.clause

          # We just append all the ops - 2 (1 sub because the len is 1 bigger than the real size, 1 sub because we've already inc'd this value once)
          # interpreter.profTotalFrames += uint64(clause.operations.len - 2)

          vmd "execute",
            "exec'd JIT segment successfully, setting pc to end of clause/" &
              $interpreter.currIndex

          if interpreter.trapped:
            break

          continue
        else:
          jitd "execute",
            "cannot compile segment: " & clause.name & ", falling back to VM"
          clause.cachedJudgement = some(CompilationJudgement.Ineligible)

    var operation = &op
    let index = interpreter.currIndex
    let clauseIndex = interpreter.currClause

    vmd "decode", "pc is " & $index & ", clauseIndex is " & $clauseIndex

    if not operation.resolved:
      vmd "decode", "op is not resolved, resolving"
      resolve(clause, operation, interpreter.heapManager)
      operation.resolved = true

      vmd "decode", "resolved/decoded op"

    vmd "execute", "exec phase beginning"
    interpreter.execute(operation)
    vmd "execute", "exec phase ended, saving op state"
    clause.operations[index] = ensureMove(operation)
    inc clause.profIterationsSpent
    interpreter.clauses[clauseIndex] = move(clause)
    vmd "execute", "saved op state"

when defined(amd64):
  proc initJITForPlatform(
      vm: pointer, heap: HeapManager, callbacks: VMCallbacks, tier: Tier
  ): AMD64Codegen =
    assert(vm != nil)
    assert(hasJITSupport, "Platform does not have a JIT compiler implementation!")

    when defined(amd64):
      case tier
      of Tier.Baseline:
        return initAMD64BaselineCodegen(vm, heap, callbacks)
      of Tier.Midtier:
        return initAMD64MidtierCodegen(vm, heap, callbacks)
      else:
        unreachable

proc tryInitializeJIT(interp: ptr PulsarInterpreter) =
  let callbacks = VMCallbacks(
    addAtom: addAtom,
    getAtom: proc(vm: PulsarInterpreter, index: uint): JSValue {.cdecl.} =
      jitd "callback", "getAtom(index=" & $index & ')'
      let atom = vm.get(index.int)
      return &atom,
    copyAtom: proc(vm: var PulsarInterpreter, source, dest: uint) {.cdecl.} =
      jitd "callback", "copyAtom(source=" & $source & "; dest=" & $dest & ')'
      vm.stack[dest] = &vm.get(source.int),
    resetArgs: proc(vm: var PulsarInterpreter) {.cdecl.} =
      jitd "callback", "resetArgs()"
      vm.registers.callArgs.reset(),
    passArgument: proc(vm: var PulsarInterpreter, index: uint) {.cdecl.} =
      jitd "callback", "passArgument(index=" & $index & ')'
      vm.registers.callArgs.add(&vm.get(index.int)),
    callBytecodeClause: proc(vm: var PulsarInterpreter, name: cstring) {.cdecl.} =
      jitd "callback", "callBytecodeClause(name=" & $name & ')'
      vm.trapped = true
      vm.call($name, default(Operation))
      vm.run(),
    invoke: proc(vm: var PulsarInterpreter, index: int64) {.cdecl.} =
      jitd "callback", "invoke(index=" & $index & ')'
      vm.trapped = true
      vm.invoke(&vm.get(index))
      vm.run()
      vm.trapped = false,
    invokeStr: proc(vm: var PulsarInterpreter, index: cstring) {.cdecl.} =
      jitd "callback", "invokeStr(index=" & $index & ')'
      vm.trapped = true
      vm.invoke(str(vm.heapManager, $index))
      vm.run(),
    readVectorRegister: proc(
        vm: var PulsarInterpreter, store: uint, register: uint, index: uint
    ) {.cdecl.} =
      jitd "callback",
        "readVectorRegister(store=" & $store & "; register=" & $register & "; index=" &
          $index & ')'
      vm.readRegister(store.int, register.int, index.int),
    zeroRetval: proc(vm: var PulsarInterpreter) {.cdecl.} =
      jitd "callback", "zeroRetval()"
      vm.registers.retVal = none(JSValue),
    readScalarRegister: proc(
        vm: var PulsarInterpreter, store, register: uint
    ) {.cdecl.} =
      jitd "callback",
        "readScalarRegister(store=" & $store & "; register=" & $register & ')'
      vm.readRegister(store.int, register.int, 0),
    writeField: proc(
        vm: var PulsarInterpreter, position: int, source: int, field: cstring
    ) {.cdecl.} =
      jitd "callback",
        "writeField(position=" & $position & "; source=" & $source & "; field=" & $field &
          ')'
      let field = $field
      var atom = vm.stack[position]
      let alreadyExists = field in atom.objFields
      let index =
        if alreadyExists:
          atom.objFields[field]
        else:
          atom.objValues.len

      if alreadyExists:
        atom.objValues[index] = &vm.get(source)
      else:
        atom.objValues &= &vm.get(source)
        atom.objFields[field] = index

      vm.stack[position] = atom,
    addRetval: proc(vm: var PulsarInterpreter, value: JSValue) {.cdecl.} =
      jitd "callback", "addRetval()"
      vm.registers.retVal = some(value),
    createField: proc(
        vm: var PulsarInterpreter, target: JSValue, field: cstring
    ) {.cdecl.} =
      jitd "callback", "createField()"
      target[$field] = undefined(vm.heapManager),
    allocEncodedFloat: proc(vm: var PulsarInterpreter, v: int64): JSValue {.cdecl.} =
      jitd "callback", "allocEncodedFloat()"

      floating(vm.heapManager, cast[float64](v)),
    allocFloat: proc(vm: var PulsarInterpreter, v: float64): JSValue {.cdecl.} =
      jitd "callback", "allocFloat()"

      floating(vm.heapManager, v),
    alloc: proc(vm: var PulsarInterpreter, size: int64): pointer {.cdecl.} =
      jitd "callback", "alloc(" & $size & ')'

      vm.heapManager.allocate(size.uint),
    allocBytecodeCallable: proc(
        vm: var PulsarInterpreter, str: cstring
    ): JSValue {.cdecl.} =
      jitd "callback", "allocBytecodeCallable(" & $str & ')'

      bytecodeCallable(vm.heapManager, $str),
    allocStr: proc(vm: var PulsarInterpreter, value: cstring): JSValue {.cdecl.} =
      jitd "callback", "allocStr(" & $value & ')'

      str(vm.heapManager, $value),
    allocInt: proc(vm: var PulsarInterpreter, i: int64): JSValue {.cdecl.} =
      jitd "callback", "allocInt(" & $i & ')'

      integer(vm.heapManager, i),
    getProperty: proc(
        vm: var PulsarInterpreter, value: JSValue, field: cstring
    ): JSValue {.cdecl.} =
      jitd "callback", "getProperty(field: " & $field & ')'
      let field = $field
      if value.contains(field):
        return value[field]

      undefined(vm.heapManager),
    equate: proc(vm: var PulsarInterpreter, a, b: JSValue): bool {.cdecl.} =
      jitd "callback", "equate"
      assert vm.equationHook != nil
      vm.equationHook(a, b),
  )

  when hasJITSupport:
    interp[].baseline = BaselineJIT(
      initJITForPlatform(interp, interp.heapManager, callbacks, Tier.Baseline)
    )

    interp[].midtier = MidtierJIT(
      initJITForPlatform(interp, interp.heapManager, callbacks, Tier.Midtier)
    )

proc feed*(interp: var PulsarInterpreter, modules: seq[CodeModule]) =
  for module in modules:
    var clause: Clause
    clause.name = module.name
    clause.rollback.clause = int.low

    for i, op in module.operations:
      var operation = Operation(
        index: i.uint64 + 1'u64,
        opcode: op.opcode,
        resolved: true,
        arguments: newSeqOfCap[JSValue](op.arguments.len),
      )
      for arg in op.arguments:
        operation.arguments &= atomToJSValue(interp.heapManager, arg)

      clause.operations &= move(operation)

    interp.clauses &= move(clause)

proc newPulsarInterpreter*(clauses: seq[CodeModule]): ptr PulsarInterpreter =
  var interp = cast[ptr PulsarInterpreter](allocShared(sizeof(PulsarInterpreter)))
  interp[] = PulsarInterpreter(
    clauses: @[],
    builtins: initTable[string, Builtin](),
    currIndex: 0'u,
    stack: newSeq[JSValue](BaliVMInitialPreallocatedStackSize),
    trapped: false, # Pre-allocate space for some value pointers
  )
  interp.heapManager = initHeapManager()
  interp[].feed(clauses)
  interp.tryInitializeJIT()

  interp

export Operation
