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
import mirage/atom
import bali/grammar/prelude
import bali/runtime/[statement_utils, types]

proc optimizeAwayStateMutatorLoop*(
    runtime: Runtime, fn: Function, stmt: Statement
): bool =
  debug "mutator_loops: checking if loop can be elided (is it a state mutator?)"
  let muts = stmt.whConditionExpr.getStateMutators()
  debug "mutator_loops: expression depends on " & $muts.len & " mutators"

  for mut in muts:
    debug "mutator_loops: expression mutator: " & mut
    var leftTrav = stmt.whConditionExpr.binLeft
    var rightTrav = stmt.whConditionExpr.binRight

    if leftTrav.kind == IdentHolder and leftTrav.ident == mut:
      debug "mutator_loops: condition expression LHS is an ident, and it matches `" & mut &
        '`'
      if rightTrav.kind != AtomHolder:
        warn "mutator_loops: TODO: implement codegen optimization for when LHS is an ident and RHS is an atom!"
        return false # FIXME: also implement this optimization for identifiers

      if stmt.whConditionExpr.op == BinaryOperation.LesserThan:
        debug "mutator_loops: op is less-than, optimizing away loop into the value of RHS (" &
          rightTrav.atom.crush() & ')'
        let idx = runtime.loadIRAtom(rightTrav.atom)
        runtime.markLocal(fn, leftTrav.ident)
        return true

    if rightTrav.kind == IdentHolder and rightTrav.ident == mut:
      debug "mutator_loops: condition expression RHS is an ident, and it matches `" & mut &
        '`'
      if leftTrav.kind != AtomHolder:
        warn "mutator_loops: TODO: implement codegen optimization for when LHS is an atom and RHS is an ident!"
        return false # FIXME: same as above

      if stmt.whConditionExpr.op == BinaryOperation.LesserThan:
        debug "mutator_loops: op is less-than, optimizing away loop into the value of LHS (" &
          leftTrav.atom.crush() & ')'
        let idx = runtime.loadIRAtom(leftTrav.atom)
        runtime.markLocal(fn, rightTrav.ident)
        return true

  return false
