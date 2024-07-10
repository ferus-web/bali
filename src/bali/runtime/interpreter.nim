## Bali runtime (MIR emitter)
##
## Copyright (C) 2024 Trayambak Rai and Ferus Authors
import std/[logging, sugar, tables, importutils]
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
    clauses: seq[string]

proc index*(runtime: Runtime, name: string): uint =
  if name in runtime.nameToIdx:
    return runtime.nameToIdx[name]
  else:
    raise newException(CatchableError, "No such ident: " & name) # FIXME: turn into semantic error

proc mark*(runtime: Runtime, name: string) =
  runtime.nameToIdx[name] = runtime.addrIdx

proc generateIR*(runtime: Runtime, stmt: Statement) =
  case stmt.kind
  of CreateImmutVal:
    inc runtime.addrIdx
    mark runtime, stmt.imIdentifier
    info "interpreter: generate IR for creating immutable value"

    case stmt.imAtom.kind
    of Integer:
      info "interpreter: generate IR for loading immutable integer"
      runtime.ir.loadInt(
        runtime.addrIdx,
        stmt.imAtom
      )
    of String:
      info "interpreter: generate IR for loading immutable string"
      discard runtime.ir.loadStr(
        runtime.addrIdx,
        stmt.imAtom
      ) # FIXME: mirage: loadStr doesn't have the discardable pragma
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
          runtime.ir.passArgument(runtime.index(arg.ident))
        of cakAtom:
          for child in stmt.expand():
            runtime.generateIR(
              child
            )

      runtime.ir.call(nam)
      #runtime.ir.resetArgs()
      discard runtime.ir.addOp IROperation(opcode: CrashInterpreter)
  else:
    warn "interpreter: unimplemented IR generation directive: " & $stmt.kind

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
  
  for stmt in scope.stmts:
    for child in stmt.expand():
      runtime.generateIR(child)
    
    runtime.generateIR(stmt)

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

  runtime.generateIRForScope(runtime.ast.scopes[0])

  let source = runtime.ir.emit()
  echo source
  
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
