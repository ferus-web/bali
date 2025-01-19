## `parseInt` builtin.
##

import std/[strutils, math, options, logging]
import mirage/runtime/prelude
import bali/runtime/[arguments, types, bridge]
import bali/internal/[sugar, trim_string]

proc parseIntGenerateStdIr*(runtime: Runtime) =
  info "builtins.parse_int: generating IR interfaces"

  # parseInt
  # The parseInt() function parses a string argument and returns an integer of the specified radix (the base in mathematical numeral systems).
  runtime.defineFn(
    "parseInt",
    proc() =
      if runtime.vm.registers.callArgs.len < 1:
        runtime.vm.registers.retVal = some floating NaN
        return

      let
        inputString = &runtime.argument(1) # 1. Let inputString be ? ToString(string).
        value = runtime.trimString(inputString, TrimMode.Left)
          # 2. Let S be ! TrimString(inputString, start).

        # FIXME: should we interpret the rest as according to the spec or should we leave it to the Nim standard library? It seems to work as intended...
        radix =
          if runtime.vm.registers.callArgs.len > 1: # 8. If R ≠ 0, then
            runtime.vm.registers.callArgs[1].getInt()
          else:
            # We don't remove the first two chars from the beginning of the string as `parseInt` in std/strutils does it itself when the radix is set to 16.
            if value.startsWith("0x"):
              # 10. a. If the length of S is at least 2 and the first two code units of S are either "0x" or "0X", then 
              some(16) # ii. Set R to 16.
            else: # 9. Else,
              some(10) # a. Set R to 10.

      try:
        runtime.vm.registers.retVal = some(
          case &radix
          of 2:
            integer parseBinInt(value)
          of 8:
            integer parseOctInt(value)
          of 10:
            integer parseInt(value)
          of 16:
            integer parseHexInt(value)
          else:
            if unlikely(&radix < 2 or &radix > 36):
              floating NaN
            else:
              floating NaN
        )
      except ValueError as exc:
        warn "builtins.parse_int(" & $value & "): " & exc.msg & " (radix=" & $radix & ')'
        runtime.vm.registers.retVal = some floating NaN,
  )
