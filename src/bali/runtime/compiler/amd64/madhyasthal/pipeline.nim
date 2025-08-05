import pkg/bali/runtime/compiler/amd64/madhyasthal/[ir]

type
  Pipeline* = object
    fn*: ir.Function

  Passes* {.pure, size: sizeof(uint8).} = enum
    ## All optimization passes Madhyasthal supports
    NaiveDeadCodeElim
    AlgebraicSimplification

  OptimizationPass* = proc(state: var Pipeline): bool
