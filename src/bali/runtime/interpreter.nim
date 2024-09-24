## Bali runtime (MIR emitter)
##
## Copyright (C) 2024 Trayambak Rai and Ferus Authors
import std/[options, hashes, logging, sugar, strutils, tables, importutils]
import mirage/ir/generator
import mirage/runtime/[tokenizer, prelude]
import bali/grammar/prelude
import bali/internal/sugar
import bali/runtime/[normalize]
import bali/stdlib/prelude
import crunchy, pretty

type
  ValueKind* = enum
    vkGlobal
    vkLocal
    vkInternal ## or immediate

  IndexParams* = object
    priorities*: seq[ValueKind] = @[vkLocal, vkGlobal]

    fn*: Option[Function]
    stmt*: Option[Statement]

  Value* = object
    index*: uint
    identifier*: string
    case kind*: ValueKind
    of vkLocal:
      ownerFunc*: Hash
    of vkInternal:
      ownerStmt*: Hash
    else: discard

  SemanticErrorKind* = enum
    UnknownIdentifier
    ImmutableReassignment

  SemanticError* = object
    line*, col*: uint
    case kind*: SemanticErrorKind
    of UnknownIdentifier:
      unknown*: string
    of ImmutableReassignment:
      imIdent*: string
      imNewValue*: MAtom
  
  InterpreterOpts* = object
    test262*: bool = false

  Runtime* = ref object
    ast: AST
    ir: IRGenerator
    vm*: PulsarInterpreter
    opts*: InterpreterOpts

    addrIdx: uint
    values*: seq[Value]
    semanticErrors*: seq[SemanticError]
    clauses: seq[string]

proc unknownIdentifier*(identifier: string): SemanticError {.inline.} =
  SemanticError(kind: UnknownIdentifier, unknown: identifier)

proc immutableReassignmentAttempt*(stmt: Statement): SemanticError {.inline.} =
  SemanticError(kind: ImmutableReassignment, imIdent: stmt.reIdentifier, imNewValue: stmt.reAtom, line: stmt.line, col: stmt.col)

proc defaultParams*(fn: Function): IndexParams {.inline.} =
  IndexParams(
    fn: some fn
  )

proc internalIndex*(stmt: Statement): IndexParams {.inline.} =
  IndexParams(priorities: @[vkInternal], stmt: some stmt)

proc markInternal*(runtime: Runtime, stmt: Statement, ident: string) =
  runtime.values &=
    Value(
      kind: vkInternal,
      index: runtime.addrIdx,
      identifier: ident,
      ownerStmt: hash(stmt)
    )

  info "Ident \"" & ident & "\" is being internally marked at index " & $runtime.addrIdx & " with statement hash: " & $hash(stmt)

  inc runtime.addrIdx

proc markGlobal*(runtime: Runtime, ident: string) =
  runtime.values &=
    Value(
      kind: vkGlobal,
      index: runtime.addrIdx,
      identifier: ident
    )

  info "Ident \"" & ident & "\" is being globally marked at index " & $runtime.addrIdx

  inc runtime.addrIdx

proc markLocal*(runtime: Runtime, fn: Function, ident: string) =
  runtime.values &=
    Value(
      kind: vkLocal,
      index: runtime.addrIdx,
      identifier: ident,
      ownerFunc: hash(fn)
    )

  info "Ident \"" & ident & "\" is being locally marked at index " & $runtime.addrIdx

  inc runtime.addrIdx

proc index*(runtime: Runtime, ident: string, params: IndexParams): uint =
  for value in runtime.values:
    for prio in params.priorities:
      if value.kind != prio: continue

      let cond = case value.kind
      of vkGlobal:
        value.identifier == ident
      of vkLocal:
        assert *params.fn
        value.identifier == ident and value.ownerFunc == hash(&params.fn)
      of vkInternal:
        assert *params.stmt
        value.identifier == ident and value.ownerStmt == hash(&params.stmt)
      
      if cond:
        return value.index
  
  raise newException(ValueError, "No such ident: " & ident)

proc generateIR*(runtime: Runtime, fn: Function, stmt: Statement, internal: bool = false, ownerStmt: Option[Statement] = none(Statement))

proc expand*(runtime: Runtime, fn: Function, stmt: Statement) =
  case stmt.kind
  of Call:
    debug "ir: expand Call statement"
    for i, arg in stmt.arguments:
      if arg.kind == cakAtom:
        debug "ir: load immutable value to expand Call's immediate arguments: " & arg.atom.crush("")
        runtime.generateIR(fn, createImmutVal(
          $i,
          arg.atom
        ), ownerStmt = some(stmt), internal = true) # XXX: should this be mutable?
  of ConstructObject:
    debug "ir: expand ConstructObject statement"
    for i, arg in stmt.args:
      if arg.kind == cakAtom:
        debug "ir: load immutable value to ConstructObject's immediate arguments: " & arg.atom.crush("")
        runtime.generateIR(fn, createImmutVal(
          $i,
          arg.atom
        ), ownerStmt = some(stmt), internal = true) # XXX: should this be mutable?
  of CallAndStoreResult:
    debug "ir: expand CallAndStoreResult statement by expanding child Call statement"
    runtime.expand(fn, stmt.storeFn)
  of ThrowError:
    debug "ir: expand ThrowError"

    if *stmt.error.str:
      runtime.generateIR(fn, createImmutVal("error_msg", str(&stmt.error.str)), ownerStmt = some(stmt), internal = true)
  of BinaryOp:
    debug "ir: expand BinaryOp"

    if *stmt.binStoreIn:
      debug "ir: BinaryOp evaluation will be stored in: " & &stmt.binStoreIn & " (" & $runtime.addrIdx & ')'
      runtime.ir.loadInt(runtime.addrIdx, 0)
      runtime.markLocal(fn, &stmt.binStoreIn)

    if stmt.binLeft.kind == AtomHolder:
      debug "ir: BinaryOp left term is an atom"
      runtime.generateIR(fn, createImmutVal("left_term", stmt.binLeft.atom), ownerStmt = some(stmt), internal = true)
    #else:
    #  debug "ir: BinaryOp left term is an ident, reserving new index for result"
    #  runtime.generateIR(fn, createImmutVal("store_in", null()), ownerStmt = some(stmt), internal = true)

    if stmt.binRight.kind == AtomHolder:
      debug "ir: BinaryOp right term is an atom"
      runtime.generateIR(fn, createImmutVal("right_term", stmt.binRight.atom), ownerStmt = some(stmt), internal = true)
    elif stmt.binRight.kind == IdentHolder:
      debug "ir: BinaryOp right term is an ident"
  else: discard 

proc verifyNotOccupied*(runtime: Runtime, ident: string, fn: Function): bool =
  var prev = fn.prev

  while *prev:
    let parked = try:
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

proc resolveFieldAccess*(runtime: Runtime, fn: Function, stmt: Statement, address: int, field: string): uint =
  let internalName = $(hash(stmt) !& hash(ident) !& hash(field))
  runtime.generateIR(fn, createImmutVal(internalName, null()), internal = true, ownerStmt = some(stmt))
  let accessResult = runtime.addrIdx - 1

  # start preparing for call to internal field resolver
  inc runtime.addrIdx
  runtime.ir.loadUint(runtime.addrIdx, accessResult)
  inc runtime.addrIdx
  runtime.ir.loadInt(runtime.addrIdx, address)
  inc runtime.addrIdx
  runtime.ir.loadStr(runtime.addrIdx, field)
  inc runtime.addrIdx

  runtime.ir.passArgument(runtime.addrIdx - 3)     # pass `accessResult`
  runtime.ir.passArgument(runtime.addrIdx - 2)     # pass `address`
  runtime.ir.passArgument(runtime.addrIdx - 1)     # pass `field`

  runtime.ir.call("BALI_RESOLVEFIELD")
  runtime.ir.resetArgs()

  accessResult

proc generateIR*(runtime: Runtime, fn: Function, stmt: Statement, internal: bool = false, ownerStmt: Option[Statement] = none(Statement)) =
  case stmt.kind
  of CreateImmutVal:
    info "emitter: generate IR for creating immutable value with identifier: " & stmt.imIdentifier

    case stmt.imAtom.kind
    of Integer:
      info "interpreter: generate IR for loading immutable integer"
      runtime.ir.loadInt(
        runtime.addrIdx,
        stmt.imAtom
      )
    of UnsignedInt:
      info "interpreter: generate IR for loading immutable unsigned integer"
      runtime.ir.loadUint(
        runtime.addrIdx,
        &stmt.imAtom.getUint() # FIXME: make all mirage integer ops work on unsigned integers whenever possible too.
      )
    of String:
      info "interpreter: generate IR for loading immutable string"
      discard runtime.ir.loadStr(
        runtime.addrIdx,
        stmt.imAtom
      ) # FIXME: mirage: loadStr doesn't have the discardable pragma
    of Float:
      info "interpreter: generate IR for loading immutable float"
      discard runtime.ir.addOp(
        IROperation(opcode: LoadFloat, arguments: @[uinteger runtime.addrIdx, stmt.imAtom])
      ) # FIXME: mirage: loadFloat isn't implemented
    of Boolean:
      info "emitter: generate IR for loading immutable boolean"
      runtime.ir.loadBool(runtime.addrIdx, stmt.imAtom)
    of Null:
      info "emitter: generate IR for loading immutable null"
      runtime.ir.loadNull(runtime.addrIdx)
    else: print stmt.imAtom; unreachable
    
    if not internal:
      if fn.name.len < 1:
        runtime.ir.markGlobal(runtime.addrIdx)

      runtime.markLocal(fn, stmt.imIdentifier)
    else:
      assert *ownerStmt
      runtime.markInternal(&ownerStmt, stmt.imIdentifier)
  of CreateMutVal:
    case stmt.mutAtom.kind
    of Integer:
      info "emitter: generate IR for loading mutable integer"
      runtime.ir.loadInt(
        runtime.addrIdx,
        stmt.mutAtom
      )
    of UnsignedInt:
      info "emitter: generate IR for loading mutable unsigned integer"
      runtime.ir.loadUint(
        runtime.addrIdx,
        &stmt.mutAtom.getUint()
      )
    of String:
      info "emitter: generate IR for loading mutable string"
      discard runtime.ir.loadStr(
        runtime.addrIdx,
        stmt.mutAtom
      )
    of Float:
      info "emitter: generate IR for loading mutable float"
      discard runtime.ir.addOp(
        IROperation(opcode: LoadFloat, arguments: @[uinteger runtime.addrIdx, stmt.mutAtom])
      ) # FIXME: mirage: loadFloat isn't implemented
    else: unreachable
    
    if fn.name.len < 1:
      runtime.ir.markGlobal(runtime.addrIdx)
    runtime.markLocal(fn, stmt.mutIdentifier)
  of Call:
    if runtime.vm.hasBuiltin(stmt.fn):
      info "interpreter: generate IR for calling builtin: " & stmt.fn
      let args =
        (proc(): seq[MAtom] =
          var x: seq[MAtom]
          for arg in stmt.arguments:
            x &= uinteger runtime.index(arg.ident, defaultParams(fn))

          x
        )()

      runtime.ir.call(
        stmt.fn, args
      )
    else:
      let nam = stmt.fn.normalizeIRName()
      info "interpreter: generate IR for calling function (normalized): " & nam
      runtime.expand(fn, stmt)
      
      for i, arg in stmt.arguments:
        case arg.kind
        of cakIdent:
          info "interpreter: passing ident parameter to function with ident: " & arg.ident
          
          runtime.ir.passArgument(runtime.index(arg.ident, defaultParams(fn)))
        of cakAtom: # already loaded via the statement expander
          let ident = $i
          info "interpreter: passing atom parameter to function with ident: " & ident
          runtime.ir.passArgument(runtime.index(ident, internalIndex(stmt)))
        of cakFieldAccess:
          let index = runtime.resolveFieldAccess(fn, stmt, int runtime.index(arg.fIdent, defaultParams(fn)), arg.fField)
          runtime.ir.markGlobal(index)
          runtime.ir.passArgument(index)

      runtime.ir.call(nam)
      runtime.ir.resetArgs()
  of ReturnFn:
    assert not (*stmt.retVal and *stmt.retIdent), "ReturnFn statement cannot have both return atom and return ident at once!"
    
    if *stmt.retVal:
      let name = $hash(fn) & "_retval"
      runtime.generateIR(fn, createImmutVal(name, &stmt.retVal))
      runtime.ir.returnFn(runtime.index(name, defaultParams(fn)).int)
    elif *stmt.retIdent:
      runtime.ir.returnFn(runtime.index(&stmt.retIdent, defaultParams(fn)).int)
    else:
      let name = $hash(fn) & "_retval"
      runtime.generateIR(fn, createImmutVal(name, null())) # load NULL atom
      runtime.ir.returnFn(runtime.index(name, defaultParams(fn)).int)
  of CallAndStoreResult:
    runtime.markLocal(fn, stmt.storeIdent)
    runtime.generateIR(fn, stmt.storeFn)

    let index = runtime.index(stmt.storeIdent, defaultParams(fn))
    debug "emitter: call-and-store result will be stored in ident \"" & stmt.storeIdent & "\" or index " & $index
    runtime.ir.readRegister(index, Register.ReturnValue)
  of ConstructObject:
    for i, arg in stmt.args:
      case arg.kind
      of cakIdent:
        let ident = arg.ident
        info "interpreter: passing ident parameter to function with ident: " & ident
        runtime.ir.passArgument(runtime.index(ident, defaultParams(fn)))
      of cakAtom: # already loaded via the statement expander
        let ident = $hash(stmt) & '_' & $i
        info "interpreter: passing atom parameter to function with ident: " & ident
        runtime.ir.passArgument(runtime.index(ident, defaultParams(fn)))
      of cakFieldAccess:
        let index = runtime.resolveFieldAccess(fn, stmt, int runtime.index(arg.fIdent, defaultParams(fn)), arg.fField)
        runtime.ir.markGlobal(index)
        runtime.ir.passArgument(index)

    runtime.ir.call("BALI_CONSTRUCTOR_" & stmt.objName.toUpperAscii())
  of ReassignVal:
    let index = runtime.index(stmt.reIdentifier, defaultParams(fn))
    if runtime.verifyNotOccupied(stmt.reIdentifier, fn):
      runtime.semanticError(immutableReassignmentAttempt(stmt))
      return

    info "emitter: reassign value at index " & $index & " with ident \"" & stmt.reIdentifier & "\" to " & stmt.reAtom.crush("")
    
    case stmt.reAtom.kind
    of Integer:
      runtime.ir.loadInt(
        index,
        stmt.reAtom
      )
    of UnsignedInt:
      runtime.ir.loadUint(
        index,
        &stmt.reAtom.getUint()
      )
    of String:
      discard runtime.ir.loadStr(
        index,
        stmt.reAtom
      )
    of Float:
      discard runtime.ir.addOp(
        IROperation(opcode: LoadFloat, arguments: @[uinteger index, stmt.reAtom])
      ) # FIXME: mirage: loadFloat isn't implemented
    else: unreachable

    runtime.ir.markGlobal(index)
  of ThrowError:
    info "emitter: add error-throw logic"

    if *stmt.error.str:
      let msg = &stmt.error.str

      info "emitter: error string that will be raised: `" & msg & '`'
      runtime.expand(fn, stmt)

      runtime.ir.passArgument(runtime.index("error_msg", internalIndex(stmt)))
      runtime.ir.call("BALI_THROWERROR")
  of BinaryOp:
    info "emitter: emitting IR for binary operation"
    runtime.expand(fn, stmt)

    let 
      leftTerm = stmt.binLeft
      rightTerm = stmt.binRight

    # TODO: recursive IR generation

    let
      leftIdx = if leftTerm.kind == AtomHolder:
        runtime.index("left_term", internalIndex(stmt))
      elif leftTerm.kind == IdentHolder:
        runtime.index(leftTerm.ident, defaultParams(fn))
      else: 0

      rightIdx = if rightTerm.kind == AtomHolder:
        runtime.index("right_term", internalIndex(stmt))
      elif rightTerm.kind == IdentHolder:
        runtime.index(rightTerm.ident, defaultParams(fn))
      else: 0
      
    case stmt.op
    of BinaryOperation.Add: runtime.ir.addInt(leftIdx, rightIdx)
    of BinaryOperation.Sub: runtime.ir.subInt(leftIdx, rightIdx)
    of BinaryOperation.Equal:
      runtime.ir.equate(leftIdx, rightIdx)
      # FIXME: really weird bug in mirage's IR generator. wtf?
      let equalJmp = runtime.ir.addOp(IROperation(opcode: Jump)) - 1 # left == right branch
      let unequalJmp = runtime.ir.addOp(IROperation(opcode: Jump)) - 1 # left != right branch
      
      # left == right branch
      let equalBranch = if leftTerm.kind == AtomHolder:
        runtime.ir.loadBool(leftIdx, true)
      else:
        runtime.ir.loadBool(runtime.index(&stmt.binStoreIn, defaultParams(fn)), true)
      runtime.ir.overrideArgs(equalJmp, @[uinteger(equalBranch)])
      runtime.ir.jump(equalBranch + 3)

      # left != right branch
      let unequalBranch = if leftTerm.kind == AtomHolder:
        runtime.ir.loadBool(leftIdx, false)
      else:
        runtime.ir.loadBool(runtime.index(&stmt.binStoreIn, defaultParams(fn)), false)
      runtime.ir.overrideArgs(unequalJmp, @[uinteger(unequalBranch)])
    of BinaryOperation.NotEqual:
      runtime.ir.equate(leftIdx, rightIdx)
      # FIXME: really weird bug in mirage's IR generator. wtf?
      let equalJmp = runtime.ir.addOp(IROperation(opcode: Jump)) - 1 # left == right branch
      let unequalJmp = runtime.ir.addOp(IROperation(opcode: Jump)) - 1 # left != right branch
        
      # left != right branch: true
      let unequalBranch = if leftTerm.kind == AtomHolder:
        runtime.ir.loadBool(leftIdx, true)
      else:
        runtime.ir.loadBool(runtime.index(&stmt.binStoreIn, defaultParams(fn)), true)
      runtime.ir.overrideArgs(unequalJmp, @[uinteger(unequalBranch)])
      runtime.ir.jump(unequalBranch + 3)

      # left == right branch: false
      let equalBranch = if leftTerm.kind == AtomHolder:
        runtime.ir.loadBool(leftIdx, false)
      else:
        runtime.ir.loadBool(runtime.index(&stmt.binStoreIn, defaultParams(fn)), false)
      runtime.ir.overrideArgs(equalJmp, @[uinteger(equalBranch)])
    else:
      warn "emitter: unimplemented binary operation: " & $stmt.op 

    if not *stmt.binStoreIn:
      runtime.ir.moveAtom(leftIdx, runtime.index(&stmt.binStoreIn, defaultParams(fn)))
  else:
    warn "emitter: unimplemented IR generation directive: " & $stmt.kind

proc loadArgumentsOntoStack*(runtime: Runtime, fn: Function) =
  info "emitter: loading up function signature arguments onto stack via IR: " & fn.name

  for i, arg in fn.arguments:
    runtime.markLocal(fn, arg)
    runtime.ir.readRegister(runtime.index(arg, defaultParams(fn)), Register.CallArgument)
    runtime.ir.resetArgs() # reset the call param register

proc generateIRForScope*(runtime: Runtime, scope: Scope) =
  let 
    fn = cast[Function](scope)
    name = if fn.name.len > 0:
      fn.name
    else:
      "outer"
  
  debug "generateIRForScope(): function name: " & name
  if not runtime.clauses.contains(name):
    runtime.clauses.add(name)
    runtime.ir.newModule(name.normalizeIRName())
  
  if name != "outer":
    runtime.loadArgumentsOntoStack(fn)

  for stmt in scope.stmts:
    runtime.generateIR(fn, stmt)

  var curr = scope
  while *curr.next:
    curr = &curr.next
    runtime.generateIRForScope(curr)

proc generateInternalIR*(runtime: Runtime) =
  runtime.ir.newModule("BALI_RESOLVEFIELD")
  runtime.vm.registerBuiltin("BALI_RESOLVEFIELD_INTERNAL",
    proc(op: Operation) =
      let
        ident = runtime.vm.registers.callArgs.pop()
        index = uint(&getInt(runtime.vm.registers.callArgs.pop()))
        storeAt = uint(&getInt(runtime.vm.registers.callArgs.pop()))

      let atom = runtime.vm.stack[index] # FIXME: weird bug with mirage, `get` returns a NULL atom.

      if atom.kind != Object:
        debug "runtime: atom is not an object, returning null."
        runtime.vm.addAtom(obj(), storeAt)
        return

      if not atom.objFields.contains(&ident.getStr()):
        debug "runtime: atom does not have any field \"" & &ident.getStr() & "\"; returning null."
        runtime.vm.addAtom(obj(), storeAt)
        return
      
      let value = atom.objValues[atom.objFields[&ident.getStr()]]
      runtime.vm.addAtom(value, storeAt)
  )
  runtime.ir.call("BALI_RESOLVEFIELD_INTERNAL")

proc run*(runtime: Runtime) =
  if runtime.ast.doNotEvaluate and runtime.opts.test262:
    quit(0)

  console.generateStdIR(runtime.vm, runtime.ir)
  math.generateStdIR(runtime.vm, runtime.ir)
  uri.generateStdIR(runtime.vm, runtime.ir)
  errors.generateStdIR(runtime.vm, runtime.ir)
  base64.generateStdIR(runtime.vm, runtime.ir)
  parseIntGenerateStdIR(runtime.vm, runtime.ir)

  runtime.generateInternalIR()

  if runtime.opts.test262:
    test262.generateStdIR(runtime.vm, runtime.ir)

  runtime.generateIRForScope(runtime.ast.scopes[0])

  let source = runtime.ir.emit()
  
  privateAccess(PulsarInterpreter) # modern problems require modern solutions
  runtime.vm.tokenizer = tokenizer.newTokenizer(source)

  debug "interpreter: the following bytecode will now be executed"
  debug source

  info "interpreter: begin VM analyzer"
  runtime.vm.analyze()

  info "interpreter: setting entry point to `outer`"
  runtime.vm.setEntryPoint("outer")

  info "interpreter: passing over execution to VM"
  runtime.vm.run()

proc newRuntime*(file: string, ast: AST, opts: InterpreterOpts = default(InterpreterOpts)): Runtime {.inline.} =
  Runtime(
    ast: ast,
    clauses: @[],
    ir: newIRGenerator(
      "bali-" & $sha256(file).toHex()
    ),
    vm: newPulsarInterpreter(""),
    opts: opts
  )
