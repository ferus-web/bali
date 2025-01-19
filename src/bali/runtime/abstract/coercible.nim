import mirage/runtime/prelude
import bali/runtime/types
import bali/stdlib/errors

proc RequireObjectCoercible*(runtime: Runtime, value: MAtom): MAtom {.inline.} =
  if value.kind == Null:
    runtime.typeError("Object is not coercible: " & value.crush())
    return

  value
