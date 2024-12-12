## Implementation of the error throw IR builtin
## Refactored here because Nim hates me
## Authors:
## Trayambak Rai (xtrayambak at disroot dot org)
import std/[logging]
import mirage/runtime/prelude
import bali/stdlib/errors_common
import bali/runtime/[arguments, atom_helpers, types]
import bali/runtime/abstract/to_string
import bali/internal/sugar

proc generateStdIr*(runtime: Runtime) =
  info "errors: generate IR interface"

  runtime.vm.registerBuiltin(
    "BALI_THROWERROR",
    proc(op: Operation) =
      let atom = runtime.argument(1, required = true, message = "BUG: BALI_THROWERROR got {nargs} atoms, expected one!")
      runtime.vm.throw(jsException(
        runtime.ToString(&atom)
      ))
      runtime.logTracebackAndDie(),
  )
