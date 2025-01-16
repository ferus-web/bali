## The main routine of this module needs to be called each time a loop body is about to be generated.
## It performs an optimization pass over it to see if there's any redundant loop allocations.
##
## For instance, in pseudocode:
## while true do
##allocate "hello world" at [1]
##   print [1]
## end
##
## This can be optimized away to:
## allocate "hello world" at [1]
## while true do
##   print [1]
## end

import std/[logging]
import mirage/atom
import mirage/ir/generator
import bali/grammar/prelude
import bali/runtime/[statement_utils, types]

type AllocationEliminatorResult* = object
  placeBefore*: Scope ## All statements here are to be placed outside the loop
  modifiedBody*: Scope
    ## This is the modified body and it should be placed where the original body was intended

proc eliminateRedundantLoopAllocations*(
    runtime: Runtime, body: Scope
): AllocationEliminatorResult =
  debug "redundant_loop_allocations: checking if redundant allocations can be eliminated in loop body..."

  var elims: AllocationEliminatorResult
  elims.placeBefore = Scope()
  elims.modifiedBody = Scope()

  for stmt in body.stmts:
    case stmt.kind
    of CreateImmutVal, CreateMutVal:
      debug "redundant_loop_allocations: moving " & $stmt.kind &
        " into place-before scope"
      elims.placeBefore.stmts &= stmt
    else:
      debug "redundant_loop_allocations: moving " & $stmt.kind &
        " into modified-body scope"
      elims.modifiedBody.stmts &= stmt

  elims
