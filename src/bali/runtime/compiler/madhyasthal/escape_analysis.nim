## Escape analysis implementation
## This only works after the dead code elimination pass
## has been executed.
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import std/[sets]
import pkg/bali/runtime/compiler/madhyasthal/[ir, pipeline]

func analyzeEscapePoints*(fn: ir.Function): HashSet[ir.Reg] =
  var escapes = initHashSet[ir.Reg]()

  for i, stmt in fn.insts:
    case stmt.kind
    of {InstKind.Return}:
      escapes.incl(stmt.args[0].vreg)
    else:
      discard

  ensureMove(escapes)

func analyzeEscapes*(pipeline: var pipeline.Pipeline) =
  # First, we can get the escape points from where registers/indices
  # leak beyond the function's scope.
  let escapePoints = analyzeEscapePoints(pipeline.fn)

  # Then, we can just check the alive registers and subtract the escaping registers
  # from that set to get the registers whose lifetimes are bound to this function's
  # scopes.
  pipeline.info.esc.locals = pipeline.info.dce.alive - escapePoints
