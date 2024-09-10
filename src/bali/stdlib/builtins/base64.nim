## Base64 encoding/decoding
##
## Copyright (C) 2024 Trayambak Rai and Ferus Authors
import std/[base64, logging]
import mirage/ir/generator
import mirage/runtime/prelude
import bali/runtime/normalize
import bali/stdlib/errors
import bali/internal/sugar
import pretty

proc generateStdIr*(vm: PulsarInterpreter, generator: IRGenerator) =
  info "builtins.base64: generating IR interfaces"
  
  # atob
  # Turn base64-encoded data into a normal string
  generator.newModule("atob")
  vm.registerBuiltin("BALI_ATOB",
    proc(op: Operation) =
      if op.arguments.len < 1:
        typeError(vm, "atob: At least 1 argument required, but only 0 passed")
        return

      let value = op.arguments[0]
      if value.kind != String:
        typeError(vm, "atob: Expected String, got " & $value.kind & " instead")
        return
      
      try:
        vm.registers.retVal = decode(&value.getStr())
      except ValueError as exc:
        warn "atob: failed to decode string: " & exc.msg
        typeError(vm, "atob: String contains an invalid character")
        return
  )
  generator.call("BALI_ATOB")
