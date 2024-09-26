import std/[logging, strutils]
import mirage/runtime/prelude
import bali/internal/sugar
import bali/runtime/atom_helpers
import bali/stdlib/errors
import bali/internal/[trim_string, parse_number]

proc StringToNumber*(vm: PulsarInterpreter, value: MAtom): float =
  assert value.kind == String, "StringToNumber() was passed a " & $value.kind
  let text = vm.trimString(value, TrimMode.Both)

  if text.len < 1:
    return 0f

  if text == "Infinity" or text == "+Infinity":
    return Inf

  if text == "-Infinity":
    return -Inf

  let parsed = parseNumberText(text)
  if !parsed:
    return NaN
  
  return &parsed

proc ToNumber*(vm: PulsarInterpreter, value: MAtom): float =
  ## 7.1.4 ToNumber ( argument )
  ## The abstract operation ToNumber takes argument argument (an ECMAScript language value) and returns either
  ## a normal completion containing a Number or a throw completion. It converts argument to a value of type Number.
  ## It performs the following steps when called
  
  case value.kind
  of Integer: return float(&value.getInt())   # 1. If argument is a Number, return argument.
  of UnsignedInt: return float(&value.getUint())
  of Object:
    if value.isUndefined(): return NaN # 3. If argument is undefined, return NaN.
    else:
      vm.typeError("ToPrimitive() is not implemented yet!")
  of Null: return 0f # 4. If argument is either null or false, return +0𝔽.
  of Bool:
    if not &value.getBool(): return 0f # 4. If argument is either null or false, return +0𝔽.
    else: return 1f # 5. If argument is true, return 1𝔽.
  of String:
    return vm.StringToNumber(value)
  else: unreachable
