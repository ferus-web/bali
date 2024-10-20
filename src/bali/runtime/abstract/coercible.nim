import std/[logging]
import mirage/runtime/prelude
import bali/runtime/[atom_helpers, types]
import bali/stdlib/errors

proc RequireObjectCoercible*(vm: PulsarInterpreter, value: MAtom): MAtom {.inline.} =
  if value.kind == Null:
    vm.typeError("Object is not coercible: " & value.crush())
    return

  value

proc RequireObjectCoercible*(runtime: Runtime, value: MAtom): MAtom {.inline.} =
  runtime.vm.RequireObjectCoercible(value)
