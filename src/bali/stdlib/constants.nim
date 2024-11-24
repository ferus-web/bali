## Constant values (like NaN, undefined, null, etc.)

import std/[options, logging, tables]
import bali/internal/sugar
import bali/runtime/[normalize, atom_helpers]
import bali/runtime/abstract/coercion
import bali/stdlib/errors
import jsony
import mirage/ir/generator
import mirage/atom
import mirage/runtime/[prelude]
import bali/runtime/types
import sanchar/parse/url
import pretty

proc generateStdIr*(runtime: Runtime) =
  if runtime.constantsGenerated:
    return

  runtime.constantsGenerated = true

  debug "constants: generating constant values"
  runtime.ir.loadObject(runtime.addrIdx)
  runtime.ir.markGlobal(runtime.addrIdx)
  runtime.markGlobal("undefined")

  runtime.ir.loadFloat(runtime.addrIdx, floating(NaN))
  runtime.ir.markGlobal(runtime.addrIdx)
  runtime.markGlobal("NaN")

  runtime.ir.loadBool(runtime.addrIdx, true)
  runtime.ir.markGlobal(runtime.addrIdx)
  runtime.markGlobal("true")

  runtime.ir.loadBool(runtime.addrIdx, false)
  runtime.ir.markGlobal(runtime.addrIdx)
  runtime.markGlobal("false")

  runtime.ir.loadNull(runtime.addrIdx)
  runtime.ir.markGlobal(runtime.addrIdx)
  runtime.markGlobal("null")
