## Routines to decide whether a segment of the AST is safely elidable
## Author: Trayambak Rai (xtrayambak at disroot dot org)

#!fmt: off
import pkg/bali/grammar/[statement],
       pkg/bali/runtime/optimize/[side_effects]
#!fmt: on

proc forLoopIsDead*(loop: Statement): bool =
  assert(loop.kind == ForLoop)

  not forLoopHasObservableSideEffects(loop)
