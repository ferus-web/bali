import std/[logging]
import mirage/runtime/prelude
import bali/runtime/[atom_helpers, types]
import bali/stdlib/errors

proc RequireObjectCoercible*(runtime: Runtime, value: MAtom): MAtom {.inline.} =
  if value.kind == Null:
    runtime.typeError("Object is not coercible: " & value.crush())
    return

  value
