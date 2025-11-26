## Types and structures for Madhyasthal's optimization pipeline
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import std/sets
import pkg/bali/runtime/compiler/madhyasthal/[ir]

type
  UseOrDef* = object
    reg*: ir.Reg ## The register that was used/defined in this function
    inst*: uint32 ## The instruction that used/defined it

  Definition* = UseOrDef
  Use* = UseOrDef
  Mutation* = UseOrDef

  EscapeAnalysisInfo* = object
    locals*: HashSet[ir.Reg]

  DCEPassInfo* = object
    defs*: HashSet[Definition]
    rawDefs*: HashSet[ir.Reg]
    uses*: HashSet[Use]
    alive*: HashSet[ir.Reg]

  Copy* = object
    inst*: uint32
    source*, dest*: ir.Reg

  CopyPropInfo* = object
    aliased*: HashSet[ir.Reg]

  OptimizerInfo* = object
    dce*: DCEPassInfo
    cprop*: CopyPropInfo
    esc*: EscapeAnalysisInfo

  Pipeline* = object
    fn*: ir.Function
    info*: OptimizerInfo

  Passes* {.pure, size: sizeof(uint8).} = enum
    ## All optimization passes Madhyasthal supports
    NaiveDeadCodeElim
    AlgebraicSimplification
    CopyPropagation
    EscapeAnalysis

  OptimizationPass* = proc(state: var Pipeline): bool

func isUsedBeyond*(dce: DCEPassInfo, reg: ir.Reg, inst: uint32): bool {.inline.} =
  for use in dce.uses:
    if use.reg == reg and use.inst > inst:
      return true
