## Bali runtime (MIR emitter)

import std/[options, hashes, logging, strutils, tables, importutils]
import bali/runtime/vm/ir/generator
import bali/runtime/vm/prelude
import bali/grammar/prelude
import bali/internal/sugar
import
  bali/runtime/
    [normalize, types, atom_helpers, arguments, statement_utils, bridge, describe]
import bali/runtime/optimize/[mutator_loops, redundant_loop_allocations]
import bali/runtime/vm/heap/boehm
import bali/runtime/abstract/equating
import bali/stdlib/prelude

privateAccess(PulsarInterpreter)
privateAccess(Runtime)
privateAccess(AllocStats)

proc generateBytecode(
  runtime: Runtime,
  fn: Function,
  stmt: Statement,
  internal: bool = false,
  ownerStmt: Option[Statement] = none(Statement),
  exprStoreIn: Option[string] = none(string),
  parentStmt: Option[Statement] = none(Statement),
  index: Option[uint] = none(uint),
)

proc expand*(runtime: Runtime, fn: Function, stmt: Statement, internal: bool = false) =
  case stmt.kind
  of Call:
    debug "niche: expand Call statement"
    for i, arg in stmt.arguments:
      if arg.kind == cakAtom:
        debug "niche: load immutable value to expand Call's immediate arguments: " &
          arg.atom.crush()
        discard runtime.loadIRAtom(arg.atom)
        runtime.markInternal(stmt, $i)
      elif arg.kind == cakImmediateExpr:
        debug "niche: add code to solve expression to expand Call's immediate arguments"
        runtime.markInternal(arg.expr, $i)
        runtime.generateBytecode(
          fn, arg.expr, internal = true, exprStoreIn = some($i), parentStmt = some(stmt)
        )
  of ConstructObject:
    debug "niche: expand ConstructObject statement"
    for i, arg in stmt.args:
      if arg.kind == cakAtom:
        debug "niche: load immutable value to ConstructObject's immediate arguments: " &
          arg.atom.crush()

        discard runtime.loadIRAtom(arg.atom)
        let name = $hash(stmt) & '_' & $i
        runtime.markInternal(stmt, name)
  of CallAndStoreResult:
    debug "niche: expand CallAndStoreResult statement by expanding child Call statement"
    runtime.expand(fn, stmt.storeFn, internal)
  of ThrowError:
    debug "niche: expand ThrowError"

    if *stmt.error.str:
      runtime.generateBytecode(
        fn,
        createImmutVal("error_msg", stackStr(&stmt.error.str)),
        ownerStmt = some(stmt),
        internal = true,
      )
  of BinaryOp:
    debug "niche: expand BinaryOp"

    if *stmt.binStoreIn:
      debug "niche: BinaryOp evaluation will be stored in: " & &stmt.binStoreIn & " (" &
        $runtime.addrIdx & ')'
      runtime.ir.loadInt(runtime.addrIdx, 0)

      if not internal:
        debug "niche: ...locally"
        runtime.markLocal(fn, &stmt.binStoreIn)
      else:
        debug "niche: ...internally"
        runtime.markInternal(stmt, &stmt.binStoreIn)

    if stmt.binLeft.kind == AtomHolder:
      debug "niche: BinaryOp left term is an atom"
      runtime.generateBytecode(
        fn,
        createImmutVal("left_term", stmt.binLeft.atom),
        ownerStmt = some(stmt),
        internal = true,
      )

    if stmt.binRight.kind == AtomHolder:
      debug "niche: BinaryOp right term is an atom"
      runtime.generateBytecode(
        fn,
        createImmutVal("right_term", stmt.binRight.atom),
        ownerStmt = some(stmt),
        internal = true,
      )
    elif stmt.binRight.kind == IdentHolder:
      debug "niche: BinaryOp right term is an ident"
  of IfStmt:
    debug "niche: expand IfStmt"

    if stmt.conditionExpr.binLeft.kind == AtomHolder:
      debug "niche: if-stmt: left term is an atom"
      runtime.generateBytecode(
        fn,
        createImmutVal("left_term", stmt.conditionExpr.binLeft.atom),
        ownerStmt = some(stmt),
        internal = true,
      )

    if stmt.conditionExpr.binRight.kind == AtomHolder:
      debug "niche: if-stmt: right term is an atom"
      runtime.generateBytecode(
        fn,
        createImmutVal("right_term", stmt.conditionExpr.binRight.atom),
        ownerStmt = some(stmt),
        internal = true,
      )
  of WhileStmt:
    debug "niche: expand WhileStmt"
    if stmt.whConditionExpr.binLeft.kind == AtomHolder:
      debug "niche: while-stmt: left term is an atom"
      runtime.generateBytecode(
        fn,
        createImmutVal("left_term", stmt.whConditionExpr.binLeft.atom),
        ownerStmt = some(stmt),
        internal = true,
      )

    if stmt.whConditionExpr.binRight.kind == AtomHolder:
      debug "niche: while-stmt: right term is an atom"
      runtime.generateBytecode(
        fn,
        createImmutVal("right_term", stmt.whConditionExpr.binRight.atom),
        ownerStmt = some(stmt),
        internal = true,
      )
  of ReturnFn:
    if *stmt.retVal:
      runtime.generateBytecode(
        fn,
        createImmutVal("retval", &stmt.retVal),
        internal = true,
        ownerStmt = some(stmt),
      )
    elif *stmt.retExpr:
      runtime.generateBytecode(
        fn,
        createImmutVal("retval", stackUndefined()),
        internal = true,
        ownerStmt = some(stmt),
      ) # load undefined atom

      var expr = &stmt.retExpr
      expr.binStoreIn = some("retval")
      runtime.generateBytecode(fn, move(expr), internal = true, ownerStmt = some(stmt))
    else:
      runtime.generateBytecode(
        fn,
        createImmutVal("retval", stackUndefined()),
        internal = true,
        ownerStmt = some(stmt),
      ) # load undefined atom
  else:
    discard

proc verifyNotOccupied*(runtime: Runtime, ident: string, fn: Function): bool =
  var prev = fn.prev

  while *prev:
    let parked =
      try:
        discard runtime.index(ident, defaultParams(fn))
        true
      except ValueError as exc:
        false

    if parked:
      return true

    prev = (&prev).prev

  false

proc loadFieldAccessStrings*(runtime: Runtime, access: FieldAccess) =
  var curr = access.next
  assert(
    curr != nil,
    "Field access on single ident (or top of access chain was not provided)",
  )

  while curr != nil:
    runtime.ir.loadStr(runtime.addrIdx, curr.identifier)
    runtime.ir.passArgument(runtime.addrIdx)
    inc runtime.addrIdx

    curr = curr.next

proc resolveFieldAccess*(
    runtime: Runtime, fn: Function, stmt: Statement, address: uint, access: FieldAccess
): uint =
  let internalName = $(hash(stmt) !& hash(ident) !& hash(access.identifier))
  runtime.generateBytecode(
    fn,
    createImmutVal(internalName, stackNull()),
    internal = true,
    ownerStmt = some(stmt),
  )
  let accessResult = runtime.addrIdx - 1 # index where the value will be stored

  # Pass the index at which the atom is located
  inc runtime.addrIdx
  runtime.ir.loadUint(runtime.addrIdx, address)
  runtime.ir.passArgument(runtime.addrIdx)

  # Pass the index at wbich the result is to be stored
  inc runtime.addrIdx
  runtime.ir.loadUint(runtime.addrIdx, accessResult)
  runtime.ir.passArgument(runtime.addrIdx)

  # Pass all the fields
  runtime.loadFieldAccessStrings(access)

  runtime.ir.call("BALI_RESOLVEFIELD")
  runtime.ir.resetArgs()

  accessResult

proc generateBytecodeForScope*(
  runtime: Runtime, scope: Scope, allocateConstants: bool = true
)

func willIRGenerateClause*(runtime: Runtime, clause: string): bool {.inline.} =
  for cls in runtime.ir.modules:
    if cls.name == clause:
      return true

  false

proc genCreateImmutVal(
    runtime: Runtime,
    fn: Function,
    stmt: Statement,
    internal: bool,
    ownerStmt: Option[Statement],
) =
  debug "emitter: generate IR for creating immutable value with identifier: " &
    stmt.imIdentifier

  let idx = runtime.loadIRAtom(deepCopy(stmt.imAtom))

  if not internal:
    if fn.name == "outer":
      debug "emitter: marking index as global because it's in outer-most scope: " & $idx

    runtime.markLocal(fn, stmt.imIdentifier, index = some(idx))
  else:
    assert *ownerStmt
    runtime.markInternal(&ownerStmt, stmt.imIdentifier)

proc genCreateMutVal(
    runtime: Runtime,
    fn: Function,
    stmt: Statement,
    internal: bool,
    ownerStmt: Option[Statement],
) =
  let idx = runtime.loadIRAtom(stmt.mutAtom)

  if not internal:
    if fn.name == "outer":
      debug "emitter: marking index as global because it's in outer-most scope: " & $idx

    runtime.markLocal(fn, stmt.mutIdentifier, index = some(idx))
  else:
    assert *ownerStmt
    runtime.markInternal(&ownerStmt, stmt.mutIdentifier)

proc genCall(
    runtime: Runtime,
    fn: Function,
    stmt: Statement,
    internal: bool,
    ownerStmt: Option[Statement],
) =
  runtime.expand(fn, stmt)
  runtime.ir.resetArgs()
  var nam =
    if stmt.mangle:
      stmt.fn.normalizeIRName()
    else:
      stmt.fn.function

  proc fillArguments() =
    for i, arg in stmt.arguments:
      case arg.kind
      of cakIdent:
        debug "interpreter: passing ident parameter to function with ident: " & arg.ident

        runtime.ir.passArgument(runtime.index(arg.ident, defaultParams(fn)))
      of cakAtom: # already loaded via the statement expander
        let ident = $i
        debug "interpreter: passing atom parameter to function with ident: " & ident
        runtime.ir.passArgument(runtime.index(ident, internalIndex(stmt)))
      of cakFieldAccess:
        let index = runtime.resolveFieldAccess(
          fn, stmt, runtime.index(arg.access.identifier, defaultParams(fn)), arg.access
        )
        runtime.ir.passArgument(index)
      of cakImmediateExpr:
        let index = runtime.index($i, internalIndex(arg.expr))
        runtime.ir.passArgument(index)

  if *stmt.fn.field:
    let identName = (&stmt.fn.field).identifier

    # TODO: recursive field solving

    # firstly, try to get the bytecode callable / native callable
    let fn = runtime.resolveFieldAccess(
      fn, stmt, runtime.index(identName, defaultParams(fn)), &stmt.fn.field
    )

    fillArguments()

    # then, invoke it.
    runtime.ir.invoke(fn)
  else:
    debug "interpreter: generate IR for calling traditional function: " & nam &
      (if stmt.mangle: " (mangled)" else: newString 0)

    # assert nam != "a"

    fillArguments()

    let indexed = runtime.index(nam, defaultParams(fn))

    if indexed == runtime.index("undefined", defaultParams(fn)):
      runtime.ir.invoke(nam)
    else:
      runtime.ir.invoke(indexed)

  runtime.ir.resetArgs()
    # Reset the call arguments register to prevent this call's arguments from leaking into future calls

  if !ownerStmt:
    runtime.ir.zeroRetval()

proc genReturnFn(runtime: Runtime, fn: Function, stmt: Statement) =
  runtime.expand(fn, stmt)

  if *stmt.retVal:
    runtime.ir.returnFn(runtime.index("retval", internalIndex(stmt)).int)
  elif *stmt.retExpr:
    runtime.ir.returnFn(runtime.index("retval", internalIndex(&stmt.retExpr)).int)
  elif *stmt.retIdent:
    runtime.ir.returnFn(runtime.index(&stmt.retIdent, defaultParams(fn)).int)
  else:
    unreachable

proc genCallAndStoreResult(runtime: Runtime, fn: Function, stmt: Statement) =
  runtime.generateBytecode(fn, stmt.storeFn, ownerStmt = some(stmt))
  var index = runtime.index(stmt.storeIdent, defaultParams(fn))

  if index == runtime.index("undefined", defaultParams(fn)):
    runtime.markLocal(fn, stmt.storeIdent)
    index = runtime.addrIdx - 1

  debug "emitter: call-and-store result will be stored in ident \"" & stmt.storeIdent &
    "\" or index " & $index
  runtime.ir.loadUndefined(index) # load `undefined` on that index
  runtime.ir.readRegister(index, Register.ReturnValue)
  runtime.ir.zeroRetval()

proc genConstructObject(
    runtime: Runtime, fn: Function, stmt: Statement, internal: bool
) =
  runtime.expand(fn, stmt, internal)
  for i, arg in stmt.args:
    case arg.kind
    of cakIdent:
      let ident = arg.ident
      info "interpreter: passing ident parameter to function with ident: " & ident
      runtime.ir.passArgument(runtime.index(ident, defaultParams(fn)))
    of cakAtom: # already loaded via the statement expander
      let ident = $hash(stmt) & '_' & $i
      info "interpreter: passing atom parameter to function with ident: " & ident
      runtime.ir.passArgument(runtime.index(ident, internalIndex(stmt)))
    of cakFieldAccess:
      let index = runtime.resolveFieldAccess(
        fn, stmt, runtime.index(arg.access.identifier, defaultParams(fn)), arg.access
      )
      runtime.ir.passArgument(index)
    of cakImmediateExpr:
      discard

  runtime.ir.call("BALI_CONSTRUCTOR_" & stmt.objName.toUpperAscii())
  runtime.ir.resetArgs()

proc genReassignVal(runtime: Runtime, fn: Function, stmt: Statement) =
  if not stmt.reIdentifier.contains('.'):
    let index = runtime.index(stmt.reIdentifier, defaultParams(fn))

    info "emitter: reassign value at index " & $index & " with ident \"" &
      stmt.reIdentifier & "\" to " & stmt.reAtom.crush()

    # TODO: make this use loadIRAtom
    case stmt.reAtom.kind
    of Integer:
      runtime.ir.loadInt(index, stmt.reAtom)
    of String:
      runtime.ir.loadStr(index, stmt.reAtom)
    of Float:
      runtime.ir.loadFloat(index, stmt.reAtom)
    else:
      unreachable
  else:
    # field overwrite!
    let accesses = createFieldAccess(stmt.reIdentifier.split('.'))
    let atomIndex = runtime.loadIRAtom(stmt.reAtom)

    inc runtime.addrIdx

    # prepare for internal call
    runtime.ir.passArgument(
      runtime.loadIRAtom(
        stackInteger(runtime.index(accesses.identifier, defaultParams(fn)))
      )
    ) # 1: Atom index that needs its field to be overwritten

    inc runtime.addrIdx

    runtime.ir.passArgument(atomIndex) # 2: The atom to be put in the field

    runtime.loadFieldAccessStrings(accesses) # 3: The field access strings

    runtime.ir.call("BALI_WRITE_FIELD")
    runtime.ir.resetArgs()

proc genThrowError(runtime: Runtime, fn: Function, stmt: Statement, internal: bool) =
  info "emitter: add error-throw logic"

  if *stmt.error.str:
    let msg = &stmt.error.str

    info "emitter: error string that will be raised: `" & msg & '`'
    runtime.expand(fn, stmt, internal)

    runtime.ir.passArgument(runtime.index("error_msg", internalIndex(stmt)))
    runtime.ir.call("BALI_THROWERROR")
    runtime.ir.resetArgs()

    runtime.vm.sourceMap[fn.name][runtime.ir.cachedIndex - 1] =
      (message: stmt.source, line: stmt.line)
  elif *stmt.error.ident:
    runtime.ir.passArgument(runtime.index(&stmt.error.ident, defaultParams(fn)))
    runtime.ir.call("BALI_THROWERROR")
    runtime.ir.resetArgs()

    runtime.vm.sourceMap[fn.name][runtime.ir.cachedIndex - 1] =
      (message: stmt.source, line: stmt.line)
  else:
    unreachable

proc genBinaryOp(
    runtime: Runtime,
    fn: Function,
    stmt: Statement,
    internal: bool,
    parentStmt: Option[Statement] = none(Statement),
    exprStoreIn: Option[string] = none(string),
) =
  info "emitter: emitting IR for binary operation"
  runtime.expand(fn, stmt, internal)

  let
    leftTerm = stmt.binLeft
    rightTerm = stmt.binRight

  # TODO: recursive IR generation

  let
    leftIdx =
      if leftTerm.kind == AtomHolder:
        runtime.index("left_term", internalIndex(stmt))
      elif leftTerm.kind == IdentHolder:
        runtime.index(leftTerm.ident, defaultParams(fn))
      else:
        0

    rightIdx =
      if rightTerm.kind == AtomHolder:
        runtime.index("right_term", internalIndex(stmt))
      elif rightTerm.kind == IdentHolder:
        runtime.index(rightTerm.ident, defaultParams(fn))
      else:
        0

  case stmt.op
  of BinaryOperation.Add:
    runtime.ir.add(leftIdx, rightIdx)
  of BinaryOperation.Sub:
    runtime.ir.sub(leftIdx, rightIdx)
  of BinaryOperation.Mult:
    runtime.ir.mult(leftIdx, rightIdx)
  of BinaryOperation.Div:
    runtime.ir.divide(leftIdx, rightIdx)
  of BinaryOperation.Equal, BinaryOperation.TrueEqual:
    # runtime.ir.equate(leftIdx, rightIdx)
    runtime.ir.passArgument(leftIdx)
    runtime.ir.passArgument(rightIdx)
    runtime.ir.call(
      if stmt.op == BinaryOperation.Equal:
        "BALI_EQUATE_ATOMS"
      else:
        "BALI_EQUATE_ATOMS_STRICT"
    )
    # FIXME: really weird bug in mirage's IR generator. wtf?
    let
      equalJmp = runtime.ir.addOp(IROperation(opcode: Jump)) - 1 # left == right branch
      unequalJmp = runtime.ir.addOp(IROperation(opcode: Jump)) - 1 # left != right branch

    # left == right branch
    let equalBranch =
      if leftTerm.kind == AtomHolder:
        runtime.ir.loadBool(leftIdx, true)
      else:
        runtime.ir.loadBool(runtime.index(&stmt.binStoreIn, defaultParams(fn)), true)
    runtime.ir.overrideArgs(equalJmp, @[stackInteger(equalBranch)])
    runtime.ir.jump(equalBranch + 3)

    # left != right branch
    let unequalBranch =
      if leftTerm.kind == AtomHolder:
        runtime.ir.loadBool(leftIdx, false)
      else:
        runtime.ir.loadBool(runtime.index(&stmt.binStoreIn, defaultParams(fn)), false)
    runtime.ir.overrideArgs(unequalJmp, @[stackInteger(unequalBranch)])
  of BinaryOperation.NotEqual:
    runtime.ir.passArgument(leftIdx)
    runtime.ir.passArgument(rightIdx)
    runtime.ir.call("BALI_EQUATE_ATOMS")
    # FIXME: really weird bug in mirage's IR generator. wtf?
    let equalJmp = runtime.ir.addOp(IROperation(opcode: Jump)) - 1 # left == right branch
    let unequalJmp = runtime.ir.addOp(IROperation(opcode: Jump)) - 1
      # left != right branch

    # left != right branch: true
    let unequalBranch =
      if leftTerm.kind == AtomHolder:
        runtime.ir.loadBool(leftIdx, true)
      else:
        runtime.ir.loadBool(runtime.index(&stmt.binStoreIn, defaultParams(fn)), true)
    runtime.ir.overrideArgs(unequalJmp, @[stackInteger(unequalBranch)])
    runtime.ir.jump(unequalBranch + 3)

    # left == right branch: false
    let equalBranch =
      if leftTerm.kind == AtomHolder:
        runtime.ir.loadBool(leftIdx, false)
      else:
        runtime.ir.loadBool(runtime.index(&stmt.binStoreIn, defaultParams(fn)), false)
    runtime.ir.overrideArgs(equalJmp, @[stackInteger(equalBranch)])
  of BinaryOperation.GreaterThan:
    runtime.ir.greaterThan(leftIdx, rightIdx)
  of BinaryOperation.LesserThan:
    runtime.ir.greaterThanEqual(leftIdx, rightIdx)
  of BinaryOperation.LesserOrEqual:
    runtime.ir.lesserThanEqual(leftIdx, rightIdx)
  else:
    warn "emitter: unimplemented binary operation: " & $stmt.op

  if *stmt.binStoreIn:
    runtime.ir.copyAtom(
      leftIdx,
      runtime.index(
        &stmt.binStoreIn,
        if not internal:
          defaultParams(fn)
        else:
          internalIndex(stmt),
      ),
    )
  elif *exprStoreIn:
    assert *parentStmt
    runtime.ir.copyAtom(
      leftIdx, runtime.index(&exprStoreIn, internalIndex(&parentStmt))
    )

  runtime.vm.sourceMap[fn.name][runtime.ir.cachedIndex - 1] =
    (message: stmt.source, line: stmt.line)

proc genIfStmt(runtime: Runtime, fn: Function, stmt: Statement) =
  info "emitter: emitting bytecode for if statement"

  # if runtime.opts.codegen.deadCodeElimination and conditionalIsDead(stmt):
  #  debug "emitter: dce tells us that the if statement is unreachable, preventing codegen for it"
  #  return

  runtime.expand(fn, stmt)

  let
    lhsIdx =
      case stmt.conditionExpr.binLeft.kind
      of IdentHolder:
        debug "emitter: if-stmt: LHS is ident"
        runtime.index(stmt.conditionExpr.binLeft.ident, defaultParams(fn))
      of AtomHolder:
        debug "emitter: if-stmt: LHS is atom"
        runtime.index("left_term", internalIndex(stmt))
      else:
        unreachable
        0

    rhsIdx =
      case stmt.conditionExpr.binRight.kind
      of IdentHolder:
        debug "emitter: if-stmt: RHS is ident"
        runtime.index(stmt.conditionExpr.binRight.ident, defaultParams(fn))
      of AtomHolder:
        debug "emitter: if-stmt: RHS is atom"
        runtime.index("right_term", internalIndex(stmt))
      else:
        unreachable
        0

  case stmt.conditionExpr.op
  of BinaryOperation.Equal, BinaryOperation.NotEqual, BinaryOperation.TrueEqual:
    runtime.ir.passArgument(lhsIdx)
    runtime.ir.passArgument(rhsIdx)
    runtime.ir.call(
      if stmt.conditionExpr.op != BinaryOperation.TrueEqual:
        "BALI_EQUATE_ATOMS"
      else:
        "BALI_EQUATE_ATOMS_STRICT"
    )
  of BinaryOperation.GreaterThan:
    runtime.ir.greaterThan(lhsIdx, rhsIdx)
  of BinaryOperation.LesserThan:
    runtime.ir.lesserThan(lhsIdx, rhsIdx)
  of BinaryOperation.GreaterOrEqual:
    runtime.ir.greaterThanEqual(lhsIdx, rhsIdx)
  of BinaryOperation.LesserOrEqual:
    runtime.ir.lesserThanEqual(lhsIdx, rhsIdx)
  else:
    unreachable

  let
    trueJump = runtime.ir.addOp(IROperation(opcode: Jump)) - 1
    falseJump = runtime.ir.addOp(IROperation(opcode: Jump)) - 1

  proc getCurrOpNum(): int =
    for module in runtime.ir.modules:
      if module.name == runtime.ir.currModule:
        return module.operations.len + 1

    unreachable
    0

  runtime.generateBytecodeForScope(stmt.branchTrue, allocateConstants = false)
    # generate branch one
  let skipBranchTwoJmp = runtime.ir.addOp(IROperation(opcode: Jump)) - 1
    # jump beyond branch two, don't accidentally execute it
  let endOfBranchOne = getCurrOpNum().uint

  runtime.generateBytecodeForScope(stmt.branchFalse, allocateConstants = false)
    # generate branch two
  let endOfBranchTwo = getCurrOpNum().uint
  runtime.ir.overrideArgs(skipBranchTwoJmp, @[stackInteger(endOfBranchTwo)])

  case stmt.conditionExpr.op
  of BinaryOperation.Equal, BinaryOperation.GreaterThan, BinaryOperation.TrueEqual,
      BinaryOperation.GreaterOrEqual, BinaryOperation.LesserThan,
      BinaryOperation.LesserOrEqual:
    runtime.ir.overrideArgs(falseJump, @[stackInteger(endOfBranchOne)])
    runtime.ir.overrideArgs(trueJump, @[stackInteger(falseJump + 2)])
  of BinaryOperation.NotEqual:
    runtime.ir.overrideArgs(trueJump, @[stackInteger(getCurrOpNum().uint)])
    runtime.ir.overrideArgs(falseJump, @[stackInteger(falseJump + 2)])
  else:
    unreachable

  runtime.vm.sourceMap[fn.name][runtime.ir.cachedIndex - 1] =
    (message: stmt.source, line: stmt.line)

proc genCopyValMut(runtime: Runtime, fn: Function, stmt: Statement) =
  debug "emitter: generate IR for copying value to a mutable address with source: " &
    stmt.cpMutSourceIdent & " and destination: " & stmt.cpMutDestIdent

  let preExistingDestIndex = runtime.index(stmt.cpMutDestIdent, defaultParams(fn))

  if preExistingDestIndex == runtime.index("undefined", defaultParams(fn)):
    runtime.generateBytecode(
      fn, createMutVal(stmt.cpMutDestIdent, stackNull()), internal = false
    )
    let dest = runtime.addrIdx - 1

    if stmt.cpMutDestIdent.contains('.'):
      # Field access.
      let fields = createFieldAccess(stmt.cpMutDestIdent.split('.'))

      # TODO: recursively find the field to modify
      runtime.ir.writeField(
        runtime.index(fields.identifier, defaultParams(fn)),
        fields.next.identifier,
        runtime.index(stmt.cpMutSourceIdent, defaultParams(fn)),
      )
    else:
      runtime.ir.copyAtom(runtime.index(stmt.cpMutSourceIdent, defaultParams(fn)), dest)

    runtime.vm.sourceMap[fn.name][runtime.ir.cachedIndex - 1] =
      (message: stmt.source, line: stmt.line)
  else:
    runtime.ir.copyAtom(
      runtime.index(stmt.cpMutSourceIdent, defaultParams(fn)), preExistingDestIndex
    )

proc genCopyValImmut(runtime: Runtime, fn: Function, stmt: Statement) =
  debug "emitter: generate IR for copying value to an immutable address with source: " &
    stmt.cpImmutSourceIdent & " and destination: " & stmt.cpImmutDestIdent
  runtime.generateBytecode(
    fn, createMutVal(stmt.cpImmutDestIdent, stackNull()), internal = false
  )
  let dest = runtime.addrIdx - 1

  runtime.ir.copyAtom(runtime.index(stmt.cpImmutSourceIdent, defaultParams(fn)), dest)

  runtime.vm.sourceMap[fn.name][runtime.ir.cachedIndex - 1] =
    (message: stmt.source, line: stmt.line)

proc genWhileStmt(runtime: Runtime, fn: Function, stmt: Statement) =
  debug "emitter: generate IR for while loop"
  if runtime.opts.codegen.elideLoops and
      stmt.whStmtOnlyMutatesItsState(stmt.whBranch.getValueCaptures()):
    debug "emitter: while loop only mutates its own state - eliding it away"
    if runtime.optimizeAwayStateMutatorLoop(fn, stmt):
      return # we can fully skip creating all of the expensive comparison checks! :D
    else:
      debug "emitter: failed to elide state mutator loop :("

  runtime.expand(fn, stmt)

  proc getCurrOpNum(): int =
    for module in runtime.ir.modules:
      if module.name == runtime.ir.currModule:
        return module.operations.len + 1

    unreachable
    0

  let allocElimResult: Option[AllocationEliminatorResult] =
    if runtime.opts.codegen.loopAllocationEliminator:
      runtime.eliminateRedundantLoopAllocations(stmt.whBranch).some
    else:
      none(AllocationEliminatorResult)

  let
    lhsIdx =
      case stmt.whConditionExpr.binLeft.kind
      of IdentHolder:
        debug "emitter: while-stmt: LHS is ident"
        runtime.index(stmt.whConditionExpr.binLeft.ident, defaultParams(fn))
      of AtomHolder:
        debug "emitter: while-stmt: LHS is atom"
        runtime.index("left_term", internalIndex(stmt))
      else:
        unreachable
        0

    rhsIdx =
      case stmt.whConditionExpr.binRight.kind
      of IdentHolder:
        debug "emitter: while-stmt: RHS is ident"
        runtime.index(stmt.whConditionExpr.binRight.ident, defaultParams(fn))
      of AtomHolder:
        debug "emitter: while-stmt: RHS is atom"
        runtime.index("right_term", internalIndex(stmt))
      else:
        unreachable
        0

  if *allocElimResult:
    let placeBefore = (&allocElimResult).placeBefore
    runtime.generateBytecodeForScope(placeBefore, allocateConstants = false)

  let jmpIntoComparison = getCurrOpNum()
  case stmt.whConditionExpr.op
  of Equal, NotEqual, TrueEqual:
    runtime.ir.passArgument(lhsIdx)
    runtime.ir.passArgument(rhsIdx)
    runtime.ir.call(
      if stmt.whConditionExpr.op != BinaryOperation.TrueEqual:
        "BALI_EQUATE_ATOMS"
      else:
        "BALI_EQUATE_ATOMS_STRICT"
    )
  of GreaterThan:
    runtime.ir.greaterThan(lhsIdx, rhsIdx)
  of LesserThan:
    runtime.ir.lesserThan(lhsIdx, rhsIdx)
  else:
    unreachable

  let
    trueJump = runtime.ir.addOp(IROperation(opcode: Jump)) - 1
      # the jump into the body of the loop
    escapeJump = runtime.ir.addOp(IROperation(opcode: Jump)) - 1
      # the jump to "escape" out of the loop
    dummyJump = runtime.ir.addOp(IROperation(opcode: Jump)) - 1
      # this will just point to its own address in the event that it isn't modified
      # if it is modified, it'll likely point to wherever `escapeJump` points to

  let jmpIntoBody = getCurrOpNum()

  # generate the body of the loop
  if !allocElimResult:
    runtime.generateBytecodeForScope(stmt.whBranch, allocateConstants = false)
  else:
    runtime.generateBytecodeForScope(
      (&allocElimResult).modifiedBody, allocateConstants = false
    )

  runtime.ir.jump(jmpIntoComparison.uint) # jump back to the comparison logic

  let jmpPastBody = getCurrOpNum()

  if runtime.irHints.breaksGeneratedAt.len > 0:
    for brk in runtime.irHints.breaksGeneratedAt:
      runtime.ir.overrideArgs(brk, @[stackInteger(jmpPastBody.uint)])
  else:
    runtime.ir.overrideArgs(dummyJump, @[stackInteger(jmpPastBody.uint)])

  runtime.irHints.breaksGeneratedAt.reset()

  case stmt.whConditionExpr.op
  of BinaryOperation.Equal, BinaryOperation.TrueEqual, BinaryOperation.GreaterThan,
      BinaryOperation.LesserThan:
    runtime.ir.overrideArgs(trueJump, @[stackInteger(jmpIntoBody.uint)])
    runtime.ir.overrideArgs(escapeJump, @[stackInteger(jmpPastBody.uint)])
  of BinaryOperation.NotEqual:
    runtime.ir.overrideArgs(trueJump, @[stackInteger(jmpPastBody.uint)])
    runtime.ir.overrideArgs(escapeJump, @[stackInteger(jmpIntoBody.uint)])
  else:
    unreachable

  runtime.vm.sourceMap[fn.name][runtime.ir.cachedIndex - 1] =
    (message: stmt.source, line: stmt.line)

proc genIncrement(runtime: Runtime, fn: Function, stmt: Statement) {.inline.} =
  debug "emitter: generate IR for increment"
  runtime.ir.incrementInt(runtime.index(stmt.incIdent, defaultParams(fn)))
  runtime.vm.sourceMap[fn.name][runtime.ir.cachedIndex - 1] =
    (message: stmt.source, line: stmt.line)

proc genDecrement(runtime: Runtime, fn: Function, stmt: Statement) {.inline.} =
  debug "emitter: generate IR for decrement"
  runtime.ir.decrementInt(runtime.index(stmt.decIdent, defaultParams(fn)))
  runtime.vm.sourceMap[fn.name][runtime.ir.cachedIndex - 1] =
    (message: stmt.source, line: stmt.line)

proc genBreak(runtime: Runtime, fn: Function, stmt: Statement) {.inline.} =
  debug "emitter: generate IR for break"
  runtime.irHints.breaksGeneratedAt &= runtime.ir.addOp(IROperation(opcode: Jump)) - 1
  runtime.vm.sourceMap[fn.name][runtime.ir.cachedIndex - 1] =
    (message: stmt.source, line: stmt.line)

proc genWaste(runtime: Runtime, fn: Function, stmt: Statement) =
  debug "emitter: generate IR for wasting value"
  assert(
    not (*stmt.wstAtom and *stmt.wstIdent), "Cannot waste atom and identifier at once!"
  )

  let idx =
    if *stmt.wstAtom:
      runtime.loadIRAtom(&stmt.wstAtom)
    elif *stmt.wstIdent:
      runtime.index(&stmt.wstIdent, defaultParams(fn))
    else:
      unreachable
      0'u

  if runtime.opts.repl:
    runtime.ir.passArgument(idx)
    var args: PositionedArguments

    if *stmt.wstAtom:
      args.pushAtom(&stmt.wstAtom)
    elif *stmt.wstIdent:
      args.pushIdent(&stmt.wstIdent)
    else:
      unreachable

    runtime.generateBytecode(
      fn,
      call(
        callFunction(
          "console",
          FieldAccess(identifier: "console", next: FieldAccess(identifier: "log")),
        ), # FIXME: why do we have to specify console twice? :/
        ensureMove(args),
        expectsReturnVal = false,
      ),
    )

  runtime.vm.sourceMap[fn.name][runtime.ir.cachedIndex - 1] =
    (message: stmt.source, line: stmt.line)

proc genAccessArrayIndex(
    runtime: Runtime,
    fn: Function,
    stmt: Statement,
    storeIn: Option[string] = none(string),
) =
  debug "emitter: generate IR for array indexing"
  let atomIdx = runtime.index(stmt.arrAccIdent, defaultParams(fn))
  let fieldIndex =
    if *stmt.arrAccIndex:
      runtime.loadIRAtom(&stmt.arrAccIndex)
    elif *stmt.arrAccIdentIndex:
      runtime.index(&stmt.arrAccIdentIndex, defaultParams(fn))
    else:
      unreachable
      0

  runtime.ir.passArgument(atomIdx)
  runtime.ir.passArgument(fieldIndex)
  runtime.ir.call("BALI_INDEX")

  if !storeIn:
    runtime.ir.resetArgs()
  else:
    runtime.ir.readRegister(
      runtime.index(&storeIn, internalIndex(stmt)), Register.ReturnValue
    )
  runtime.vm.sourceMap[fn.name][runtime.ir.cachedIndex - 1] =
    (message: stmt.source, line: stmt.line)

proc genTernaryOp(runtime: Runtime, fn: Function, stmt: Statement) =
  debug "emitter: generate IR for ternary op"
  if !stmt.ternaryStoreIn:
    return

  let
    storeIn = &stmt.ternaryStoreIn
    addrOfCond =
      if stmt.ternaryCond.kind == AtomHolder:
        runtime.loadIRAtom(stmt.ternaryCond.atom)
      elif stmt.ternaryCond.kind == IdentHolder:
        runtime.index(stmt.ternaryCond.ident, defaultParams(fn))
      else:
        unreachable
        0'u

  inc runtime.addrIdx

  let addrOfTrueExpr =
    if stmt.trueTernary.kind == AtomHolder:
      runtime.loadIRAtom(stmt.trueTernary.atom)
    elif stmt.trueTernary.kind == IdentHolder:
      runtime.index(stmt.falseTernary.ident, defaultParams(fn))
    else:
      unreachable
      0'u

  inc runtime.addrIdx

  let addrOfFalseExpr =
    if stmt.falseTernary.kind == AtomHolder:
      runtime.loadIRAtom(stmt.falseTernary.atom)
    elif stmt.falseTernary.kind == IdentHolder:
      runtime.index(stmt.falseTernary.ident, defaultParams(fn))
    else:
      unreachable
      0'u

  inc runtime.addrIdx

  proc getCurrOpNum(): uint =
    for module in runtime.ir.modules:
      if module.name == runtime.ir.currModule:
        return uint(module.operations.len + 1)

    unreachable
    0'u

  runtime.markLocal(fn, storeIn)
  let finalAddr = runtime.addrIdx - 1

  runtime.ir.equate(addrOfCond, runtime.index("true", defaultParams(fn)))
  # If addrOfCond == true:
  runtime.ir.jump(getCurrOpNum() + 2'u)
  # If addrOfCond == false (or != true, which means false anyways):
  runtime.ir.jump(getCurrOpNum() + 3'u)

  runtime.ir.copyAtom(addrOfTrueExpr, finalAddr)
  runtime.ir.jump(getCurrOpNum() + 2'u)

  runtime.ir.copyAtom(addrOfFalseExpr, finalAddr)

  runtime.vm.sourceMap[fn.name][runtime.ir.cachedIndex - 1] =
    (message: stmt.source, line: stmt.line)

proc genForLoop(runtime: Runtime, fn: Function, stmt: Statement) =
  # if runtime.opts.codegen.deadCodeElimination and forLoopIsDead(stmt):
  # If the for-loop has no side effects, we can safely elide it.
  #  debug "emitter: dce tells us that this for-loop has no side effects, preventing codegen"
  #  return

  runtime.vm.sourceMap[fn.name][runtime.ir.cachedIndex - 1] =
    (message: stmt.source, line: stmt.line)

  # Generate bytecode for initializer, if it exists.
  if *stmt.forLoopInitializer:
    runtime.generateBytecode(fn, &stmt.forLoopInitializer)

  proc getCurrOpNum(): uint =
    for module in runtime.ir.modules:
      if module.name == runtime.ir.currModule:
        return uint(module.operations.len + 1)

    unreachable
    0'u

  let conditionalJump = getCurrOpNum()

  # Generate IR for conditional, if it exists.
  # TODO: Else, just equate `0` to `0`

  var inverted = false
  if *stmt.forLoopCond:
    let cond = &stmt.forLoopCond
    inverted = cond.op in {BinaryOperation.LesserThan}
    runtime.generateBytecode(fn, cond)
  else:
    unreachable

  # Now, generate the jumps for either going into the loop body or outside it.
  # If conditional is true, jump into the body
  # else, jump outside
  let jmpIntoBody = stackInteger(getCurrOpNum() + 2'u)

  let jump1 = runtime.ir.placeholder(Jump) - 1
  let jump2 = runtime.ir.placeholder(Jump) - 1

  runtime.generateBytecodeForScope(stmt.forLoopBody, allocateConstants = false)

  # Generate code for the incrementor/stepper
  if *stmt.forLoopIter:
    runtime.generateBytecode(fn, &stmt.forLoopIter)

  let jmpOutsideBody = stackInteger(getCurrOpNum() + 1'u)

  if not inverted:
    runtime.ir.overrideArgs(jump1, @[jmpIntoBody])
    runtime.ir.overrideArgs(jump2, @[jmpOutsideBody])
  else:
    runtime.ir.overrideArgs(jump1, @[jmpOutsideBody])
    runtime.ir.overrideArgs(jump2, @[jmpIntoBody])

  runtime.ir.jump(conditionalJump)

proc genTryClause(runtime: Runtime, fn: Function, stmt: Statement) =
  debug "emitter: generate bytecode for try clause"

  runtime.vm.sourceMap[fn.name][runtime.ir.cachedIndex - 1] =
    (message: stmt.source, line: stmt.line)

  # Install a jump-on-exception handler
  let excHandler = runtime.ir.placeholder(JumpOnError) - 1

  # Generate bytecode for try-block
  runtime.generateBytecodeForScope(stmt.tryStmtBody, allocateConstants = false)

  proc getCurrOpNum(): int =
    for module in runtime.ir.modules:
      if module.name == runtime.ir.currModule:
        return module.operations.len + 1

    unreachable
    0

  # Generate bytecode for catch clause, if it exists.
  runtime.ir.overrideArgs(excHandler, @[getCurrOpNum().stackInteger])
  if *stmt.tryCatchBody:
    if *stmt.tryErrorCaptureIdent:
      runtime.markLocal(fn = fn, ident = &stmt.tryErrorCaptureIdent)
      let errorCaptureIndex = runtime.addrIdx - 1

      runtime.ir.readRegister(errorCaptureIndex, Register.Error)

    runtime.generateBytecodeForScope(&stmt.tryCatchBody, allocateConstants = false)

proc genCompoundAsgn(runtime: Runtime, fn: Function, stmt: Statement) =
  debug "emitter: generate bytecode for compound assignment"
  let target = runtime.index(stmt.compAsgnTarget, defaultParams(fn))
  let compounder =
    if *stmt.compAsgnCompounder:
      runtime.loadIRAtom(&stmt.compAsgnCompounder)
    elif *stmt.compAsgnCompounderIdent:
      runtime.index(&stmt.compAsgnCompounderIdent, defaultParams(fn))
    else:
      unreachable
      0'u

  case stmt.compAsgnOp
  of BinaryOperation.Mult:
    runtime.ir.mult(target, compounder)
  of BinaryOperation.Div:
    runtime.ir.divide(target, compounder)
  of BinaryOperation.Add:
    runtime.ir.add(target, compounder)
  of BinaryOperation.Sub:
    runtime.ir.sub(target, compounder)
  else:
    unreachable

  runtime.vm.sourceMap[fn.name][runtime.ir.cachedIndex - 1] =
    (message: stmt.source, line: stmt.line)

proc genDefineFunction(runtime: Runtime, fn: Function, stmt: Statement) =
  debug "emitter: generate bytecode for define-function"

  runtime.vm.sourceMap[fn.name][runtime.ir.cachedIndex - 1] =
    (message: stmt.source, line: stmt.line)

  let moduleName = runtime.ir.currModule
  runtime.generateBytecodeForScope(Scope(stmt.defunFn))

  runtime.ir.cachedModule = nil
  runtime.ir.currModule = moduleName

  runtime.markLocal(fn, stmt.defunFn.name)
  runtime.ir.loadBytecodeCallable(
    runtime.addrIdx - 1, normalizeIRName(stmt.defunFn.name)
  )

proc generateBytecode(
    runtime: Runtime,
    fn: Function,
    stmt: Statement,
    internal: bool = false,
    ownerStmt: Option[Statement] = none(Statement),
    exprStoreIn: Option[string] = none(string),
    parentStmt: Option[Statement] = none(Statement),
    index: Option[uint] = none(uint),
) =
  ## Given a statement `stmt` and its encompassing functional scope `fn` (which can be a plain scope as well),
  ## generate the bytecode for that statement.
  ## **NOTE**: This function can be _HIGHLY_ recursive in nature and has side effects*
  case stmt.kind
  of CreateImmutVal:
    runtime.genCreateImmutVal(
      fn = fn, stmt = stmt, internal = internal, ownerStmt = ownerStmt
    )
  of CreateMutVal:
    runtime.genCreateMutVal(
      fn = fn, stmt = stmt, internal = internal, ownerStmt = ownerStmt
    )
  of Call:
    runtime.genCall(fn = fn, stmt = stmt, internal = internal, ownerStmt = ownerStmt)
  of ReturnFn:
    runtime.genReturnFn(fn = fn, stmt = stmt)
  of CallAndStoreResult:
    runtime.genCallAndStoreResult(fn = fn, stmt = stmt)
  of ConstructObject:
    runtime.genConstructObject(fn = fn, stmt = stmt, internal = internal)
  of ReassignVal:
    runtime.genReassignVal(fn = fn, stmt = stmt)
  of ThrowError:
    runtime.genThrowError(fn = fn, stmt = stmt, internal = internal)
  of BinaryOp:
    runtime.genBinaryOp(
      fn = fn,
      stmt = stmt,
      internal = internal,
      parentStmt = parentStmt,
      exprStoreIn = exprStoreIn,
    )
  of IfStmt:
    runtime.genIfStmt(fn = fn, stmt = stmt)
  of CopyValMut:
    runtime.genCopyValMut(fn = fn, stmt = stmt)
  of CopyValImmut:
    runtime.genCopyValImmut(fn = fn, stmt = stmt)
  of WhileStmt:
    runtime.genWhileStmt(fn = fn, stmt = stmt)
  of Increment:
    runtime.genIncrement(fn = fn, stmt = stmt)
  of Decrement:
    runtime.genDecrement(fn = fn, stmt = stmt)
  of Break:
    runtime.genBreak(fn = fn, stmt = stmt)
  of Waste:
    runtime.genWaste(fn = fn, stmt = stmt)
  of AccessArrayIndex:
    runtime.genAccessArrayIndex(fn = fn, stmt = stmt, storeIn = exprStoreIn)
  of TernaryOp:
    runtime.genTernaryOp(fn = fn, stmt = stmt)
  of ForLoop:
    runtime.genForLoop(fn = fn, stmt = stmt)
  of TryCatch:
    runtime.genTryClause(fn = fn, stmt = stmt)
  of CompoundAssignment:
    runtime.genCompoundAsgn(fn = fn, stmt = stmt)
  of DefineFunction:
    runtime.genDefineFunction(fn = fn, stmt = stmt)
  else:
    warn "emitter: unimplemented bytecode generation directive: " & $stmt.kind

  runtime.vm.sourceMap[fn.name][runtime.ir.cachedIndex] =
    (message: stmt.source, line: stmt.line)

proc loadArgumentsOntoStack(runtime: Runtime, fn: Function) =
  info "niche: loading up function signature arguments onto stack via IR: " & fn.name

  for i, arg in fn.arguments:
    runtime.markLocal(fn, arg)
    runtime.ir.readRegister(
      runtime.index(arg, defaultParams(fn)), i.uint, Register.CallArgument
    )

  runtime.ir.resetArgs() # reset the call param register

proc generateBytecodeForScope(
    runtime: Runtime, scope: Scope, allocateConstants: bool = true
) =
  let
    fn =
      try:
        Function(scope)
      except ObjectConversionDefect:
        Function(
          name: "outer",
          arguments: newSeq[string](0),
          prev: scope.prev,
          children: scope.children,
          stmts: scope.stmts,
        ) # FIXME: discriminate between scopes
    name = fn.name

  debug "generateBytecodeForScope(): function name: " & name
  if not runtime.clauses.contains(name):
    runtime.clauses.add(name)
    runtime.ir.newModule(name.normalizeIRName())

  for child in scope.children:
    let clause =
      try:
        Function(child).name
      except ObjectConversionDefect:
        newString(0)

    if clause.len > 0:
      runtime.markGlobal(clause)
      let fnIndex = runtime.addrIdx - 1
      runtime.ir.loadBytecodeCallable(fnIndex, clause)

  runtime.irHints.generatedClauses &= name
  runtime.vm.sourceMap[name] = initTable[uint, tuple[message: string, line: uint]]()

  if name != "outer":
    runtime.loadArgumentsOntoStack(fn)
    # runtime.markGlobal(name)
  else:
    if allocateConstants:
      constants.generateStdIr(runtime)
      inc runtime.addrIdx

      for i, typ in runtime.types:
        let idx = runtime.addrIdx
        runtime.markGlobal(typ.name)
        runtime.ir.createField(idx, 0, "@bali_object_type")
        runtime.types[i].singletonId = idx

  for i, stmt in scope.stmts:
    runtime.generateBytecode(fn, stmt, index = i.uint.some)

  for child in scope.children:
    runtime.generateBytecodeForScope(child)

proc findField*(atom: JSValue, accesses: FieldAccess): JSValue =
  if accesses.identifier in atom.objFields:
    if accesses.next == nil:
      return atom.objValues[atom.objFields[accesses.identifier]]
    else:
      return atom.findField(accesses.next)
  else:
    return undefined()

proc computeTypeof*(runtime: Runtime, atom: JSValue): string =
  ## Compute the type of an atom.
  case atom.kind
  of String:
    return "string"
  of Integer, Float:
    return "number"
  of Null, Sequence:
    return "object"
  of Object:
    if runtime.isA(atom, JSString):
      return "string"

    if runtime.isA(atom, JSBigInt):
      return "bigint"

    return "object"
  of Boolean:
    return "boolean"
  of BigInteger:
    return "bigint"
  of Undefined:
    return "undefined"
  of NativeCallable, BytecodeCallable:
    return "function"
  else:
    unreachable

proc generateInternalIR*(runtime: Runtime) =
  ## Generate the internal functions needed by Bali to work properly.
  runtime.vm[].registerBuiltin(
    "BALI_RESOLVEFIELD",
    proc(op: Operation) =
      inc runtime.statFieldAccesses
      let
        index = &getInt(&runtime.argument(1))
        storeAt = &getInt(&runtime.argument(2))

        accesses = createFieldAccess(
          (
            proc(): seq[string] =
              if runtime.argumentCount() < 3:
                return

              var accesses: seq[string]
              for i in 3 .. runtime.argumentCount():
                accesses.add(&(&runtime.argument(i)).getStr())

              accesses
          )()
        )

      debug "hooks: BALI_RESOLVEFIELD: index = " & $index & ", destination = " & $storeAt

      let atom = &runtime.vm[].get(index)

      if atom.isUndefined():
        runtime.typeError("value is undefined")

      if atom.isNull():
        runtime.typeError("value is null")

      if atom.kind != Object:
        debug "runtime: atom is not an object, returning undefined."
        runtime.vm[].addAtom(undefined(), storeAt)
        return

      runtime.vm[].addAtom(atom.findField(accesses), storeAt),
  )

  runtime.vm[].registerBuiltin(
    "BALI_TYPEOF",
    proc(op: Operation) =
      inc runtime.statTypeofCalls
      let atom = runtime.argument(1)
      assert(*atom, "BUG: Atom was empty when calling BALI_TYPEOF_INTERNAL!")
      ret runtime.computeTypeof(&atom)
    ,
  )

  runtime.vm[].registerBuiltin(
    "BALI_INDEX",
    proc(op: Operation) =
      let
        atom = runtime.argument(1)
        index = runtime.argument(2)

      assert(*atom, "BUG: Atom was empty when calling BALI_INDEX_INTERNAL!")
      assert(
        (&atom).kind == Sequence,
        "BUG: BALI_INDEX_INTERNAL was passed a " & $(&atom).kind,
      )

      let idx = int(&(&index).getNumeric())
      var vec = (&atom).sequence
      if idx < 0 or idx > vec.len - 1:
        ret undefined()

      ret vec[idx].addr # TODO: add indexing for tables/object fields
    ,
  )

  runtime.vm[].registerBuiltin(
    "BALI_EQUATE_ATOMS",
    proc(op: Operation) =
      # This is supposed to work exactly how the EQU instruction works
      let
        a = &runtime.argument(1)
        b = &runtime.argument(2)

      runtime.vm.registers.callArgs.reset()

      let res = runtime.isLooselyEqual(a, b)
      if not res:
        # Jump 2 instructions ahead
        runtime.vm.currIndex += 1
    ,
  )

  runtime.vm[].registerBuiltin(
    "BALI_EQUATE_ATOMS_STRICT",
    proc(op: Operation) =
      # This is supposed to work exactly how the EQU instruction works
      let
        a = &runtime.argument(1)
        b = &runtime.argument(2)

      runtime.vm.registers.callArgs.reset()

      let res = runtime.isStrictlyEqual(a, b)
      if not res:
        # Jump 2 instructions ahead
        runtime.vm.currIndex += 1
    ,
  )

  runtime.vm[].registerBuiltin(
    "BALI_WRITE_FIELD",
    proc(_: Operation) =
      let
        destinationAtomIndex = uint(&getInt(&runtime.argument(1)))
        writeAtom = &runtime.argument(2)

      var accesses = createFieldAccess(
        (
          proc(): seq[string] =
            if runtime.argumentCount() < 3:
              return

            var accesses: seq[string]
            for i in 3 .. runtime.argumentCount():
              accesses.add(&(&runtime.argument(i)).getStr())

            accesses
        )()
      )

      var destAtom = runtime.vm.stack[destinationAtomIndex]

      if destAtom.kind != Object:
        ret writeAtom

      template checkDestAtom() =
        if destAtom.isUndefined:
          runtime.typeError("Value is undefined")

        if destAtom.isNull:
          runtime.typeError("Value is null")

      checkDestAtom

      while true:
        let next = accesses.next
        if next == nil:
          break
        else:
          accesses = accesses.next

        destAtom = destAtom[accesses.identifier]
        checkDestAtom

      destAtom[accesses.identifier] = writeAtom

      runtime.vm.stack[destinationAtomIndex] = ensureMove(destAtom)
      ret writeAtom
    ,
  )

  if runtime.opts.insertDebugHooks:
    runtime.defineFn(
      "baliGC_Dump",
      proc() =
        echo GC_getStatistics()
      ,
    )

    runtime.generateDescribeFnCode()

    runtime.defineFn(
      "baliGC_FullCollect",
      proc() =
        GC_fullCollect(),
    )

    runtime.defineFn(
      "baliGC_PartialCollect",
      proc() =
        let limit = &(&runtime.argument(1)).getInt()
        GC_partialCollect(limit),
    )

    runtime.defineFn(
      "baliVM_IsCompiled",
      proc() =
        ret runtime.vm.runningCompiled
      ,
    )

export types
