## Bali runtime (MIR emitter)

import std/[options, hashes, logging, strutils, tables, importutils]
import bali/runtime/vm/ir/generator
import bali/runtime/vm/runtime/[tokenizer, prelude]
import bali/grammar/prelude
import bali/internal/sugar
import
  bali/runtime/[
    normalize, types, atom_helpers, atom_obj_variant, arguments, statement_utils,
    bridge, describe,
  ]
import bali/runtime/optimize/[mutator_loops, redundant_loop_allocations]
import bali/runtime/vm/heap/boehm
import bali/runtime/abstract/equating
import bali/stdlib/prelude
import crunchy, pretty

privateAccess(PulsarInterpreter)
privateAccess(Runtime)
privateAccess(AllocStats)

proc generateIR*(
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
    debug "ir: expand Call statement"
    for i, arg in stmt.arguments:
      if arg.kind == cakAtom:
        debug "ir: load immutable value to expand Call's immediate arguments: " &
          arg.atom.crush()
        discard runtime.loadIRAtom(arg.atom)
        runtime.markInternal(stmt, $i)
      elif arg.kind == cakImmediateExpr:
        debug "ir: add code to solve expression to expand Call's immediate arguments"
        runtime.markInternal(stmt, $i)
        runtime.generateIR(
          fn, arg.expr, internal = true, exprStoreIn = some($i), parentStmt = some(stmt)
        )
  of ConstructObject:
    debug "ir: expand ConstructObject statement"
    for i, arg in stmt.args:
      if arg.kind == cakAtom:
        debug "ir: load immutable value to ConstructObject's immediate arguments: " &
          arg.atom.crush()

        discard runtime.loadIRAtom(arg.atom)
        let name = $hash(stmt) & '_' & $i
        runtime.markInternal(stmt, name)
  of CallAndStoreResult:
    debug "ir: expand CallAndStoreResult statement by expanding child Call statement"
    runtime.expand(fn, stmt.storeFn, internal)
  of ThrowError:
    debug "ir: expand ThrowError"

    if *stmt.error.str:
      runtime.generateIR(
        fn,
        createImmutVal("error_msg", stackStr(&stmt.error.str)),
        ownerStmt = some(stmt),
        internal = true,
      )
  of BinaryOp:
    debug "ir: expand BinaryOp"

    if *stmt.binStoreIn:
      debug "ir: BinaryOp evaluation will be stored in: " & &stmt.binStoreIn & " (" &
        $runtime.addrIdx & ')'
      runtime.ir.loadInt(runtime.addrIdx, 0)

      if not internal:
        debug "ir: ...locally"
        runtime.markLocal(fn, &stmt.binStoreIn)
      else:
        debug "ir: ...internally"
        print stmt
        runtime.markInternal(stmt, &stmt.binStoreIn)

    if stmt.binLeft.kind == AtomHolder:
      debug "ir: BinaryOp left term is an atom"
      runtime.generateIR(
        fn,
        createImmutVal("left_term", stmt.binLeft.atom),
        ownerStmt = some(stmt),
        internal = true,
      )
    #else:
    #  debug "ir: BinaryOp left term is an ident, reserving new index for result"
    #  runtime.generateIR(fn, createImmutVal("store_in", stackNull()), ownerStmt = some(stmt), internal = true)

    if stmt.binRight.kind == AtomHolder:
      debug "ir: BinaryOp right term is an atom"
      runtime.generateIR(
        fn,
        createImmutVal("right_term", stmt.binRight.atom),
        ownerStmt = some(stmt),
        internal = true,
      )
    elif stmt.binRight.kind == IdentHolder:
      debug "ir: BinaryOp right term is an ident"
  of IfStmt:
    debug "ir: expand IfStmt"

    if stmt.conditionExpr.binLeft.kind == AtomHolder:
      debug "ir: if-stmt: left term is an atom"
      runtime.generateIR(
        fn,
        createImmutVal("left_term", stmt.conditionExpr.binLeft.atom),
        ownerStmt = some(stmt),
        internal = true,
      )

    if stmt.conditionExpr.binRight.kind == AtomHolder:
      debug "ir: if-stmt: right term is an atom"
      runtime.generateIR(
        fn,
        createImmutVal("right_term", stmt.conditionExpr.binRight.atom),
        ownerStmt = some(stmt),
        internal = true,
      )
  of WhileStmt:
    debug "ir: expand WhileStmt"
    if stmt.whConditionExpr.binLeft.kind == AtomHolder:
      debug "ir: while-stmt: left term is an atom"
      runtime.generateIR(
        fn,
        createImmutVal("left_term", stmt.whConditionExpr.binLeft.atom),
        ownerStmt = some(stmt),
        internal = true,
      )

    if stmt.whConditionExpr.binRight.kind == AtomHolder:
      debug "ir: while-stmt: right term is an atom"
      runtime.generateIR(
        fn,
        createImmutVal("right_term", stmt.whConditionExpr.binRight.atom),
        ownerStmt = some(stmt),
        internal = true,
      )
  of ReturnFn:
    if *stmt.retVal:
      runtime.generateIR(
        fn,
        createImmutVal("retval", &stmt.retVal),
        internal = true,
        ownerStmt = some(stmt),
      )
    else:
      runtime.generateIR(
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
  runtime.generateIR(
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

proc generateIRForScope*(runtime: Runtime, scope: Scope, allocateConstants: bool = true)

func willIRGenerateClause*(runtime: Runtime, clause: string): bool {.inline.} =
  for cls in runtime.ir.modules:
    if cls.name == clause:
      return true

  false

proc generateIR*(
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
  ## **NOTE**: This function can be recursive in nature and has side effects.
  case stmt.kind
  of CreateImmutVal:
    debug "emitter: generate IR for creating immutable value with identifier: " &
      stmt.imIdentifier

    let idx = runtime.loadIRAtom(deepCopy(stmt.imAtom))

    if not internal:
      if fn.name == "outer":
        debug "emitter: marking index as global because it's in outer-most scope: " &
          $idx
        runtime.ir.markGlobal(idx)

      runtime.markLocal(fn, stmt.imIdentifier, index = some(idx))
    else:
      assert *ownerStmt
      runtime.markInternal(&ownerStmt, stmt.imIdentifier)
  of CreateMutVal:
    let idx = runtime.loadIRAtom(stmt.mutAtom)

    if fn.name.len < 1:
      runtime.ir.markGlobal(idx)

    if not internal:
      if fn.name == "outer":
        debug "emitter: marking index as global because it's in outer-most scope: " &
          $idx
        runtime.ir.markGlobal(idx)

      runtime.markLocal(fn, stmt.mutIdentifier, index = some(idx))
    else:
      assert *ownerStmt
      runtime.markInternal(&ownerStmt, stmt.mutIdentifier)
  of Call:
    runtime.expand(fn, stmt)
    var nam =
      if stmt.mangle:
        stmt.fn.normalizeIRName()
      else:
        stmt.fn.function

    if *stmt.fn.field:
      let typName = block:
        var curr = &stmt.fn.field
        while true:
          if curr.prev == nil:
            break

          curr = curr.prev

        curr.identifier

      let typ = runtime.getTypeFromName(typName)

      if *typ:
        nam =
          "BALI_" & toUpperAscii(typName) & '_' &
          toUpperAscii(stmt.fn.function.normalizeIRName())
      else:
        runtime.ir.passArgument(
          runtime.index((&stmt.fn.field).identifier, defaultParams(fn))
        )

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
        runtime.ir.markGlobal(index)
        runtime.ir.passArgument(index)
      of cakImmediateExpr:
        let index = runtime.index($i, internalIndex(stmt))
        runtime.ir.markGlobal(index)
        runtime.ir.passArgument(index)

    # Traditional function calls (pre-defined functions)
    #[ if runtime.willIRGenerateClause(nam) or
        runtime.vm.builtins.contains(nam):]#
    debug "interpreter: generate IR for calling traditional function: " & nam &
      (if stmt.mangle: " (mangled)" else: newString 0)

    runtime.ir.call(nam)
    runtime.ir.resetArgs()
    # Reset the call arguments register to prevent this call's arguments from leaking into future calls

    if not stmt.expectsReturnVal and runtime.opts.codegen.aggressivelyFreeRetvals:
      runtime.ir.zeroRetval()
        # Destroy the return value, if any. This helps conserve memory.
    #[ else:
      # Dynamic bytecode segment references
      discard runtime.ir.addOp(
        IROperation(
          opcode: ExecuteBytecodeCallable,
          arguments: @[stackUinteger(runtime.index(nam, defaultParams(fn)))],
        )
      )
      runtime.ir.resetArgs() ]#
  of ReturnFn:
    assert not (*stmt.retVal and *stmt.retIdent),
      "ReturnFn statement cannot have both return atom and return ident at once!"

    runtime.expand(fn, stmt)

    if !stmt.retIdent:
      runtime.ir.returnFn(runtime.index("retval", internalIndex(stmt)).int)
    else:
      runtime.ir.returnFn(runtime.index(&stmt.retIdent, defaultParams(fn)).int)
  of CallAndStoreResult:
    runtime.generateIR(fn, stmt.storeFn)
    runtime.markLocal(fn, stmt.storeIdent)

    let index = runtime.index(stmt.storeIdent, defaultParams(fn))
    debug "emitter: call-and-store result will be stored in ident \"" & stmt.storeIdent &
      "\" or index " & $index
    runtime.ir.loadObject(index) # load `undefined` on that index
    runtime.ir.readRegister(index, Register.ReturnValue)
    runtime.ir.zeroRetval()
  of ConstructObject:
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
        runtime.ir.markGlobal(index)
        runtime.ir.passArgument(index)
      of cakImmediateExpr:
        discard

    runtime.ir.call("BALI_CONSTRUCTOR_" & stmt.objName.toUpperAscii())
    runtime.ir.resetArgs()
  of ReassignVal:
    if not stmt.reIdentifier.contains('.'):
      let index = runtime.index(stmt.reIdentifier, defaultParams(fn))

      info "emitter: reassign value at index " & $index & " with ident \"" &
        stmt.reIdentifier & "\" to " & stmt.reAtom.crush()

      # TODO: make this use loadIRAtom
      case stmt.reAtom.kind
      of Integer:
        runtime.ir.loadInt(index, stmt.reAtom)
      of UnsignedInt:
        runtime.ir.loadUint(index, &stmt.reAtom.getUint())
      of String:
        discard runtime.ir.loadStr(index, stmt.reAtom)
      of Float:
        discard runtime.ir.addOp(
          IROperation(opcode: LoadFloat, arguments: @[stackUinteger index, stmt.reAtom])
        ) # FIXME: mirage: loadFloat isn't implemented
      else:
        unreachable

      runtime.ir.markGlobal(index)
    else:
      # field overwrite!
      let accesses = createFieldAccess(stmt.reIdentifier.split('.'))
      let atomIndex = runtime.loadIRAtom(stmt.reAtom)

      inc runtime.addrIdx

      # prepare for internal call
      runtime.ir.passArgument(
        runtime.loadIRAtom(
          stackUinteger(runtime.index(accesses.identifier, defaultParams(fn)))
        )
      ) # 1: Atom index that needs its field to be overwritten

      inc runtime.addrIdx

      runtime.ir.passArgument(atomIndex) # 2: The atom to be put in the field

      runtime.loadFieldAccessStrings(accesses) # 3: The field access strings

      runtime.ir.call("BALI_WRITE_FIELD")
      runtime.ir.resetArgs()
  of ThrowError:
    info "emitter: add error-throw logic"

    if *stmt.error.str:
      let msg = &stmt.error.str

      info "emitter: error string that will be raised: `" & msg & '`'
      runtime.expand(fn, stmt, internal)

      runtime.ir.passArgument(runtime.index("error_msg", internalIndex(stmt)))
      runtime.ir.call("BALI_THROWERROR")
    elif *stmt.error.ident:
      runtime.ir.passArgument(runtime.index(&stmt.error.ident, defaultParams(fn)))
      runtime.ir.call("BALI_THROWERROR")
    else:
      unreachable
  of BinaryOp:
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
      runtime.ir.addInt(leftIdx, rightIdx)
    of BinaryOperation.Sub:
      runtime.ir.subInt(leftIdx, rightIdx)
    of BinaryOperation.Mult:
      runtime.ir.multInt(leftIdx, rightIdx)
    of BinaryOperation.Div:
      runtime.ir.divInt(leftIdx, rightIdx)
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
        unequalJmp = runtime.ir.addOp(IROperation(opcode: Jump)) - 1
          # left != right branch

      # left == right branch
      let equalBranch =
        if leftTerm.kind == AtomHolder:
          runtime.ir.loadBool(leftIdx, true)
        else:
          runtime.ir.loadBool(runtime.index(&stmt.binStoreIn, defaultParams(fn)), true)
      runtime.ir.overrideArgs(equalJmp, @[stackUinteger(equalBranch)])
      runtime.ir.jump(equalBranch + 3)

      # left != right branch
      let unequalBranch =
        if leftTerm.kind == AtomHolder:
          runtime.ir.loadBool(leftIdx, false)
        else:
          runtime.ir.loadBool(runtime.index(&stmt.binStoreIn, defaultParams(fn)), false)
      runtime.ir.overrideArgs(unequalJmp, @[stackUinteger(unequalBranch)])
    of BinaryOperation.NotEqual:
      runtime.ir.passArgument(leftIdx)
      runtime.ir.passArgument(rightIdx)
      runtime.ir.call("BALI_EQUATE_ATOMS")
      # FIXME: really weird bug in mirage's IR generator. wtf?
      let equalJmp = runtime.ir.addOp(IROperation(opcode: Jump)) - 1
        # left == right branch
      let unequalJmp = runtime.ir.addOp(IROperation(opcode: Jump)) - 1
        # left != right branch

      # left != right branch: true
      let unequalBranch =
        if leftTerm.kind == AtomHolder:
          runtime.ir.loadBool(leftIdx, true)
        else:
          runtime.ir.loadBool(runtime.index(&stmt.binStoreIn, defaultParams(fn)), true)
      runtime.ir.overrideArgs(unequalJmp, @[stackUinteger(unequalBranch)])
      runtime.ir.jump(unequalBranch + 3)

      # left == right branch: false
      let equalBranch =
        if leftTerm.kind == AtomHolder:
          runtime.ir.loadBool(leftIdx, false)
        else:
          runtime.ir.loadBool(runtime.index(&stmt.binStoreIn, defaultParams(fn)), false)
      runtime.ir.overrideArgs(equalJmp, @[stackUinteger(equalBranch)])
    of BinaryOperation.GreaterThan, BinaryOperation.LesserThan:
      discard runtime.ir.addOp(
        IROperation(
          opcode: GreaterThanInt,
          arguments: @[stackUinteger leftIdx, stackUinteger rightIdx],
        ) # FIXME: mirage doesn't have a nicer IR function for this.
      )

      #[ let
        trueJump = runtime.ir.placeholder(Jump) - 1
        falseJump = runtime.ir.placeholder(Jump) - 1
      
      runtime.ir.overrideArgs(trueJump, @[stackUinteger runtime.ir.loadBool(leftIdx, true)])
      let jmpAfterTrueBranch = runtime.ir.placeholder(Jump) - 1

      let falseBranch = runtime.ir.loadBool(leftIdx, false) - 1
      
      runtime.ir.overrideArgs(jmpAfterTrueBranch, @[stackUinteger(falseBranch + 1)])
      runtime.ir.overrideArgs(falseJump, @[stackUinteger(falseBranch + 1)]) ]#
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
  of IfStmt:
    info "emitter: emitting IR for if statement"
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
      discard runtime.ir.addOp(
        IROperation(
          opcode: GreaterThanInt,
          arguments: @[stackUinteger lhsIdx, stackUinteger rhsIdx],
        ) # FIXME: mirage doesn't have a nicer IR function for this.
      )
    of BinaryOperation.LesserThan:
      discard runtime.ir.addOp(
        IROperation(
          opcode: LesserThanInt,
          arguments: @[stackUinteger lhsIdx, stackUinteger rhsIdx],
        )
      )
    of BinaryOperation.GreaterOrEqual:
      discard runtime.ir.addOp(
        IROperation(
          opcode: GreaterThanEqualInt,
          arguments: @[stackUinteger lhsIdx, stackUinteger rhsIdx],
        )
      )
    of BinaryOperation.LesserOrEqual:
      discard runtime.ir.addOp(
        IROperation(
          opcode: LesserThanEqualInt,
          arguments: @[stackUinteger lhsIdx, stackUinteger rhsIdx],
        )
      )
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

    runtime.generateIRForScope(stmt.branchTrue, allocateConstants = false)
      # generate branch one
    let skipBranchTwoJmp = runtime.ir.addOp(IROperation(opcode: Jump)) - 1
      # jump beyond branch two, don't accidentally execute it
    let endOfBranchOne = getCurrOpNum().uint

    runtime.generateIRForScope(stmt.branchFalse, allocateConstants = false)
      # generate branch two
    let endOfBranchTwo = getCurrOpNum().uint
    runtime.ir.overrideArgs(skipBranchTwoJmp, @[stackUinteger(endOfBranchTwo)])

    case stmt.conditionExpr.op
    of BinaryOperation.Equal, BinaryOperation.GreaterThan, BinaryOperation.TrueEqual,
        BinaryOperation.GreaterOrEqual, BinaryOperation.LesserThan,
        BinaryOperation.LesserOrEqual:
      runtime.ir.overrideArgs(falseJump, @[stackUinteger(endOfBranchOne)])
      runtime.ir.overrideArgs(trueJump, @[stackUinteger(falseJump + 2)])
    of BinaryOperation.NotEqual:
      runtime.ir.overrideArgs(trueJump, @[stackUinteger(getCurrOpNum().uint)])
      runtime.ir.overrideArgs(falseJump, @[stackUinteger(falseJump + 2)])
    else:
      unreachable
  of CopyValMut:
    debug "emitter: generate IR for copying value to a mutable address with source: " &
      stmt.cpMutSourceIdent & " and destination: " & stmt.cpMutDestIdent
    runtime.generateIR(
      fn, createMutVal(stmt.cpMutDestIdent, stackNull()), internal = false
    )
    let dest = runtime.addrIdx - 1

    runtime.ir.copyAtom(runtime.index(stmt.cpMutSourceIdent, defaultParams(fn)), dest)
  of CopyValImmut:
    debug "emitter: generate IR for copying value to an immutable address with source: " &
      stmt.cpImmutSourceIdent & " and destination: " & stmt.cpImmutDestIdent
    runtime.generateIR(
      fn, createMutVal(stmt.cpImmutDestIdent, stackNull()), internal = false
    )
    let dest = runtime.addrIdx - 1

    runtime.ir.copyAtom(runtime.index(stmt.cpImmutSourceIdent, defaultParams(fn)), dest)
  of WhileStmt:
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
      runtime.generateIRForScope(placeBefore, allocateConstants = false)

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
    of GreaterThan, LesserThan:
      discard runtime.ir.addOp(
        IROperation(
          opcode: GreaterThanInt,
          arguments: @[stackUinteger lhsIdx, stackUinteger rhsIdx],
        ) # FIXME: mirage doesn't have a nicer IR function for this.
      )
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
      runtime.generateIRForScope(stmt.whBranch, allocateConstants = false)
    else:
      runtime.generateIRForScope(
        (&allocElimResult).modifiedBody, allocateConstants = false
      )

    runtime.ir.jump(jmpIntoComparison.uint) # jump back to the comparison logic

    let jmpPastBody = getCurrOpNum()

    if runtime.irHints.breaksGeneratedAt.len > 0:
      for brk in runtime.irHints.breaksGeneratedAt:
        runtime.ir.overrideArgs(brk, @[stackUinteger(jmpPastBody.uint)])
    else:
      runtime.ir.overrideArgs(dummyJump, @[stackUinteger(jmpPastBody.uint)])

    runtime.irHints.breaksGeneratedAt.reset()

    case stmt.whConditionExpr.op
    of BinaryOperation.Equal, BinaryOperation.TrueEqual, BinaryOperation.GreaterThan:
      runtime.ir.overrideArgs(trueJump, @[stackUinteger(jmpIntoBody.uint)])
      runtime.ir.overrideArgs(escapeJump, @[stackUinteger(jmpPastBody.uint)])
    of BinaryOperation.NotEqual, BinaryOperation.LesserThan:
      runtime.ir.overrideArgs(trueJump, @[stackUinteger(jmpPastBody.uint)])
      runtime.ir.overrideArgs(escapeJump, @[stackUinteger(jmpIntoBody.uint)])
    else:
      unreachable
  of Increment:
    debug "emitter: generate IR for increment"
    runtime.ir.incrementInt(runtime.index(stmt.incIdent, defaultParams(fn)))
  of Decrement:
    debug "emitter: generate IR for decrement"
    runtime.ir.decrementInt(runtime.index(stmt.decIdent, defaultParams(fn)))
  of Break:
    debug "emitter: generate IR for break"
    runtime.irHints.breaksGeneratedAt &= runtime.ir.addOp(IROperation(opcode: Jump)) - 1
  of Waste:
    debug "emitter: generate IR for wasting value"
    assert(
      not (*stmt.wstAtom and *stmt.wstIdent),
      "Cannot waste atom and identifier at once!",
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
      runtime.ir.call(normalizeIRName "console.log")
  of AccessArrayIndex:
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
    runtime.ir.resetArgs()
  of TernaryOp:
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
  of ForLoop:
    # Generate IR for initializer, if it exists.
    if *stmt.forLoopInitializer:
      runtime.generateIR(fn, &stmt.forLoopInitializer)

    proc getCurrOpNum(): uint =
      for module in runtime.ir.modules:
        if module.name == runtime.ir.currModule:
          return uint(module.operations.len + 1)

      unreachable
      0'u

    let conditionalJump = getCurrOpNum() + 1'u

    # Generate IR for conditional, if it exists.
    # TODO: Else, just equate `0` to `0`

    var inverted = false
    if *stmt.forLoopCond:
      let cond = &stmt.forLoopCond
      inverted = cond.op in {BinaryOperation.LesserThan}
      runtime.generateIR(fn, cond)
    else:
      unreachable

    # Now, generate the jumps for either going into the loop body or outside it.
    # If conditional is true, jump into the body
    # else, jump outside
    let jmpIntoBody = stackUinteger(getCurrOpNum() + 2'u)

    let jump1 = runtime.ir.placeholder(Jump) - 1
    let jump2 = runtime.ir.placeholder(Jump) - 1

    runtime.generateIRForScope(stmt.forLoopBody, allocateConstants = false)

    # Generate code for the incrementor/stepper
    if *stmt.forLoopIter:
      runtime.generateIR(fn, &stmt.forLoopIter)

    let jmpOutsideBody = stackUinteger(getCurrOpNum() + 1'u)

    if not inverted:
      runtime.ir.overrideArgs(jump1, @[jmpIntoBody])
      runtime.ir.overrideArgs(jump2, @[jmpOutsideBody])
    else:
      runtime.ir.overrideArgs(jump1, @[jmpOutsideBody])
      runtime.ir.overrideArgs(jump2, @[jmpIntoBody])

    runtime.ir.jump(conditionalJump)
  else:
    warn "emitter: unimplemented IR generation directive: " & $stmt.kind

proc loadArgumentsOntoStack*(runtime: Runtime, fn: Function) =
  info "emitter: loading up function signature arguments onto stack via IR: " & fn.name

  for i, arg in fn.arguments:
    runtime.markLocal(fn, arg)
    runtime.ir.readRegister(
      runtime.index(arg, defaultParams(fn)), i.uint, Register.CallArgument
    )

  runtime.ir.resetArgs() # reset the call param register

proc generateIRForScope*(
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

  debug "generateIRForScope(): function name: " & name
  if not runtime.clauses.contains(name):
    runtime.clauses.add(name)
    runtime.ir.newModule(name.normalizeIRName())

  runtime.irHints.generatedClauses &= name

  if name != "outer":
    runtime.loadArgumentsOntoStack(fn)
    runtime.markGlobal(name)
  else:
    if allocateConstants:
      constants.generateStdIr(runtime)
      inc runtime.addrIdx

      for clause in runtime.clauses:
        if clause == "outer":
          continue # Nothing should be able to call into the outer scope.

        let fnIndex = runtime.index(clause, defaultParams(fn))
        discard runtime.ir.addOp(
          IROperation(
            opcode: LoadBytecodeCallable,
            arguments: @[stackUinteger(fnIndex), stackStr(clause)],
          )
        )
        runtime.ir.markGlobal(fnIndex)

      for i, typ in runtime.types:
        let idx = runtime.addrIdx
        runtime.markGlobal(typ.name)
        runtime.ir.loadObject(idx)
        runtime.ir.createField(idx, 0, "@bali_object_type")
        runtime.ir.markGlobal(idx)
        runtime.types[i].singletonId = idx

  for i, stmt in scope.stmts:
    runtime.generateIR(fn, stmt, index = i.uint.some)

  for child in scope.children:
    runtime.generateIRForScope(child)

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
  of Integer, Float, UnsignedInt:
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
  else:
    unreachable

proc generateInternalIR*(runtime: Runtime) =
  ## Generate the internal functions needed by Bali to work properly.
  runtime.ir.newModule("BALI_RESOLVEFIELD")
  runtime.vm.registerBuiltin(
    "BALI_RESOLVEFIELD_INTERNAL",
    proc(op: Operation) =
      inc runtime.statFieldAccesses
      let
        index = uint(&(&runtime.argument(1)).getInt())
        storeAt = uint(&(&runtime.argument(2)).getInt())
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

      let atom = runtime.vm.stack[index]
        # FIXME: weird bug with mirage, `get` returns a NULL atom.

      if atom.isUndefined():
        runtime.typeError("value is undefined")

      if atom.isNull():
        runtime.typeError("value is stackNull")

      if atom.kind != Object:
        debug "runtime: atom is not an object, returning undefined."
        runtime.vm.addAtom(obj(), storeAt)
        return

      for typ in runtime.types:
        if typ.singletonId == index:
          debug "runtime: singleton ID for type `" & typ.name &
            "` matches field access index"

          for name, member in typ.members:
            if member.isFn:
              continue
            if name != accesses.identifier:
              continue

            if accesses.next != nil:
              assert(member.atom().kind == Object)
              runtime.vm.addAtom(member.atom().findField(accesses.next), storeAt)
            else:
              runtime.vm.addAtom(member.atom(), storeAt)
            return

      runtime.vm.addAtom(atom.findField(accesses), storeAt),
  )
  runtime.ir.call("BALI_RESOLVEFIELD_INTERNAL")

  runtime.ir.newModule("BALI_TYPEOF")
  runtime.vm.registerBuiltin(
    "BALI_TYPEOF_INTERNAL",
    proc(op: Operation) =
      inc runtime.statTypeofCalls
      let atom = runtime.argument(1)
      assert(*atom, "BUG: Atom was empty when calling BALI_TYPEOF_INTERNAL!")
      ret runtime.computeTypeof(&atom)
    ,
  )
  runtime.ir.call("BALI_TYPEOF_INTERNAL")

  runtime.ir.newModule("BALI_INDEX")
  runtime.vm.registerBuiltin(
    "BALI_INDEX_INTERNAL",
    proc(op: Operation) =
      let
        atom = runtime.argument(1)
        index = runtime.argument(2)

      assert(*atom, "BUG: Atom was empty when calling BALI_INDEX_INTERNAL!")
      assert(
        (&atom).kind == Sequence,
        "BUG: BALI_INDEX_INTERNAL was passed a " & $(&atom).kind,
      )

      let idx = &(&index).getInt()
      var vec = (&atom).sequence
      if idx < 0 or idx > vec.len - 1:
        ret undefined()

      ret vec[idx].addr # TODO: add indexing for tables/object fields
    ,
  )
  runtime.ir.call("BALI_INDEX_INTERNAL")

  runtime.vm.registerBuiltin(
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

  runtime.vm.registerBuiltin(
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

  runtime.vm.registerBuiltin(
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
          runtime.typeError("Value is stackNull")

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

proc run*(runtime: Runtime) =
  ## This function starts the code generator and executes the generated bytecode.
  ## It also starts the interpreter's garbage collector. Any attempts to interact with the Bali GC
  ## prior to this function being called will result in undefined behaviour, generally an infinite loop.

  runtime.allocStatsStart = getAllocStats()
  runtime.test262 = runtime.ast.test262
  console.generateStdIR(runtime)
  math.generateStdIR(runtime)
  uri.generateStdIR(runtime)
  errors_ir.generateStdIR(runtime)
  base64.generateStdIR(runtime)
  json.generateStdIR(runtime)
  encodeUri.generateStdIR(runtime)
  std_string.generateStdIR(runtime)
  date.generateStdIR(runtime)
  std_bigint.generateStdIR(runtime)
  std_number.generateStdIR(runtime)
  std_set.generateStdIR(runtime)

  parseIntGenerateStdIR(runtime)

  runtime.generateInternalIR()

  if runtime.opts.test262:
    test262.generateStdIR(runtime)
    setDeathCallback(
      proc(vm: PulsarInterpreter, exitCode: int) =
        if not vm.trace.exception.message.contains(runtime.test262.negative.`type`):
          quit(1)
        else:
          quit(0)
    )

  for ident in ["undefined", "NaN", "true", "false", "null"]:
    runtime.markGlobal(ident)

  runtime.generateIRForScope(runtime.ast.scopes[0])

  constants.generateStdIR(runtime)

  let source = runtime.ir.emit()

  privateAccess(PulsarInterpreter) # modern problems require modern solutions
  runtime.vm.tokenizer = tokenizer.newTokenizer(source)

  debug "interpreter: the following bytecode will now be executed"

  if not runtime.opts.dumpBytecode:
    debug source
  else:
    echo source
    quit(0)

  debug "interpreter: begin VM analyzer"
  runtime.vm.analyze()

  debug "interpreter: setting entry point to `outer`"
  runtime.vm.setEntryPoint("outer")

  for error in runtime.ast.errors:
    runtime.syntaxError($error, if runtime.opts.test262: 0 else: 1)

  if runtime.ast.doNotEvaluate and runtime.opts.test262:
    debug "runtime: `doNotEvaluate` is set to `true` in Test262 mode - skipping execution."
    quit(0)
  debug "interpreter: passing over execution to VM - here goes nothing!"
  runtime.vm.run()

proc newRuntime*(
    file: string, ast: AST, opts: InterpreterOpts = default(InterpreterOpts)
): Runtime {.inline.} =
  ## Instantiate the runtime by feeding it the name of the file executed and the AST, alongside the interpreter settings.
  ## If the input isn't from a file, you can set it to anything - it's primarily used for caching.
  ## The AST must be valid.
  ## You can check the options exposed to you in `InterpreterOpts` by checking its documentation.
  # initializeGC(getStackPtr(), 4) # Initialize the M&S garbage collector

  boehmGCinit()
  boehmGC_enable()

  Runtime(
    ast: ast,
    clauses: @[],
    ir: newIRGenerator("bali-" & $sha256(file).toHex()),
    vm: newPulsarInterpreter(""),
    opts: opts,
  )

export types
