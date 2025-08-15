## Types and structures for Madhyasthal's optimization pipeline
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import std/sets
import pkg/bali/runtime/compiler/amd64/madhyasthal/[ir]

type
  UseOrDef* = object
    reg*: ir.Reg ## The register that was used/defined in this function
    inst*: uint32 ## The instruction that used/defined it

  Definition* = distinct UseOrDef
  Use* = distinct UseOrDef

  DCEPassInfo* = object
    defs*: HashSet[Definition]
    uses*: HashSet[Use]

  CopyPropInfo* = object
    aliased*: HashSet[ir.Reg]

  OptimizerInfo* = object
    dce*: DCEPassInfo
    cprop*: CopyPropInfo

  Pipeline* = object
    fn*: ir.Function
    info*: OptimizerInfo

  Passes* {.pure, size: sizeof(uint8).} = enum
    ## All optimization passes Madhyasthal supports
    NaiveDeadCodeElim
    AlgebraicSimplification
    CopyPropagation

  OptimizationPass* = proc(state: var Pipeline): bool
