## Coercion abstract functions
##
## Copyright (C) 2024 Trayambak Rai
import std/[tables]
import mirage/runtime/prelude
import bali/internal/sugar
import bali/stdlib/errors

proc RequireObjectCoercible*(vm: PulsarInterpreter, value: MAtom): MAtom {.inline.} =
  if value.kind == Null:
    vm.typeError("Object is not coercible: " & value.crush())
    return

  value

proc ToString*(vm: PulsarInterpreter, value: MAtom): string {.inline.} =
  ## 7.1.17 ToString ( argument )
  ## The abstract operation ToString takes argument argument (an ECMAScript language value) and returns either a normal completion containing a String or a throw completion. It converts argument to a value of type String. It performs the following steps when called

  case value.kind
  of String: # 1. If argument is a String, return argument.
    return &value.getStr()
  of Ident:
    vm.typeError("Cannot convert Symbol to String")
    return ""
  of Object:
    if value.objFields.len < 1: # Bali's way of indicating an undefined object
      # 3. If argument is undefined, return "undefined".
      return "undefined"
    else:
      # 9. Assert: argument is an Object.
      return "undefined" # FIXME: not implemented yet!
  of Null:
    return "null" # 4. If argument is null, return "null".
  of Boolean:
    if &value.getBool(): "true" # 5. If argument is true, return "true"
    else: "false" # 6. If argument is false, return "false".
  of Integer:
    return $(&value.getInt()) # 7. If argument is a Number, return Number::toString(argument, 10).
  of Float:
    return $(&value.getFloat()) # 7. If argument is a Number, return Number::toString(argument, 10).
  of UnsignedInt:
    return $(&value.getUint()) # 7. If argument is a Number, return Number::toString(argument, 10).
  of Sequence: return "undefined" # FIXME: not implemented yet!
