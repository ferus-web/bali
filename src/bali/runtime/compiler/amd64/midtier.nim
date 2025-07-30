## Mid-tier JIT compiler for x86-64
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import std/[logging, posix, options, tables]
import pkg/bali/runtime/compiler/amd64/madhyasthal/[ir, lowering, pipeline, optimizer, dumper],
       pkg/bali/runtime/compiler/amd64/common,
       pkg/bali/runtime/compiler/base
import pkg/shakar

type
  MidtierJIT* = object of AMD64Codegen

proc compileLowered(cgen: var MidtierJIT, fn: ir.Function): Option[JITSegment] =
  echo "Compiling `" & fn.name & "`:\n" & dumpFunction(fn)
  assert off

proc compile*(cgen: var MidtierJIT, clause: Clause): Option[JITSegment] =
  if clause.name in cgen.cached:
    return some(cgen.cached[clause.name])
  
  let lowered = lowering.lower(clause)
  if !lowered:
    warn "jit/amd64: midtier compiler failed to lower clause, falling back to VM"
    return

  var pipeline = Pipeline(fn: &lowered)
  pipeline.optimize({ Passes.NaiveDeadCodeElim })

  let fn = pipeline.fn
  return compileLowered(cgen, fn)

proc initAMD64MidtierCodegen*(vm: pointer, callbacks: VMCallbacks): MidtierJIT =
  info "jit/amd64: initializing midtier jit"

  var cgen = MidtierJIT(vm: vm, callbacks: callbacks)
  cgen.pageSize = sysconf(SC_PAGESIZE)
  debug "jit/amd64: page size is " & $cgen.pageSize

  move(cgen)
