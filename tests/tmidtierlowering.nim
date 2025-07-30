## madhyasthal lowering tests
import std/[importutils, tables]
import pkg/bali/runtime/compiler/amd64/madhyasthal/[ir, lowering, dumper]
import pkg/bali/runtime/vm/interpreter/interpreter
import pkg/bali/easy
import pkg/[shakar, pretty]

var x = createRuntimeForSource(
  """
console.log("Hello world!")
  """
)
x.run()

privateAccess(PulsarInterpreter)

assert x.vm.clauses[x.vm.clauses.len - 1].name == "outer"
let outer = x.vm.clauses[x.vm.clauses.len - 1]
print outer

let lowered = lowering.lower(outer)
echo dumpFunction(&lowered)
