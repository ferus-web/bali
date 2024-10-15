import bali/runtime/atom_obj_variant
import mirage/atom

var v1 = initAtomOrFunction(
  proc(name: string) =
    echo "Hi, " & name
)

var v2 = initAtomOrFunction[proc()](
  integer(1337)
)

v1.fn()("tray")
echo v2.atom().crush()
