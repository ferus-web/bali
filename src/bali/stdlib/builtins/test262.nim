## Test262 required builtins
##
## Copyright (C) 2024 Trayambak Rai

import std/[strutils, math, options, logging]
import mirage/ir/generator
import mirage/runtime/prelude
import bali/runtime/normalize
import bali/internal/sugar
import pretty

proc generateStdIr*(vm: PulsarInterpreter, generator: IRGenerator) =
  info "builtins.test262: generating IR interfaces"
  
  # $DONOTEVALUATE (stub)
  generator.newModule(normalizeIRName "$DONOTEVALUATE")
  vm.registerBuiltin("TESTS_DONOTEVALUATE",
    proc(op: Operation) =
      return
  )
  generator.call("TESTS_DONOTEVALUATE")
