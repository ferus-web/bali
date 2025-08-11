## ===========
## Algebraic simplification implementation
## ===========
##
## This pass works by scanning for arithmetic operations and checking if their operands were
## allocated right before the arithmetic ops. If so, then we can make a huge list
## of assumptions:
## * We can perform constant folding safely.
## * We can apply certain well-known arithmetic rules to safely eliminate unneeded
##   patterns.
##
## This is best invoked after the dead code elimination pass to reduce
## the amount of instructions it needs to iterate over (a _LOT_!)
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import std/[options, sets]
import pkg/bali/runtime/compiler/amd64/madhyasthal/[ir, pipeline]
import pkg/shakar

proc inferLocallyAllocatedNumericOperandValue*(
    pipeline: pipeline.Pipeline, insts: seq[ir.Inst], before: int, operand: ir.Reg
): Option[float] =
  if insts.len < 1:
    return

  for i, inst in insts[0 ..< before]:
    if inst.kind != InstKind.LoadNumber:
      continue

    if inst.args[0].vreg == operand:
      return some(inst.args[1].flt)

proc findNumericOpAllocationPoint*(
    pipeline: pipeline.Pipeline, insts: seq[ir.Inst], op: ir.Reg
): Option[int] =
  for i, inst in insts:
    if inst.kind != InstKind.LoadNumber:
      continue

    if inst.args[0].vreg == op:
      return some(i)

proc rewriteAlgebraicExpressions*(pipeline: var pipeline.Pipeline) =
  var insts = pipeline.fn.insts
  var rewritten = newSeqOfCap[ir.Inst](insts.len)
  pipeline.fn.insts.reset()

  template InferOperands() =
    let src = inferLocallyAllocatedNumericOperandValue(
      pipeline, insts = insts, before = i, operand = inst.args[0].vreg
    )

    if !src:
      # The source value ([1]) is not allocated in this function.
      # Don't attempt to optimize this.
      rewritten &= inst
      continue

    let dest = inferLocallyAllocatedNumericOperandValue(
      pipeline, insts = insts, before = i, operand = inst.args[1].vreg
    )
    if !dest:
      # The destination value ([2]) is not allocated in this function.
      # Don't attempt to optimize this.
      rewritten &= inst
      continue

    let
      vsrc {.inject, used.} = &src
      vdest {.inject, used.} = &dest

  for i, inst in insts:
    case inst.kind
    of InstKind.Add:
      InferOperands

      # Case 1:
      # x + 0 = x
      if vsrc == 0 and vdest == 0:
        continue # They're already computed, duh.

      if vsrc == 0 and vdest != 0:
        continue # We don't need to do anything, the result's already computed.

      # In all other cases, we unfortunately need to let the instruction survive.
      rewritten &= inst
    of InstKind.Sub:
      InferOperands

      if vsrc == 0 and vdest == 0:
        continue # They're already computed, duh.

      # Case 1:
      # x - 0 = x
      if vdest == 0:
        rewritten &= copy(inst.args[0].vreg, inst.args[1].vreg)
        continue

      rewritten &= inst
    of InstKind.Mult:
      InferOperands

      # x * 0 = 0
      # OR
      # 0 * x = 0
      if vsrc == 0 or vdest == 0:
        let
          srcAllocPos =
            &findNumericOpAllocationPoint(pipeline, rewritten, inst.args[0].vreg)
          destAllocPos =
            &findNumericOpAllocationPoint(pipeline, rewritten, inst.args[1].vreg)

        assert srcAllocPos != destAllocPos
          # FIXME: We should really handle this properly.

        rewritten[destAllocPos] = loadNumber(inst.args[0].vreg, 0)
        rewritten.delete(srcAllocPos)
        continue

      # x * 1 = x
      if vdest == 1:
        let
          srcAllocPos =
            &findNumericOpAllocationPoint(pipeline, rewritten, inst.args[0].vreg)
          destAllocPos =
            &findNumericOpAllocationPoint(pipeline, rewritten, inst.args[1].vreg)

        assert srcAllocPos != destAllocPos
          # FIXME: We should really handle this properly.

        rewritten[destAllocPos] = loadNumber(inst.args[0].vreg, vsrc)
        rewritten.delete(srcAllocPos)

      rewritten &= inst
    of InstKind.Divide:
      InferOperands

      # x / 0 = Inf
      if vdest == Inf:
        let
          srcAllocPos =
            &findNumericOpAllocationPoint(pipeline, rewritten, inst.args[0].vreg)
          destAllocPos =
            &findNumericOpAllocationPoint(pipeline, rewritten, inst.args[1].vreg)

        assert srcAllocPos != destAllocPos
          # FIXME: We should really handle this properly.

        rewritten[destAllocPos] = loadNumber(inst.args[0].vreg, Inf)
        rewritten.delete(srcAllocPos)
        continue

      rewritten &= inst
    else:
      rewritten &= inst

  pipeline.fn.insts &= ensureMove(rewritten)

proc foldExpressions*(pipeline: var pipeline.Pipeline) =
  rewriteAlgebraicExpressions(pipeline)
