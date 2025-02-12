import bali/runtime/vm/runtime/prelude
import bali/runtime/types
import bali/stdlib/errors

proc RequireObjectCoercible*(runtime: Runtime, value: JSValue): JSValue {.inline.} =
  if value.kind == Null:
    runtime.typeError("Object is not coercible: " & value.crush())
    return null()

  value
