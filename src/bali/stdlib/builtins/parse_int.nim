## `parseInt` builtin.
##
## Copyright (C) 2024 Trayambak Rai

import std/[strutils, math, options, logging]
import mirage/ir/generator
import mirage/runtime/prelude
import bali/runtime/normalize
import bali/internal/sugar
import pretty

proc parseIntGenerateStdIr*(vm: PulsarInterpreter, generator: IRGenerator) =
  info "builtins.parse_int: generating IR interfaces"

  # parseInt
  # The parseInt() function parses a string argument and returns an integer of the specified radix (the base in mathematical numeral systems).
  generator.newModule("parseInt")
  vm.registerBuiltin("BALI_PARSEINT",
    proc(op: Operation) =
      if vm.registers.callArgs.len < 1 or vm.registers.callArgs[0].kind != String:
        vm.registers.retVal = some floating NaN
        return

      let 
        value = &vm.registers.callArgs[0].getStr()
        radix = if vm.registers.callArgs.len > 1:
          vm.registers.callArgs[1].getInt()
        else:
          if value.startsWith("0x"):
            some(16)
          else:
            some(10)
      
      try:
        vm.registers.retVal = some(
          if radix == some(2):
            integer parseBinInt(value)
          elif radix == some(8):
            integer parseOctInt(value)
          elif radix == some(10):
            integer parseInt(value)
          elif radix == some(16):
            integer parseHexInt(value)
          else:
            floating NaN
        )
      except ValueError as exc:
        warn "builtins.parse_int(" & $value & "): " & exc.msg & " (radix " & $radix & ')'
        vm.registers.retVal = some floating NaN
  )
  generator.call("BALI_PARSEINT")
