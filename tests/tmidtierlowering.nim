## madhyasthal lowering tests
import std/[importutils, tables]
import pkg/bali/runtime/compiler/madhyasthal/[ir, lowering, dumper, pipeline, optimizer]
import pkg/bali/runtime/vm/interpreter/interpreter
import pkg/bali/easy
import pkg/[shakar, pretty]

var x = createRuntimeForSource(
  """
function thing()
{
	let x = 32 // x never escapes, so it can be stack-allocated
	let y = 64 // y never escapes, so it can be stack-allocated
	let z = x + y;

	return z
}

/* for (var i = 0; i < 10000; i++)
{
	let res = thing()
} */
  """
)
x.run()

privateAccess(PulsarInterpreter)

assert x.vm.clauses[x.vm.clauses.len - 1].name == "thing"
let outer = x.vm.clauses[x.vm.clauses.len - 1]
print outer

let lowered = &lowering.lower(outer)
echo "Lowered: "
echo dumpFunction(lowered)

var ppl = Pipeline(fn: lowered)
ppl.optimize(
  {Passes.NaiveDeadCodeElim, Passes.AlgebraicSimplification, Passes.EscapeAnalysis}
)
print ppl.info

echo "Optimized: "
echo dumpFunction(ppl.fn)
