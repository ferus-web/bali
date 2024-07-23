## Bali runtime (MIR emitter)
##
## Copyright (C) 2024 Trayambak Rai and Ferus Authors
import std/[options, logging, sugar, tables, importutils]
import mirage/ir/generator
import mirage/runtime/tokenizer
import mirage/runtime/prelude
import bali/grammar/prelude
import bali/internal/sugar
import bali/runtime/[normalize]
import bali/stdlib/prelude
import crunchy, pretty

type
  Runtime* = ref object
    ast: AST
    ir: IRGenerator
    vm*: PulsarInterpreter

    addrIdx: uint
    nameToIdx: Table[string, uint]
    locals: Table[uint, string]
    clauses: seq[string]

proc index*(runtime: Runtime, name: string): uint =
  debug "interpreter: find index of ident: " & name
  if name in runtime.nameToIdx:
    return runtime.nameToIdx[name]
  else:
    raise newException(CatchableError, "No such ident: " & name) # FIXME: turn into semantic error

proc localTo*(runtime: Runtime, name: string): Option[string] =
  let idx = runtime.index(name)

  if idx in runtime.locals:
    return some runtime.locals[idx]

proc markInternal*(runtime: Runtime, name: string) =
  inc runtime.addrIdx
  debug "interpreter: mark ident '" & name & "' to index " & $runtime.addrIdx
  runtime.nameToIdx['@' & name] = runtime.addrIdx

proc indexInternal*(runtime: Runtime, name: string): uint =
  let nameInt = '@' & name
  debug "interpreter: find index of internal value: " & nameInt

  if nameInt in runtime.nameToIdx:
    return runtime.nameToIdx[nameInt]
  else:
    raise newException(CatchableError, "No such internal ident: " & name)

proc mark*(runtime: Runtime, name: string) =
  inc runtime.addrIdx
  runtime.nameToIdx[name] = runtime.addrIdx

proc generateIR*(runtime: Runtime, fn: Function, stmt: Statement) =
  case stmt.kind
  of CreateImmutVal:
    mark runtime, stmt.imIdentifier
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
  of CreateMutVal:
    inc runtime.addrIdx
    mark runtime, stmt.mutIdentifier
    runtime.ir.loadInt(
      runtime.addrIdx,
      stmt.mutAtom
    )
  of Call:
    if runtime.vm.hasBuiltin(stmt.fn):
      info "interpreter: generate IR for calling builtin: " & stmt.fn
      let args =
        (proc(): seq[MAtom] =
          var x: seq[MAtom]
          for arg in stmt.arguments:
            x &= uinteger runtime.index(arg.ident)

          x
        )()

      runtime.ir.call(
        stmt.fn, args
      )
    else:
      let nam = stmt.fn.normalizeIRName()
      info "interpreter: generate IR for calling function (normalized): " & nam
      
      for i, arg in stmt.arguments:
        case arg.kind
        of cakIdent:
          let ident = arg.ident
          info "interpreter: passing ident parameter to function with ident: " & ident
          runtime.ir.passArgument(runtime.index($hash(fn) & "funcall_arg_" & ident))
        of cakAtom: # already loaded via the statement expander
          let ident = $hash(stmt) & '_' & $i
          info "interpreter: passing atom parameter to function with ident: " & ident
          runtime.ir.passArgument(runtime.indexInternal(ident))

      runtime.ir.call(nam)
      runtime.ir.resetArgs()
  of ReturnFn:
    assert not (*stmt.retVal and *stmt.retIdent), "ReturnFn statement cannot have both return atom and return ident at once!"
    
    if *stmt.retVal:
      let name = $hash(fn) & "_retval"
      runtime.generateIR(fn, createImmutVal(name, &stmt.retVal))
      runtime.ir.returnFn(runtime.index(name).int)
    elif *stmt.retIdent:
      runtime.ir.returnFn(runtime.index('@' & $hash(fn) & '_' & &stmt.retIdent).int)
    else:
      let name = $hash(fn) & "_retval"
      runtime.generateIR(fn, createImmutVal(name, null())) # load NULL atom
      runtime.ir.returnFn(runtime.index(name).int)
  of CallAndStoreResult:
    let ident = $hash(fn) & "funcall_arg_" & stmt.storeIdent
    mark runtime, ident
    runtime.generateIR(fn, stmt.storeFn)
    runtime.ir.readRegister(runtime.index(ident), Register.ReturnValue)
  else:
    warn "interpreter: unimplemented IR generation directive: " & $stmt.kind

proc loadArgumentsOntoStack*(runtime: Runtime, fn: Function) =
  info "interpreter: loading up function signature arguments onto stack via IR: " & fn.name

  for i, arg in fn.arguments:
    let name = '@' & $hash(fn) & '_' & arg
    debug name
    mark runtime, name
    runtime.ir.readRegister(runtime.index name, Register.CallArgument)
    runtime.ir.resetArgs() # reset the call param register

proc generateIRForScope*(runtime: Runtime, scope: Scope) =
  let 
    fn = cast[Function](scope)
    name = if fn.name.len > 0:
      fn.name
    else:
      "outer"

  if not runtime.clauses.contains(name):
    runtime.clauses.add(name)
    runtime.ir.newModule(name.normalizeIRName())
  
  if name != "outer":
    runtime.loadArgumentsOntoStack(fn)
  
  for stmt in scope.stmts:
    for child in stmt.expand():
      runtime.generateIR(fn, child)
    
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
  console.generateStdIr(runtime.vm, runtime.ir)
  math.generateStdIR(runtime.vm, runtime.ir)

  runtime.generateIRForScope(runtime.ast.scopes[0])

  let source = runtime.ir.emit()
  
  privateAccess(PulsarInterpreter) # modern problems require modern solutions
  runtime.vm.tokenizer = tokenizer.newTokenizer(source) 

  info "interpreter: begin VM analyzer"
  runtime.vm.analyze()

  info "interpreter: setting entry point to `outer`"
  runtime.vm.setEntryPoint("outer")

  info "interpreter: passing over execution to VM"
  runtime.vm.run()

proc newRuntime*(file: string, ast: AST): Runtime {.inline.} =
  Runtime(
    ast: ast,
    ir: newIRGenerator(
      "bali-" & $sha256(file).toHex()
    ),
    vm: newPulsarInterpreter("")
  )
