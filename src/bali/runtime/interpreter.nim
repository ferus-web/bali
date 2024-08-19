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

  Runtime* = ref object
    ast: AST
    ir: IRGenerator
    vm*: PulsarInterpreter

    addrIdx: uint
    values*: seq[Value]
    clauses: seq[string]

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

proc indexGlobal*(runtime: Runtime, ident: string): Option[uint] =
  for value in runtime.values:
    if value.kind != vkGlobal: continue
    if value.identifier == ident:
      return some(value.index)

proc indexInternal*(runtime: Runtime, stmt: Statement, ident: string): Option[uint] =
  for value in runtime.values:
    if value.kind != vkInternal: continue
    if value.identifier == ident and
      value.ownerStmt == hash(stmt):
      return some(value.index)

proc indexLocal*(runtime: Runtime, fn: Function, ident: string): Option[uint] =
  for value in runtime.values:
    if value.kind != vkLocal: continue
    if value.identifier == ident and
      value.ownerFunc == hash(fn):
      return some(value.index)

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
      
      if value.kind == vkInternal and cond:
        echo value.identifier

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
  else: discard 

proc generateIR*(runtime: Runtime, fn: Function, stmt: Statement, internal: bool = false, ownerStmt: Option[Statement] = none(Statement)) =
  case stmt.kind
  of CreateImmutVal:
    info "interpreter: generate IR for creating immutable value with identifier: " & stmt.imIdentifier

    case stmt.imAtom.kind
    of Integer:
      info "interpreter: generate IR for loading immutable integer"
      runtime.ir.loadInt(
        runtime.addrIdx,
        stmt.imAtom
      )
    of UnsignedInt:
      info "interpreter: generate IR for loading immutable unsigned integer"
      runtime.ir.loadInt(
        runtime.addrIdx,
        integer int(&stmt.imAtom.getUint()) # FIXME: make all mirage integer ops work on unsigned integers whenever possible too.
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
    else: unreachable
    
    if not internal:
      runtime.markLocal(fn, stmt.imIdentifier)
    else:
      assert *ownerStmt
      runtime.markInternal(&ownerStmt, stmt.imIdentifier)
  of CreateMutVal:
    runtime.ir.loadInt(
      runtime.addrIdx,
      stmt.mutAtom
    )
    runtime.markLocal(fn, stmt.imIdentifier)
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
    runtime.ir.readRegister(runtime.index(stmt.storeIdent, defaultParams(fn)), Register.ReturnValue)
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

    runtime.ir.call("BALI_CONSTRUCTOR_" & stmt.objName.toUpperAscii())
  else:
    warn "interpreter: unimplemented IR generation directive: " & $stmt.kind

proc loadArgumentsOntoStack*(runtime: Runtime, fn: Function) =
  info "interpreter: loading up function signature arguments onto stack via IR: " & fn.name

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

  #[for scope in runtime.ast:
    let fn = cast[Function](scope)
    if not clauses.contains(fn.name):
      clauses.add(fn.name)
      runtime.ir.newModule(fn.name)

    for stmt in scope.stmts:
      for child in stmt.expand():
        runtime.generateIR(child, addrIdx)

      runtime.generateIR(stmt, addrIdx)]#

proc run*(runtime: Runtime) =
  console.generateStdIR(runtime.vm, runtime.ir)
  math.generateStdIR(runtime.vm, runtime.ir)
  uri.generateStdIR(runtime.vm, runtime.ir)

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

proc newRuntime*(file: string, ast: AST): Runtime {.inline.} =
  Runtime(
    ast: ast,
    clauses: @[],
    ir: newIRGenerator(
      "bali-" & $sha256(file).toHex()
    ),
    vm: newPulsarInterpreter("")
  )
