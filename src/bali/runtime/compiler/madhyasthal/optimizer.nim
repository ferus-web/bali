import
  pkg/bali/runtime/compiler/madhyasthal/[
    pipeline,

    # All optimization passes
    naive_dce,
    folding,
    copy_propagation,
    escape_analysis,
  ]
import pkg/[shakar]

func optimize*(pipeline: var pipeline.Pipeline, passes: seq[Passes]) =
  for pass in passes:
    case pass
    of Passes.NaiveDeadCodeElim:
      eliminateDeadCodeNaive(pipeline)
    of Passes.AlgebraicSimplification:
      rewriteAlgebraicExpressions(pipeline)
    of Passes.CopyPropagation:
      propagateCopies(pipeline)
    of Passes.EscapeAnalysis:
      analyzeEscapes(pipeline)
    else:
      unreachable
