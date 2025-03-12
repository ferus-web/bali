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
  runtime.ir.loadUndefined(undefined)

  let nan = runtime.index("NaN", params)
  runtime.ir.loadFloat(nan, stackFloating(NaN))

  let vTrue = runtime.index("true", params)
  runtime.ir.loadBool(vTrue, true)

  let vFalse = runtime.index("false", params)
  runtime.ir.loadBool(vFalse, false)

  let null = runtime.index("null", params)
  runtime.ir.loadNull(null)
