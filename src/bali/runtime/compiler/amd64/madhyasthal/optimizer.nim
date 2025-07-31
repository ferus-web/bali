import
  pkg/bali/runtime/compiler/amd64/madhyasthal/[
    pipeline,

    # All optimization passes
    naive_dce,
  ]
import pkg/[shakar]

proc optimize*(pipeline: var pipeline.Pipeline, passes: set[Passes] = {}) =
  for pass in passes:
    case pass
    of Passes.NaiveDeadCodeElim:
      eliminateDeadCodeNaive(pipeline)
    else:
      unreachable
