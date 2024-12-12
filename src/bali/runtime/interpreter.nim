## Bali runtime (MIR emitter)
##

import std/[options, hashes, logging, sugar, strutils, tables, importutils]
import mirage/ir/generator
import mirage/runtime/[tokenizer, prelude]
import bali/grammar/prelude
import bali/internal/sugar
import bali/runtime/[normalize, types, atom_helpers, atom_obj_variant, arguments, statement_utils, bridge]
import bali/runtime/optimize/[mutator_loops]
import bali/stdlib/prelude
import crunchy, pretty

privateAccess(PulsarInterpreter)

proc generateIR*(
  runtime: Runtime,
  fn: Function,
  stmt: Statement,
  internal: bool = false,
  ownerStmt: Option[Statement] = none(Statement),
  exprStoreIn: Option[string] = none(string),
  parentStmt: Option[Statement] = none(Statement),
  index: Option[uint] = none(uint)
)

proc expand*(runtime: Runtime, fn: Function, stmt: Statement, internal: bool = false) =
  case stmt.kind
  of Call:
    debug "ir: expand Call statement"
    for i, arg in stmt.arguments:
      if arg.kind == cakAtom:
        debug "ir: load immutable value to expand Call's immediate arguments: " &
          arg.atom.crush()
        runtime.generateIR(
          fn, createImmutVal($i, arg.atom), ownerStmt = some(stmt), internal = true
        ) # XXX: should this be mutable?
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
        runtime.generateIR(
          fn,
          createImmutVal($hash(stmt) & '_' & $i, arg.atom),
          ownerStmt = some(stmt),
          internal = true,
        ) # XXX: should this be mutable?
  of CallAndStoreResult:
    debug "ir: expand CallAndStoreResult statement by expanding child Call statement"
    runtime.expand(fn, stmt.storeFn, internal)
  of ThrowError:
    debug "ir: expand ThrowError"

    if *stmt.error.str:
      runtime.generateIR(
        fn,
        createImmutVal("error_msg", str(&stmt.error.str)),
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
    #  runtime.generateIR(fn, createImmutVal("store_in", null()), ownerStmt = some(stmt), internal = true)

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
        createImmutVal("retval", undefined()),
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

proc semanticError*(runtime: Runtime, error: SemanticError) =
  info "emitter: caught semantic error (" & $error.kind & ')'

  runtime.semanticErrors &= error

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
    fn, createImmutVal(internalName, null()), internal = true, ownerStmt = some(stmt)
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

proc generateIRForScope*(runtime: Runtime, scope: Scope)

proc generateIR*(
    runtime: Runtime,
    fn: Function,
    stmt: Statement,
    internal: bool = false,
    ownerStmt: Option[Statement] = none(Statement),
    exprStoreIn: Option[string] = none(string),
    parentStmt: Option[Statement] = none(Statement),
    index: Option[uint] = none(uint)
) =
  case stmt.kind
  of CreateImmutVal:
    debug "emitter: generate IR for creating immutable value with identifier: " &
      stmt.imIdentifier
    
    let idx = runtime.loadIRAtom(stmt.imAtom)

    if not internal:
      if fn.name == "outer":
        debug "emitter: marking index as global because it's in outer-most scope: " & $idx
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
        debug "emitter: marking index as global because it's in outer-most scope: " & $idx
        runtime.ir.markGlobal(idx)

      runtime.markLocal(fn, stmt.mutIdentifier, index = some(idx))
    else:
      assert *ownerStmt
      runtime.markInternal(&ownerStmt, stmt.mutIdentifier)
  of Call:
    #[if runtime.vm.hasBuiltin(stmt.fn):
      info "interpreter: generate IR for calling builtin: " & stmt.fn
      let args = (
        proc(): seq[MAtom] =
          var x: seq[MAtom]
          for arg in stmt.arguments:
            x &= uinteger runtime.index(arg.ident, defaultParams(fn))

          x
      )()

      runtime.ir.call(stmt.fn, args)
    else: ]#
    let nam = if stmt.mangle: stmt.fn.normalizeIRName() else: stmt.fn
    info "interpreter: generate IR for calling function: " & nam & (if stmt.mangle: " (mangled)" else: newString 0)
    runtime.expand(fn, stmt, internal)

    for i, arg in stmt.arguments:
      case arg.kind
      of cakIdent:
        info "interpreter: passing ident parameter to function with ident: " &
          arg.ident

        runtime.ir.passArgument(runtime.index(arg.ident, defaultParams(fn)))
      of cakAtom: # already loaded via the statement expander
        let ident = $i
        info "interpreter: passing atom parameter to function with ident: " & ident
        runtime.ir.passArgument(runtime.index(ident, internalIndex(stmt)))
      of cakFieldAccess:
        let index = runtime.resolveFieldAccess(
          fn,
          stmt,
          runtime.index(arg.access.identifier, defaultParams(fn)),
          arg.access,
        )
        runtime.ir.markGlobal(index)
        runtime.ir.passArgument(index)
      of cakImmediateExpr:
        let index = runtime.index($i, internalIndex(stmt))
        runtime.ir.markGlobal(index)
        runtime.ir.passArgument(index)

    runtime.ir.call(nam)
    runtime.ir.resetArgs()
  of ReturnFn:
    assert not (*stmt.retVal and *stmt.retIdent),
      "ReturnFn statement cannot have both return atom and return ident at once!"

    runtime.expand(fn, stmt)

    if !stmt.retIdent:
      runtime.ir.returnFn(runtime.index("retval", internalIndex(stmt)).int)
    else:
      runtime.ir.returnFn(runtime.index(&stmt.retIdent, defaultParams(fn)).int)
  of CallAndStoreResult:
    runtime.markLocal(fn, stmt.storeIdent)
    runtime.generateIR(fn, stmt.storeFn)

    let index = runtime.index(stmt.storeIdent, defaultParams(fn))
    debug "emitter: call-and-store result will be stored in ident \"" & stmt.storeIdent &
      "\" or index " & $index
    runtime.ir.loadObject(index) # load `undefined` on that index
    runtime.ir.readRegister(index, Register.ReturnValue)
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
    assert off
    let index = runtime.index(stmt.reIdentifier, defaultParams(fn))
    if runtime.verifyNotOccupied(stmt.reIdentifier, fn):
      runtime.semanticError(immutableReassignmentAttempt(stmt))
      return

    info "emitter: reassign value at index " & $index & " with ident \"" &
      stmt.reIdentifier & "\" to " & stmt.reAtom.crush()

    case stmt.reAtom.kind
    of Integer:
      runtime.ir.loadInt(index, stmt.reAtom)
    of UnsignedInt:
      runtime.ir.loadUint(index, &stmt.reAtom.getUint())
    of String:
      discard runtime.ir.loadStr(index, stmt.reAtom)
    of Float:
      discard runtime.ir.addOp(
        IROperation(opcode: LoadFloat, arguments: @[uinteger index, stmt.reAtom])
      ) # FIXME: mirage: loadFloat isn't implemented
    else:
      unreachable

    runtime.ir.markGlobal(index)
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
    of BinaryOperation.Equal:
      runtime.ir.equate(leftIdx, rightIdx)
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
      runtime.ir.overrideArgs(equalJmp, @[uinteger(equalBranch)])
      runtime.ir.jump(equalBranch + 3)

      # left != right branch
      let unequalBranch =
        if leftTerm.kind == AtomHolder:
          runtime.ir.loadBool(leftIdx, false)
        else:
          runtime.ir.loadBool(runtime.index(&stmt.binStoreIn, defaultParams(fn)), false)
      runtime.ir.overrideArgs(unequalJmp, @[uinteger(unequalBranch)])
    of BinaryOperation.NotEqual:
      runtime.ir.equate(leftIdx, rightIdx)
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
      runtime.ir.overrideArgs(unequalJmp, @[uinteger(unequalBranch)])
      runtime.ir.jump(unequalBranch + 3)

      # left == right branch: false
      let equalBranch =
        if leftTerm.kind == AtomHolder:
          runtime.ir.loadBool(leftIdx, false)
        else:
          runtime.ir.loadBool(runtime.index(&stmt.binStoreIn, defaultParams(fn)), false)
      runtime.ir.overrideArgs(equalJmp, @[uinteger(equalBranch)])
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
    of Equal, NotEqual:
      runtime.ir.equate(lhsIdx, rhsIdx)
    of GreaterThan, LesserThan:
      discard runtime.ir.addOp(
        IROperation(
          opcode: GreaterThanInt, arguments: @[uinteger lhsIdx, uinteger rhsIdx]
        ) # FIXME: mirage doesn't have a nicer IR function for this.
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

    runtime.generateIRForScope(stmt.branchTrue) # generate branch one
    let skipBranchTwoJmp = runtime.ir.addOp(IROperation(opcode: Jump)) - 1
      # jump beyond branch two, don't accidentally execute it
    let endOfBranchOne = getCurrOpNum().uint

    runtime.generateIRForScope(stmt.branchFalse) # generate branch two
    let endOfBranchTwo = getCurrOpNum().uint
    runtime.ir.overrideArgs(skipBranchTwoJmp, @[uinteger(endOfBranchTwo)])

    case stmt.conditionExpr.op
    of Equal, GreaterThan:
      runtime.ir.overrideArgs(falseJump, @[uinteger(endOfBranchOne)])
      runtime.ir.overrideArgs(trueJump, @[uinteger(falseJump + 2)])
    of NotEqual, LesserThan:
      runtime.ir.overrideArgs(trueJump, @[uinteger(getCurrOpNum().uint)])
      runtime.ir.overrideArgs(falseJump, @[uinteger(falseJump + 2)])
    else:
      unreachable
  of CopyValMut:
    debug "emitter: generate IR for copying value to a mutable address with source: " &
      stmt.cpMutSourceIdent & " and destination: " & stmt.cpMutDestIdent
    runtime.generateIR(fn, createMutVal(stmt.cpMutDestIdent, null()), internal = false)
    let dest = runtime.addrIdx - 1

    runtime.ir.copyAtom(runtime.index(stmt.cpMutSourceIdent, defaultParams(fn)), dest)
  of CopyValImmut:
    debug "emitter: generate IR for copying value to an immutable address with source: " &
      stmt.cpImmutSourceIdent & " and destination: " & stmt.cpImmutDestIdent
    runtime.generateIR(
      fn, createMutVal(stmt.cpImmutDestIdent, null()), internal = false
    )
    let dest = runtime.addrIdx - 1

    runtime.ir.copyAtom(runtime.index(stmt.cpImmutSourceIdent, defaultParams(fn)), dest)
  of WhileStmt:
    debug "emitter: generate IR for while loop"
    when not defined(baliEmitterDontElideLoops):
      if stmt.whStmtOnlyMutatesItsState(stmt.whBranch.getValueCaptures()):
        debug "emitter: while loop only mutates its own state - eliding it away"
        if runtime.optimizeAwayStateMutatorLoop(fn, stmt):
          return  # we can fully skip creating all of the expensive comparison checks! :D
        else:
          warn "emitter: failed to elide state mutator loop :("

    runtime.expand(fn, stmt)

    proc getCurrOpNum(): int =
      for module in runtime.ir.modules:
        if module.name == runtime.ir.currModule:
          return module.operations.len + 1

      unreachable
      0
    
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

    let jmpIntoComparison = getCurrOpNum()
    case stmt.whConditionExpr.op
    of Equal, NotEqual:
      runtime.ir.equate(lhsIdx, rhsIdx)
    of GreaterThan, LesserThan:
      discard runtime.ir.addOp(
        IROperation(
          opcode: GreaterThanInt, arguments: @[uinteger lhsIdx, uinteger rhsIdx]
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

    runtime.generateIRForScope(stmt.whBranch) # generate the body of the loop
    runtime.ir.jump(jmpIntoComparison.uint) # jump back to the comparison logic

    let jmpPastBody = getCurrOpNum()

    if runtime.irHints.breaksGeneratedAt.len > 0:
      for brk in runtime.irHints.breaksGeneratedAt:
        runtime.ir.overrideArgs(brk, @[uinteger(jmpPastBody.uint)])
    else:
      runtime.ir.overrideArgs(dummyJump, @[uinteger(jmpPastBody.uint)])

    runtime.irHints.breaksGeneratedAt.reset()

    case stmt.whConditionExpr.op
    of BinaryOperation.Equal, BinaryOperation.GreaterThan:
      runtime.ir.overrideArgs(trueJump, @[uinteger(jmpIntoBody.uint)])
      runtime.ir.overrideArgs(escapeJump, @[uinteger(jmpPastBody.uint)])
    of BinaryOperation.NotEqual, BinaryOperation.LesserThan:
      runtime.ir.overrideArgs(trueJump, @[uinteger(jmpPastBody.uint)])
      runtime.ir.overrideArgs(escapeJump, @[uinteger(jmpIntoBody.uint)])
    else:
      unreachable
  of Increment:
    runtime.ir.incrementInt(runtime.index(stmt.incIdent, defaultParams(fn)))
  of Decrement:
    runtime.ir.decrementInt(runtime.index(stmt.decIdent, defaultParams(fn)))
  of Break:
    runtime.irHints.breaksGeneratedAt &= runtime.ir.addOp(IROperation(opcode: Jump)) - 1
  of Waste:
    let idx = runtime.loadIRAtom(stmt.wstAtom)
    if runtime.opts.repl:
      runtime.ir.passArgument(idx)
      runtime.ir.call(normalizeIRName "console.log")
  of AccessArrayIndex:
    let atomIdx = runtime.index(stmt.arrAccIdent, defaultParams(fn))
    let fieldIndex = runtime.loadIRAtom(stmt.arrAccIndex)
    
    runtime.ir.passArgument(atomIdx)
    runtime.ir.passArgument(fieldIndex)
    runtime.ir.call("BALI_INDEX")
    runtime.ir.resetArgs()
  else:
    warn "emitter: unimplemented IR generation directive: " & $stmt.kind

proc loadArgumentsOntoStack*(runtime: Runtime, fn: Function) =
  info "emitter: loading up function signature arguments onto stack via IR: " & fn.name

  for i, arg in fn.arguments:
    runtime.markLocal(fn, arg)
    runtime.ir.readRegister(
      runtime.index(arg, defaultParams(fn)), Register.CallArgument
    )
    runtime.ir.resetArgs() # reset the call param register

proc generateIRForScope*(runtime: Runtime, scope: Scope) =
  let
    fn =
      try:
        Function(scope)
      except ObjectConversionDefect:
        Function(
          name: "outer",
          arguments: newSeq[string](0),
          prev: scope.prev,
          next: scope.next,
          stmts: scope.stmts,
        ) # FIXME: discriminate between scopes
    name = fn.name

  debug "generateIRForScope(): function name: " & name
  if not runtime.clauses.contains(name):
    runtime.clauses.add(name)
    runtime.ir.newModule(name.normalizeIRName())

  if name != "outer":
    runtime.loadArgumentsOntoStack(fn)
  else:
    constants.generateStdIr(runtime)
    inc runtime.addrIdx

    for i, typ in runtime.types:
      let idx = runtime.addrIdx
      runtime.markGlobal(typ.name)
      runtime.ir.loadObject(idx)
      runtime.types[i].singletonId = idx

  for i, stmt in scope.stmts:
    runtime.generateIR(fn, stmt, index = i.uint.some)

  var curr = scope
  while *curr.next:
    curr = &curr.next
    runtime.generateIRForScope(curr)

proc findField*(atom: MAtom, accesses: FieldAccess): MAtom =
  if accesses.identifier in atom.objFields:
    if accesses.next == nil:
      return atom.objValues[atom.objFields[accesses.identifier]]
    else:
      return atom.findField(accesses.next)
  else:
    return undefined()

proc computeTypeof*(runtime: Runtime, atom: MAtom): string =
  case atom.kind
  of String:
    return "string"
  of Integer, Float, UnsignedInt:
    return "number"
  of Null, Object, Sequence:
    return "object"
  of Boolean:
    return "boolean"
  else: unreachable

proc generateInternalIR*(runtime: Runtime) =
  runtime.ir.newModule("BALI_RESOLVEFIELD")
  runtime.vm.registerBuiltin(
    "BALI_RESOLVEFIELD_INTERNAL",
    proc(op: Operation) =
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
      let atom = runtime.argument(1)
      assert(*atom, "BUG: Atom was empty when calling BALI_TYPEOF_INTERNAL!")
      ret runtime.computeTypeof(&atom)
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
      assert((&atom).kind == Sequence, "BUG: BALI_INDEX_INTERNAL was passed a non-seq.")
      
      let idx = &(&index).getInt()
      let vec = (&atom).sequence
      if idx < 0 or idx > vec.len - 1:
        ret undefined()

      ret vec[idx] # TODO: add indexing for tables/object fields
  )
  runtime.ir.call("BALI_INDEX_INTERNAL")

proc run*(runtime: Runtime) =
  runtime.test262 = runtime.ast.test262
  console.generateStdIR(runtime)
  math.generateStdIR(runtime)
  uri.generateStdIR(runtime)
  errors_ir.generateStdIR(runtime)
  base64.generateStdIR(runtime)
  json.generateStdIR(runtime)
  encodeUri.generateStdIR(runtime)
  
  if runtime.opts.experiments.dateRoutines:
    date.generateStdIR(runtime)

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
    runtime.syntaxError(error, if runtime.opts.test262: 0 else: 1)

  if runtime.ast.doNotEvaluate and runtime.opts.test262:
    debug "runtime: `doNotEvaluate` is set to `true` in Test262 mode - skipping execution."
    quit(0)
  debug "interpreter: passing over execution to VM - here goes nothing!"
  runtime.vm.run()

proc newRuntime*(
    file: string, ast: AST, opts: InterpreterOpts = default(InterpreterOpts)
): Runtime {.inline.} =
  Runtime(
    ast: ast,
    clauses: @[],
    ir: newIRGenerator("bali-" & $sha256(file).toHex()),
    vm: newPulsarInterpreter(""),
    opts: opts,
  )

export types
