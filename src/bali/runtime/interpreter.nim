## Bali runtime (MIR emitter)
##
## Copyright (C) 2024 Trayambak Rai and Ferus Authors
import std/[logging, tables]
import mirage/ir/generator
import mirage/runtime/prelude
import bali/grammar/prelude
import bali/internal/sugar
import bali/runtime/[normalize]
import crunchy, pretty

type
  Runtime* = ref object
    ast: AST
    ir: IRGenerator
    vm*: PulsarInterpreter

proc generateIR*(runtime: Runtime, stmt: Statement, addrIdx: var uint) =
  case stmt.kind
  of CreateImmutVal:
    inc addrIdx
    runtime.ir.loadInt(
      addrIdx,
      stmt.imAtom
    )
  of CreateMutVal:
    inc addrIdx
    runtime.ir.loadInt(
      addrIdx,
      stmt.mutAtom
    )
  of Call:
    runtime.ir.call(stmt.fn.normalizeIRName())
  else: discard

proc generateIR*(runtime: Runtime) =
  var 
    addrIdx: uint
    clauses: seq[string]

  print runtime.ast

  for scope in runtime.ast:
    let fn = cast[Function](scope)
    if *fn.name and not clauses.contains(&fn.name):
      clauses.add(&fn.name)
      runtime.ir.newModule(&fn.name)

    for stmt in scope.stmts:
      for child in stmt.expand():
        runtime.generateIR(child, addrIdx)

      runtime.generateIR(stmt, addrIdx)

proc run*(runtime: Runtime) =
  runtime.generateIR()

  let source = runtime.ir.emit()
  echo source

  runtime.vm = newPulsarInterpreter(source)
  runtime.vm.analyze()
  runtime.vm.setEntryPoint("outer")
  runtime.vm.run()

proc newRuntime*(file: string, ast: AST): Runtime {.inline.} =
  Runtime(
    ast: ast,
    ir: newIRGenerator(
      "bali-" & $sha256(file).toHex()
    )
  )
