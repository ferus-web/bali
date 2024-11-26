## Optimization routine to optimize away mutator loops
## Loops like:
## .. code-block:: Nim
##   var i = 0
##   while (i < 9999)
##   {
##     i++
##   }
##
## Can be elided into:
## .. code-block:: Nim
##   var i = 9999

import std/[logging]
import mirage/ir/generator
import bali/grammar/prelude
import bali/runtime/[statement_utils, types]

proc optimizeAwayStateMutatorLoop*(runtime: Runtime, fn: Function, stmt: Statement): bool =
  let muts = stmt.whConditionExpr.getStateMutators()
  
  for mut in muts:
    var leftTrav = stmt.whConditionExpr.binLeft
    var rightTrav = stmt.whConditionExpr.binRight

    if leftTrav.kind == IdentHolder and leftTrav.ident == mut:
      if rightTrav.kind != AtomHolder:
        return false # FIXME: also implement this optimization for identifiers
      
      if stmt.whConditionExpr.op == BinaryOperation.LesserThan:
        let idx = runtime.loadIRAtom(rightTrav.atom)
        runtime.markLocal(fn, leftTrav.ident)
        return true

    if rightTrav.kind == IdentHolder and rightTrav.ident == mut:
      if leftTrav.kind != AtomHolder:
        return false # FIXME: same as above
      
      if stmt.whConditionExpr.op == BinaryOperation.LesserThan:
        let idx = runtime.loadIRAtom(leftTrav.atom)
        runtime.markLocal(fn, rightTrav.ident)
        return true

  return false
