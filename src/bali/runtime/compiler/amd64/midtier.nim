## Mid-tier JIT compiler for x86-64, utilizing the Madhyasthal pipeline.
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import std/[logging, posix, options, tables]
import
  pkg/bali/runtime/compiler/amd64/madhyasthal/
    [ir, lowering, pipeline, optimizer, dumper],
  pkg/bali/runtime/compiler/amd64/[common, native_forwarding],
  pkg/bali/runtime/compiler/base
import pkg/shakar

type MidtierJIT* = object of AMD64Codegen

template alignStack(offset: uint, body: untyped) =
  cgen.s.sub(regRsp.reg, offset)
  body
  cgen.s.add(regRsp.reg, offset)

proc compileLowered(cgen: var MidtierJIT, fn: ir.Function): Option[JITSegment] =
  echo dumpFunction(fn)
  for inst in fn.insts:
    case inst.kind
    of LoadNumber:
      let
        index = inst.args[0].vreg
        num = inst.args[1].flt

      alignStack 8:
        cgen.s.mov(regR9, cast[int64](num))
        cgen.s.movq(regR9.reg, regXmm0)
        cgen.s.call(allocFloatEncoded)

      cgen.s.mov(regRsi.reg, regRax)

      alignStack 8:
        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.call(cgen.callbacks.addAtom)
    of ReadProperty:
      let
        index = inst.args[0].vreg
        field = inst.args[1].str

      prepareLoadString(cgen, cstring(field))

      alignStack 8:
        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRsi, cast[int64](index))
        cgen.s.call(cgen.callbacks.getAtom)

      cgen.s.mov(regRdi.reg, regRax)

      alignStack 8:
        cgen.s.mov(regRsi.reg, regR8)
        cgen.s.call(getProperty)

      cgen.s.mov(regRsi.reg, regRax)

      alignStack 8:
        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.call(cgen.callbacks.addRetval)
    else:
      assert off, $inst.kind

proc compile*(cgen: var MidtierJIT, clause: Clause): Option[JITSegment] =
  if clause.name in cgen.cached:
    return some(cgen.cached[clause.name])

  let lowered = lowering.lower(clause)
  if !lowered:
    warn "jit/amd64: midtier compiler failed to lower clause, falling back to VM"
    return

  var pipeline = Pipeline(fn: &lowered)
  pipeline.optimize({Passes.NaiveDeadCodeElim})

  allocateNativeSegment(cgen)
  return compileLowered(cgen, pipeline.fn)

proc initAMD64MidtierCodegen*(vm: pointer, callbacks: VMCallbacks): MidtierJIT =
  info "jit/amd64: initializing midtier jit"

  var cgen = MidtierJIT(vm: vm, callbacks: callbacks)
  cgen.pageSize = sysconf(SC_PAGESIZE)
  debug "jit/amd64: page size is " & $cgen.pageSize

  move(cgen)
