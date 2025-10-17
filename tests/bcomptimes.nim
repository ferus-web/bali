## A benchmark to see how much time each compiler tier takes to compile some JS code
import std/importutils, std/tables
import bali/runtime/vm/heap/manager
import shakar, benchy
import bali/easy
import pretty
import bali/runtime/compiler/amd64/[baseline, midtier], bali/runtime/compiler/base
import bali/runtime/vm/interpreter/interpreter

privateAccess PulsarInterpreter

var mgr = initHeapManager()
var basel = initAMD64BaselineCodegen(nil, mgr, VMCallbacks())
var mid = initAMD64MidtierCodegen(nil, mgr, VMCallbacks())

var runt = createRuntimeForSource(
  """
function thing()
{
  let x = 32;
  let y = 64;
  let z = 128;
  let a = 256;
  let b = 512;
  let c = 1024;
  console.log(x)
}

thing();
"""
)

runt.run()
let thing = runt.vm.clauses[runt.vm.clauses.len - 1]

timeIt "baseline compiler", 10:
  let compiled {.used.} = basel.compile(thing, ignoreCache = true)

timeIt "midtier compiler", 10:
  let compiled {.used.} = mid.compile(thing, ignoreCache = true)

basel = initAMD64BaselineCodegen(nil, mgr, VMCallbacks())
mid = initAMD64MidtierCodegen(nil, mgr, VMCallbacks())

discard basel.compile(thing, ignoreCache = true)
discard mid.compile(thing, ignoreCache = true)

echo "Baseline compiled size: " & $basel.s.offset & " bytes"
echo "Midtier compiled size: " & $mid.s.offset & " bytes"
