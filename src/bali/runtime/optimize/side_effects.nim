## Routines to compute whether a statement has a side effect
## 
## Author: Trayambak Rai (xtrayambak at disroot dot org)
import std/options
import pkg/bali/grammar/[statement],
       pkg/shakar

proc hasSideEffects*(stmt: Statement): bool =
  case stmt.kind
  of { CreateMutVal, CreateImmutVal, BinaryOp }:
    # We know that these won't cause any observable
    # side effects.

    return false
  else:
    # We're not too sure of these.
    # We can't safely elide them.
    return true

proc isScopeSideEffectFree*(scope: Scope): bool =
  for stmt in scope.stmts:
    if stmt.hasSideEffects:
      return false

  true

# Side-effect free for-loops can be proven safe-to-eliminate via these two subroutines
proc forLoopIteratorHasSideEffects*(iter, initializer: Statement): bool =
  var initIdent: string
  
  # If the initializer creates a value, then we can proceed.
  # Else, we can assume that the loop does indeed have side effects.
  case initializer.kind
  of CreateMutVal:
    initIdent = initializer.mutIdentifier
  of CreateImmutVal:
    initIdent = initializer.imIdentifier
  else:
    return true
  
  return (
    case iter.kind
    of Increment: iter.incIdent != initIdent
    of Decrement: iter.decIdent != initIdent
    # TODO: add more cases here so that we can safely prove more cases as elidable
    else: true
  )

proc forLoopHasObservableSideEffects*(loop: Statement): bool =
  assert(loop.kind == ForLoop)

  if not isScopeSideEffectFree(loop.forLoopBody):
    # The body has side effects.
    return true

  if *loop.forLoopInitializer and hasSideEffects(&loop.forLoopInitializer):
    # If the initializer exists and has a side effect,
    # the entire loop has the side effect. Hence, we cannot
    # safely elide it.
    return true

  if *loop.forLoopIter and hasSideEffects(&loop.forLoopIter):
    if !loop.forLoopInitializer:
      # If the iterator has a side effect and there is no initializer, it
      # is most likely accessing an outer variable. In this case, the loop
      # carries a side-effect.
      return true
    
    # Check whether the iteration statement only mutates the initializer's variable.
    # If not, then this loop has a side effect.
    return forLoopIteratorHasSideEffects(&loop.forLoopIter, &loop.forLoopInitializer)

  # The loop has no observable side effects.
  false
