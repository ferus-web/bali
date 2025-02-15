## Constant values (like NaN, undefined, null, etc.)

import std/[logging]
import bali/runtime/vm/ir/generator
import bali/runtime/vm/atom
import bali/runtime/vm/runtime/[prelude]
import bali/runtime/types

proc generateStdIr*(runtime: Runtime) =
  if runtime.constantsGenerated:
    return

  runtime.constantsGenerated = true

  let params = IndexParams(priorities: @[vkGlobal])

  debug "constants: generating constant values"
  let undefined = runtime.index("undefined", params)
  runtime.ir.loadObject(undefined)
  runtime.ir.markGlobal(undefined)

  let nan = runtime.index("NaN", params)
  runtime.ir.loadFloat(nan, stackFloating(NaN))
  runtime.ir.markGlobal(nan)

  let vTrue = runtime.index("true", params)
  runtime.ir.loadBool(vTrue, true)
  runtime.ir.markGlobal(vTrue)

  let vFalse = runtime.index("false", params)
  runtime.ir.loadBool(vFalse, false)
  runtime.ir.markGlobal(vFalse)

  let null = runtime.index("null", params)
  runtime.ir.loadNull(null)
  runtime.ir.markGlobal(null)
