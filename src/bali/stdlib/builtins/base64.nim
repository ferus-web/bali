## Base64 encoding/decoding
## These aren't part of the ECMAScript standard, but rather the HTML living spec.
##
## Copyright (C) 2024 Trayambak Rai and Ferus Authors
import std/[options, logging, tables]
import mirage/ir/generator
import mirage/runtime/prelude
import bali/runtime/normalize
import bali/runtime/abstract/coercion
import bali/stdlib/errors
import bali/internal/sugar
import pretty

when not defined(baliUseStdBase64):
  import simdutf/base64
else:
  import std/base64
  from simdutf/base64 import Base64DecodeError

proc generateStdIr*(vm: PulsarInterpreter, generator: IRGenerator) =
  info "builtins.base64: generating IR interfaces"
  
  # atob
  # Decode a base64 encoded string
  generator.newModule("atob")
  vm.registerBuiltin("BALI_ATOB",
    proc(op: Operation) =
      if vm.registers.callArgs.len < 1:
        typeError(vm, "atob: At least 1 argument required, but only 0 passed")
        return

      template decodeError =
        warn "atob: failed to decode string: " & exc.msg
        typeError(vm, "atob: String contains an invalid character")
        return

      let
        value = vm.RequireObjectCoercible(vm.registers.callArgs[0])
        strVal = vm.ToString(value)

      try:
        vm.registers.retVal = some(str decode(strVal))
      except Base64DecodeError as exc:
        when not defined(baliUseStdBase64): decodeError
      except ValueError as exc:
        when defined(baliUseStdBase64): decodeError
  )
  generator.call("BALI_ATOB")

  # btoa
  # Encode a string into Base64 data
  generator.newModule("btoa")
  vm.registerBuiltin("BALI_BTOA",
    proc(op: Operation) =
      if vm.registers.callArgs.len < 1:
        typeError(vm, "btoa: At least 1 argument required, but only 0 passed")
        return

      let 
        value = vm.RequireObjectCoercible(vm.registers.callArgs[0])
        str = vm.ToString(value)

      vm.registers.retVal = some(str encode(str))
  )
  generator.call("BALI_BTOA")
