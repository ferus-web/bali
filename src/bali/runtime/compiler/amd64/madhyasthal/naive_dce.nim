## Naive dead-code-elimination/DCE implementation
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import std/[sets]
import pkg/bali/runtime/compiler/amd64/madhyasthal/[ir, pipeline]

proc scanForReferencedRegs*(pipeline: var pipeline.Pipeline, regs: var HashSet[ir.Reg]) =
  ## This routine goes over the entire function's body and checks which registers
  ## have been referenced in some way or the other.
  ##
  ## When such a register is found, it is added to the `regs` set which constitutes
  ## all the values the compiler knows have been referred to atleast once.
  for inst in pipeline.fn.insts:
    case inst.kind
    of {
      InstKind.LoadUndefined, InstKind.LoadNumber, InstKind.LoadBoolean,
      InstKind.LoadNull, InstKind.LoadBytecodeCallable, InstKind.LoadString
    }: regs.incl inst.args[0].vreg
    else: discard # The rest either have side-effects or don't cause value allocations

proc scanForUsedRegs*(pipeline: var pipeline.Pipeline, used: var HashSet[ir.Reg]) =
  ## This routine goes over the entire function's body and checks which registers
  ## have been referenced in ways that actually affect semantics.
  ##
  ## When such a register is found, it adds it to the `used` set which constitutes
  ## all the values the compiler believes are alive.
  for inst in pipeline.fn.insts:
    case inst.kind
    of {
      InstKind.PassArgument, InstKind.Invoke
    }:
      used.incl inst.args[0].vreg
    else: discard

proc scanAndElimDeadRefs*(pipeline: var pipeline.Pipeline, dead: HashSet[ir.Reg]) =
  ## This routine eliminates all instructions that are known 
  ## to be working with dead values.
  let unelimInsts = pipeline.fn.insts
  pipeline.fn.insts.reset()

  for inst in unelimInsts:
    if inst.args[0].kind == avkPos and
      inst.args[0].vreg in dead:
      continue

    if inst.args[1].kind == avkPos and
      inst.args[1].vreg in dead:
      continue

    pipeline.fn.insts &=
      inst

proc eliminateDeadCodeNaive*(pipeline: var pipeline.Pipeline) =
  ## Entry routine into the naive dead code elimination mechanism

  var
    allRegs = initHashSet[ir.Reg]()
    usedRegs = initHashSet[ir.Reg]()

  scanForReferencedRegs(pipeline, allRegs)
  scanForUsedRegs(pipeline, usedRegs)

  let deadRegs = allRegs - usedRegs
  scanAndElimDeadRefs(pipeline, deadRegs)
