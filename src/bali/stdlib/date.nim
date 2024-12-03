## WIP implementation of the `Date` object
import std/[times, logging]
import bali/internal/sugar
import bali/runtime/[normalize, atom_helpers, arguments, types]
import bali/runtime/abstract/coercion

type
  JSDate* = object
    

proc generateStdIR*(runtime: Runtime) =
  info "date: generating IR interfaces"

  runtime.registerType("JSON", JSON)
