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
  if unlikely(fn.name in cgen.dumpIrForFuncs):
    echo dumpFunction(fn)
    when not defined(release):
      assert(off)

  for inst in fn.insts:
    case inst.kind
    of InstKind.LoadNumber:
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
    of InstKind.ReadProperty:
      let
        index = inst.args[0].vreg
        field = inst.args[1].str

      prepareLoadString(cgen, cstring(field))
      cgen.s.push(regR8.reg)

      alignStack 16:
        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRsi, cast[int64](index))
        cgen.s.call(cgen.callbacks.getAtom)

      cgen.s.pop(regRsi.reg)
      cgen.s.mov(regRdi.reg, regRax)

      alignStack 8:
        cgen.s.call(getProperty)

      cgen.s.mov(regRsi.reg, regRax)

      alignStack 8:
        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.call(cgen.callbacks.addRetval)
    of InstKind.ReadScalarRegister:
      let
        register = inst.args[0].vint
        dest = inst.args[1].vreg

      alignStack 8:
        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRsi, cast[int64](dest))
        cgen.s.mov(regRdx, cast[int64](register))
        cgen.s.call(cgen.callbacks.readScalarRegister)
    of InstKind.PassArgument:
      let source = inst.args[0].vreg
      alignStack 8:
        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRsi, cast[int64](source))
        cgen.s.call(cgen.callbacks.passArgument)
    of InstKind.Invoke:
      let index = inst.args[0].vreg
      alignStack 8:
        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRsi, int64(index))
        cgen.s.call(cgen.callbacks.invoke)
    of InstKind.LoadString:
      let
        dest = inst.args[0].vreg
        str = inst.args[1].str

      prepareLoadString(cgen, cstring(str))

      alignStack 8:
        cgen.s.mov(regRdi.reg, regR8)
        cgen.s.call(strRaw)

      cgen.s.mov(regRsi.reg, regRax)

      alignStack 8:
        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRdx, int64(dest))
    of InstKind.Add:
      let
        source = inst.args[0].vreg
        dest = inst.args[1].vreg

      alignStack 8:
        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRsi, int64(source))
        cgen.s.call(cgen.callbacks.getAtom)

        cgen.s.mov(regRdi.reg, regRax)
        cgen.s.call(getRawFloat)
        cgen.s.movsd(regXmm1, regXmm0.reg)

        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRsi, int64(dest))
        cgen.s.call(cgen.callbacks.getAtom)

        cgen.s.mov(regRdi.reg, regRax)
        cgen.s.call(getRawFloat)

        cgen.s.addsd(regXmm0, regXmm1.reg)
        cgen.s.call(allocFloat)

        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRsi.reg, regRax)
        cgen.s.mov(regRdx, int64(dest))
        cgen.s.call(cgen.callbacks.addAtom)
    of InstKind.Sub:
      let
        source = inst.args[0].vreg
        dest = inst.args[1].vreg

      alignStack 8:
        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRsi, int64(source))
        cgen.s.call(cgen.callbacks.getAtom)

        cgen.s.mov(regRdi.reg, regRax)
        cgen.s.call(getRawFloat)
        cgen.s.movsd(regXmm1, regXmm0.reg)

        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRsi, int64(dest))
        cgen.s.call(cgen.callbacks.getAtom)

        cgen.s.mov(regRdi.reg, regRax)
        cgen.s.call(getRawFloat)

        cgen.s.subsd(regXmm1, regXmm0.reg)
        cgen.s.movsd(regXmm0, regXmm1.reg)
        cgen.s.call(allocFloat)

        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRsi.reg, regRax)
        cgen.s.mov(regRdx, int64(dest))
        cgen.s.call(cgen.callbacks.addAtom)
    of InstKind.Mult:
      let
        source = inst.args[0].vreg
        dest = inst.args[1].vreg

      alignStack 8:
        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRsi, int64(source))
        cgen.s.call(cgen.callbacks.getAtom)

        cgen.s.mov(regRdi.reg, regRax)
        cgen.s.call(getRawFloat)
        cgen.s.movsd(regXmm1, regXmm0.reg)

        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRsi, int64(dest))
        cgen.s.call(cgen.callbacks.getAtom)

        cgen.s.mov(regRdi.reg, regRax)
        cgen.s.call(getRawFloat)

        cgen.s.mulsd(regXmm0, regXmm1.reg)
        cgen.s.call(allocFloat)

        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRsi.reg, regRax)
        cgen.s.mov(regRdx, int64(dest))
        cgen.s.call(cgen.callbacks.addAtom)
    of InstKind.Divide:
      let
        source = inst.args[0].vreg
        dest = inst.args[1].vreg

      alignStack 8:
        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRsi, int64(source))
        cgen.s.call(cgen.callbacks.getAtom)

        cgen.s.mov(regRdi.reg, regRax)
        cgen.s.call(getRawFloat)
        cgen.s.movsd(regXmm1, regXmm0.reg)

        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRsi, int64(dest))
        cgen.s.call(cgen.callbacks.getAtom)

        cgen.s.mov(regRdi.reg, regRax)
        cgen.s.call(getRawFloat)

        cgen.s.ddivsd(regXmm1, regXmm0.reg)
        cgen.s.movsd(regXmm0, regXmm1.reg)
        cgen.s.call(allocFloat)

        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRsi.reg, regRax)
        cgen.s.mov(regRdx, int64(dest))
        cgen.s.call(cgen.callbacks.addAtom)
    of InstKind.Copy:
      let
        source = inst.args[0].vreg
        dest = inst.args[1].vreg

      alignStack 8:
        cgen.s.mov(regRdi, cast[int64](cgen.vm))
        cgen.s.mov(regRsi, int64(source))
        cgen.s.mov(regRdx, int64(dest))
    else:
      debug "jit/amd64: midtier cannot lower op into x64 code: " & $inst.kind
      return

  cgen.s.ret()
  cgen.cached[fn.name] = cast[JITSegment](cgen.s.data)
  some(cast[JITSegment](cgen.s.data))

proc compile*(cgen: var MidtierJIT, clause: Clause): Option[JITSegment] =
  if clause.name in cgen.cached:
    return some(cgen.cached[clause.name])

  let lowered = lowering.lower(clause)
  if !lowered:
    warn "jit/amd64: midtier compiler failed to lower clause, falling back to VM"
    return

  var pipeline = Pipeline(fn: &lowered)
  pipeline.optimize({Passes.NaiveDeadCodeElim, Passes.AlgebraicSimplification})

  allocateNativeSegment(cgen)
  return compileLowered(cgen, pipeline.fn)

proc initAMD64MidtierCodegen*(vm: pointer, callbacks: VMCallbacks): MidtierJIT =
  info "jit/amd64: initializing midtier jit"

  var cgen = MidtierJIT(vm: vm, callbacks: callbacks)
  cgen.pageSize = sysconf(SC_PAGESIZE)
  debug "jit/amd64: page size is " & $cgen.pageSize

  move(cgen)
