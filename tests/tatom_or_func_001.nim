import pkg/bali/runtime/atom_obj_variant
import pkg/bali/runtime/vm/atom
import pkg/bali/runtime/vm/heap/manager

# We need to setup the heap manager ourselves, otherwise
# the allocations below won't work.
var heapMgr = initHeapManager()
setHeapManager(heapMgr)

var v1 = initAtomOrFunction(
  proc(name: string) =
    echo "Hi, " & name
)

var v2 = initAtomOrFunction[proc()](integer(1337))

v1.fn()("tray")
echo v2.atom().crush()
