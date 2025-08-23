## Naive dead-code-elimination/DCE implementation
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import std/[sets]
import pkg/bali/runtime/compiler/madhyasthal/[ir, pipeline]

func markDef(pipeline: var pipeline.Pipeline, reg: ir.Reg, at: SomeNumber) =
  #!fmt: off
  pipeline.info.dce.defs.incl(
    Definition(reg: reg, inst: uint32(at))
  )
  #!fmt: on

func markUse(pipeline: var pipeline.Pipeline, reg: ir.Reg, at: SomeNumber) =
  #!fmt: off
  pipeline.info.dce.uses.incl(
    Use(reg: reg, inst: uint32(at))
  )
  #!fmt: on

func scanForAllocatedRegs*(pipeline: var pipeline.Pipeline, regs: var HashSet[ir.Reg]) =
  ## This routine goes over the entire function's body and checks which registers
  ## have been allocated in some way or the other.
  ##
  ## When such a register is found, it is added to the `regs` set which constitutes
  ## all the values the compiler knows have been referred to atleast once.
  for i, inst in pipeline.fn.insts:
    case inst.kind
    of {
      InstKind.LoadUndefined, InstKind.LoadNumber, InstKind.LoadBoolean,
      InstKind.LoadNull, InstKind.LoadBytecodeCallable, InstKind.LoadString,
    }:
      regs.incl inst.args[0].vreg
      markDef pipeline, inst.args[0].vreg, i
    else:
      discard # The rest either have side-effects or don't cause value allocations

func scanForUsedRegs*(
    pipeline: var pipeline.Pipeline, used: var HashSet[ir.Reg], start: int = 0
) =
  ## This routine goes over the entire function's body and checks which registers
  ## have been referenced in ways that actually affect semantics.
  ##
  ## When such a register is found, it adds it to the `used` set which constitutes
  ## all the values the compiler believes are alive.
  let iteration = pipeline.fn.insts[start ..< pipeline.fn.insts.len]
  var i = start

  while i < iteration.len:
    let inst = iteration[i]

    case inst.kind
    of {InstKind.PassArgument, InstKind.Invoke}:
      used.incl inst.args[0].vreg
    of {InstKind.Add, InstKind.Mult, InstKind.Divide, InstKind.Sub}:
      when not defined(baliMadhyasthalDCEOldAlgorithm):
        # Newer algorithm, can eliminate unused arithmetic ops
        var usedAhead = initHashSet[ir.Reg]()
        scanForUsedRegs(pipeline, usedAhead, start = start + i + 1)

        if inst.args[0].vreg in usedAhead:
          # If the destination is used ahead,
          # we can mark the two registers as
          # used. Otherwise, we can just let the
          # operation be elided away.
          used.incl inst.args[0].vreg
          used.incl inst.args[1].vreg

          markUse pipeline, inst.args[0].vreg, i
          markUse pipeline, inst.args[1].vreg, i

        if start > 0:
          # Optimization: Now that we've scanned ahead for used registers, we can simply merge
          # `usedAhead with `used` and skip a lot of instructions.
          #
          # `scanForUsedRegs()` pretty much scans everything ahead and builds up use-info
          # for instructions ahead, so there's no point in wasting time going ahead.
          #
          # This is only safe when we're in a recursion of this function, or when start > 0.
          # Do it when start == 0 (or... somehow less than zero, idk how but that isn't possible in normal cases)
          # and everything gets marked as dead and blown up.
          used = used + ensureMove(usedAhead)
          break
      else:
        # Old algorithm
        used.incl inst.args[0].vreg
        used.incl inst.args[1].vreg

        markUse pipeline, inst.args[0].vreg, i
        markUse pipeline, inst.args[1].vreg, i
    of InstKind.Copy:
      # Check if the results of this copy are used ahead anywhere.
      # If they aren't, then there's no point in this copy op.
      var usedAhead = initHashSet[ir.Reg]()
      scanForUsedRegs(pipeline, usedAhead, start = start + i + 1)

      if inst.args[1].vreg in usedAhead:
        used.incl inst.args[0].vreg
        used.incl inst.args[1].vreg

        markUse pipeline, inst.args[0].vreg, i
        markUse pipeline, inst.args[1].vreg, i

      if start > 0:
        # Optimization: The same as the huge wall of text I wrote above. I'm too lazy to write something here.
        used = used + ensureMove(usedAhead)
        break
    else:
      discard

    inc i

func scanAndElimDeadRefs*(pipeline: var pipeline.Pipeline, dead: HashSet[ir.Reg]) =
  ## This routine eliminates all instructions that are known 
  ## to be working with dead values.
  let unelimInsts = pipeline.fn.insts
  pipeline.fn.insts.reset()

  for inst in unelimInsts:
    if inst.args[0].kind == avkPos and inst.args[0].vreg in dead:
      continue

    if inst.args[1].kind == avkPos and inst.args[1].vreg in dead:
      continue

    pipeline.fn.insts &= inst

    if inst.args[0].kind == avkPos:
      pipeline.info.dce.alive.incl(inst.args[0].vreg)

    if inst.args[1].kind == avkPos:
      pipeline.info.dce.alive.incl(inst.args[1].vreg)

func eliminateDeadCodeNaive*(pipeline: var pipeline.Pipeline) =
  ## Entry routine into the naive dead code elimination mechanism

  var
    allRegs = initHashSet[ir.Reg]()
    usedRegs = initHashSet[ir.Reg]()

  scanForAllocatedRegs(pipeline, allRegs)
  scanForUsedRegs(pipeline, usedRegs)

  let deadRegs = allRegs - usedRegs
  scanAndElimDeadRefs(pipeline, deadRegs)
