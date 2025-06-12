## This file contains the "Pulsar" MIR interpreter. It's a redesign of the previous bytecode analyzer (keyword: analyzer, not interpreter)
## into a more modular and efficient form. You shouldn't import this directly, import `mirage/interpreter/prelude` instead.

import std/[math, tables, options]
import bali/runtime/vm/heap/boehm
import bali/runtime/vm/[atom, debugging]
import bali/runtime/vm/runtime/[shared, tokenizer, exceptions]
import bali/runtime/vm/runtime/pulsar/[operation, bytecodeopsetconv, types, resolver]
import bali/runtime/compiler/base
import pkg/[shakar]

when hasJITSupport:
  when defined(amd64):
    import bali/runtime/compiler/amd64/codegen
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

  PulsarInterpreter* = object
    tokenizer: Tokenizer
    currClause: int
    currIndex*: uint = 0
    clauses: seq[Clause]
    currJumpOnErr: Option[uint]

    stack*: seq[JSValue]
    builtins*: Table[string, proc(op: Operation)]
    errors*: seq[RuntimeException]
    halt*: bool = false
    trace: ExceptionTrace

    registers*: Registers

    when defined(amd64):
      jit*: AMD64Codegen
      useJit*: bool = true

    trapped*: bool = false

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
    interpreter: PulsarInterpreter, id: uint, ignoreLocalityRules: bool = false
): Option[JSValue] =
  if id < uint(interpreter.stack.len):
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
proc addAtom*(interpreter: var PulsarInterpreter, value: JSValue, id: uint) {.cdecl.} =
  if id > uint(interpreter.stack.len - 1):
    # We need to allocate more slots.
    interpreter.stack.setLen(id.int + BaliVMPreallocatedStackSize)

  interpreter.stack[id] = value

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
      resolve(&clause, operation)

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
          if cls.name == name:
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
      msg "new op to execute chosen"
      # set execution op index to 0 to start from the beginning
    else:
      raise newException(ValueError, "Reference to unknown clause: " & name)

  if gcStats.pressure > 0.9f:
    boehmGCFullCollect()

proc invoke*(interpreter: var PulsarInterpreter, value: JSValue) =
  if value.kind == Integer:
    let index = uint(&getInt(value))
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
      raise newException(ValueError, "INVK cannot deal with atom: " & $callable.kind)
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

proc execute*(interpreter: var PulsarInterpreter, op: var Operation) =
  when not defined(mirageNoJit):
    inc op.called

  {.computedGoto.}
  case op.opCode
  of LoadStr:
    msg "load str"
    interpreter.addAtom(op.arguments[1], (&op.arguments[0].getInt()).uint)
    inc interpreter.currIndex
  of LoadInt:
    msg "load int"
    interpreter.addAtom(op.arguments[1], (&op.arguments[0].getInt()).uint)
    inc interpreter.currIndex
  of AddInt:
    msg "add int or str"
    interpreter.appendAtom(
      (&op.arguments[0].getInt()).uint, (&op.arguments[1].getInt()).uint
    )
    inc interpreter.currIndex
  of Equate:
    msg "equate"
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
      msg "got jump but index is not given, ignoring"
      inc interpreter.currIndex
      return

    msg "jump to " & $(&pos)
    interpreter.currIndex = (&pos).uint - 1'u
  of Return:
    let clause = interpreter.getClause()

    if not *clause:
      msg "got return but we are not in any clause"
      inc interpreter.currIndex
      return

    let idx = (&op.arguments[0].getInt()).uint
    msg "return; retval overwritten with index " & $idx

    # write the return value to the `retVal` register
    interpreter.registers.retVal = interpreter.get(idx)

    # revert back to where we left off in the previous clause (or exit if this was the final clause - that's handled by the logic in `run`)

    msg "rolling back to clause " & $((&clause).rollback.clause)
    interpreter.currClause = (&clause).rollback.clause

    msg "rolling back to index " & $((&clause).rollback.opIndex)
    interpreter.currIndex = (&clause).rollback.opIndex
  of Call:
    let name = &op.arguments[0].getStr()
    msg "call " & name
    interpreter.call(name, op)
  of LoadUint:
    msg "load uint"
    interpreter.addAtom(
      uinteger((&op.arguments[1].getInt()).uint()), (&op.arguments[0].getInt()).uint
    )
    inc interpreter.currIndex
  of LoadList:
    msg "load list"
    interpreter.addAtom(sequence @[], (&op.arguments[0].getInt()).uint)
    inc interpreter.currIndex
  of AddList:
    msg "add list"
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
  of LoadBool:
    msg "load bool"
    interpreter.addAtom(op.arguments[1], (&op.arguments[0].getInt()).uint)
    inc interpreter.currIndex
  of Swap:
    msg "swap"
    let
      a = &op.arguments[0].getInt()
      b = &op.arguments[1].getInt()

    interpreter.swap(a, b)
    inc interpreter.currIndex
  of SubInt:
    msg "subint"
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
    interpreter.currJumpOnErr = some(uint(&op.arguments[0].getInt()))
    inc interpreter.currIndex
  of GreaterThanInt:
    if op.arguments.len < 2:
      msg "gti: expected 2 args, got " & $op.arguments.len & "; ignoring"
      inc interpreter.currIndex
      return

    let
      a = interpreter.get(&op.arguments[0].getIntOrUint())
      b = interpreter.get(&op.arguments[1].getIntOrUint())

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
      fieldName = &op.arguments[1].getStr()

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
      atom.objValues &= undefined()
      fieldIndex = some(atom.objValues.len - 1)

    let toWrite = op.consume(Integer, "", enforce = false, some(op.rawArgs.len - 1))
    atom.objValues[&fieldIndex] = &interpreter.get(uint(&toWrite.getInt()))

    interpreter.addAtom(atom, oatomIndex)
    inc interpreter.currIndex
  of Add:
    let
      aPos = (&op.arguments[0].getInt()).uint
      a = &interpreter.get(aPos)
      b = &interpreter.get((&op.arguments[1].getInt()).uint)

    interpreter.addAtom(floating(&a.getNumeric() + &b.getNumeric()), aPos)
    inc interpreter.currIndex
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
      interpreter.addAtom(floating(NaN), (&op.arguments[0].getInt()).uint)
        # If an invalid atom is attempted to be incremented, set its value to NaN.

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
      interpreter.addAtom(floating(NaN), (&op.arguments[0].getInt()).uint)
        # If an invalid atom is attempted to be decremented, set its value to NaN.

    inc interpreter.currIndex
  of LoadNull:
    let idx = (&op.arguments[0].getInt()).uint

    interpreter.addAtom(null(), idx)
    inc interpreter.currIndex
  of ReadRegister:
    let
      idx = (&op.arguments[0].getInt()).uint
      regIndex = if op.arguments.len > 2: 2 else: 1
      regId = (&op.arguments[regIndex].getInt())

    msg "idx: " & $idx & ", regIndex: " & $regIndex & ", regId: " & $regId

    case regId
    of 0:
      # 0 - retval register
      msg "read retval register"
      interpreter.addAtom(
        if *interpreter.registers.retVal:
          &interpreter.registers.retVal
        else:
          undefined(),
        idx,
      )
    of 1:
      # 1 - callargs register
      msg "read callargs register"
      interpreter.addAtom(
        interpreter.registers.callArgs[&op.arguments[1].getInt()], idx
      )
    of 2:
      # 2 - error register
      msg "read error register"
      interpreter.addAtom(
        if *interpreter.registers.error:
          &interpreter.registers.error
        else:
          undefined(),
        idx,
      )
    else:
      raise newException(
        InvalidRegisterRead, "Attempt to read from non-existant register " & $regId
      )

    inc interpreter.currIndex
  of PassArgument:
    # append to callArgs register
    let idx = (&op.arguments[0].getInt()).uint
    msg "passing to args register: " & $idx
    let value = &interpreter.get(idx)

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
  of Div:
    let
      posA = uint(&op.arguments[0].getInt())
      a = &(&interpreter.get(posA)).getNumeric()
      b = &(&interpreter.get(uint(&op.arguments[1].getInt()))).getNumeric()

    if b == 0f:
      interpreter.addAtom(floating(Inf), posA)
      inc interpreter.currIndex
      return

    interpreter.addAtom(floating(a / b), posA)
    inc interpreter.currIndex
  of Mult:
    let
      posA = uint(&op.arguments[0].getInt())
      a = &(&interpreter.get(posA)).getNumeric()
      b = &(&interpreter.get(uint(&op.arguments[1].getInt()))).getNumeric()

    interpreter.addAtom(floating(a * b), posA)
    inc interpreter.currIndex
  of Sub:
    let
      posA = uint(&op.arguments[0].getInt())
      a = &(&interpreter.get(posA)).getNumeric()
      b = &(&interpreter.get(uint(&op.arguments[1].getInt()))).getNumeric()

    interpreter.addAtom(floating(a - b), posA)
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
    msg "div float"
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
    msg "mult float"
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
    msg "exp float"
    let
      a = &(&interpreter.get(uint(&op.arguments[0].getInt()))).getFloat()
      b = int(&(&interpreter.get(uint(&op.arguments[1].getInt()))).getFloat())
      pos = uint(&op.arguments[0].getInt())

    interpreter.addAtom(floating(a ^ b), pos)
    inc interpreter.currIndex
  of ZeroRetval:
    msg "zero retval"
    interpreter.registers.retVal = none(JSValue)
    inc interpreter.currIndex
  of LoadBytecodeCallable:
    msg "load bytecode segment"
    let
      index = uint(&op.arguments[0].getInt())
      clause = &op.arguments[1].getStr()

    msg "index is " & $index
    msg "clause is " & clause

    interpreter.addAtom(bytecodeCallable(clause), index)
    inc interpreter.currIndex
  of ExecuteBytecodeCallable:
    msg "exec bytecode segment"
    let callable = &getBytecodeClause(&interpreter.get(uint(&op.arguments[0].getInt())))

    interpreter.call(callable, op)
  of LoadUndefined:
    msg "load undefined"
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
    msg "ltei"
    if op.arguments.len < 2:
      msg "expected 2 args, ignoring"
      inc interpreter.currIndex
      return

    let
      a = interpreter.get((&op.arguments[0].getInt()).uint)
      b = interpreter.get((&op.arguments[1].getInt()).uint)

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
  of Invoke:
    let value = op.arguments[0]

    interpreter.invoke(value)
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
    vmd "fetch", "new frame " & $interpreter.currIndex
    let cls = interpreter.getClause()

    if not *cls:
      break

    var clause = &cls
    if clause.compiled:
      break # FIXME: this is really, really stupid and an awful hack.

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

    # If we can compile this clause, we might as well.
    if interpreter.currIndex == 0 and hasJITSupport and interpreter.useJit and
        not interpreter.trapped:
      # TODO: JIT'd functions should be able to call other JIT'd segments
      vmd "fetch", "has jit support, compiling clause " & clause.name
      let compiled = interpreter.jit.compile(clause)

      if *compiled:
        clause.compiled = true
        interpreter.clauses[interpreter.currClause] = clause

        vmd "execute", "entering JIT'd segment"
        (&compiled)()
        interpreter.currIndex = clause.operations.len.uint
        vmd "execute",
          "exec'd JIT segment successfully, setting pc to end of clause/" &
            $interpreter.currIndex
        continue

    var operation = &op
    let index = interpreter.currIndex
    let clauseIndex = interpreter.currClause

    vmd "decode", "pc is " & $index & ", clauseIndex is " & $clauseIndex

    if not operation.resolved:
      vmd "decode", "op is not resolved, resolving"
      resolve(clause, operation)
      operation.resolved = true

      vmd "decode", "resolved/decoded op"

    vmd "execute", "exec phase beginning"
    interpreter.execute(operation)
    vmd "execute", "exec phase ended, saving op state"
    interpreter.clauses[clauseIndex].operations[index] = ensureMove(operation)
    vmd "execute", "saved op state"

proc initJITForPlatform(vm: pointer, callbacks: VMCallbacks): auto =
  assert(vm != nil)
  assert(hasJITSupport, "Platform does not have a JIT compiler implementation!")

  when defined(amd64):
    return initAMD64CodeGen(vm, callbacks)

proc newPulsarInterpreter*(source: string): ptr PulsarInterpreter =
  var interp = cast[ptr PulsarInterpreter](allocShared(sizeof(PulsarInterpreter)))
  interp[] = PulsarInterpreter(
    tokenizer: newTokenizer(source),
    clauses: @[],
    builtins: initTable[string, proc(op: Operation)](),
    currIndex: 0'u,
    stack: newSeq[JSValue](BaliVMInitialPreallocatedStackSize),
    trapped: false, # Pre-allocate space for some value pointers
  )

  when hasJITSupport:
    interp[].jit = initJITForPlatform(
      interp,
      VMCallbacks(
        addAtom: addAtom,
        getAtom: proc(vm: PulsarInterpreter, index: uint): JSValue {.cdecl.} =
          let atom = vm.get(index)
          return &atom,
        copyAtom: proc(vm: var PulsarInterpreter, source, dest: uint) {.cdecl.} =
          vm.stack[dest] = &vm.get(source),
        resetArgs: proc(vm: var PulsarInterpreter) {.cdecl.} =
          vm.registers.callArgs.reset(),
        passArgument: proc(vm: var PulsarInterpreter, index: uint) {.cdecl.} =
          vm.registers.callArgs.add(&vm.get(index)),
        callBytecodeClause: proc(vm: var PulsarInterpreter, name: cstring) {.cdecl.} =
          vm.trapped = true
          vm.call($name, default(Operation))
          vm.run(),
        invoke: proc(vm: var PulsarInterpreter, index: int64) {.cdecl.} =
          vm.trapped = true
          vm.invoke(&vm.get(index.uint))
          vm.run(),
      ),
    )

  interp[].registerBuiltin(
    "print",
    proc(op: Operation) =
      for i, x in op.arguments:
        if i == 0:
          continue

        let val = interp[].get((&x.getInt()).uint)

        if *val:
          echo (&val).crush("", quote = false)
    ,
  )

  interp

export Operation
