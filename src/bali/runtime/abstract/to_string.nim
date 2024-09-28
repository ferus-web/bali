import std/[logging]
import mirage/runtime/prelude
import bali/internal/sugar
import bali/runtime/atom_helpers
import bali/stdlib/errors

proc ToString*(vm: PulsarInterpreter, value: MAtom): string {.inline.} =
  ## 7.1.17 ToString ( argument )
  ## The abstract operation ToString takes argument argument (an ECMAScript language value) and returns either a normal completion containing a String or a throw completion. It converts argument to a value of type String. It performs the following steps when called
  debug "runtime: toString(): " & value.crush()

  case value.kind
  of String: # 1. If argument is a String, return argument.
    debug "runtime: toString(): atom is a String."
    return &value.getStr()
  of Object:
    debug "runtime: toString(): atom is an object."
    if value.isUndefined(): # Bali's way of indicating an undefined object
      # 3. If argument is undefined, return "undefined".
      return "undefined"
    else:
      # 9. Assert: argument is an Object.
      return "undefined" # FIXME: not implemented yet!
  of Null, Ident:
    debug "runtime: toString(): atom is null."
    return "null" # 4. If argument is null, return "null".
  of Boolean:
    debug "runtime: toString(): atom is a boolean."
    return
      $(&value.getBool())
        # 5. If argument is true, return "true"
        # 6. If argument is false, return "false".
  of Integer:
    debug "runtime: toString(): atom is a number (int)."
    return
      $(&value.getInt())
        # 7. If argument is a Number, return Number::toString(argument, 10).
  of Float:
    debug "runtime: toString(): atom is a number (float)."
    return
      $(&value.getFloat())
        # 7. If argument is a Number, return Number::toString(argument, 10).
  of UnsignedInt:
    debug "runtime: toString(): atom is a number (uint)."
    return
      $(&value.getUint())
        # 7. If argument is a Number, return Number::toString(argument, 10).
  of Sequence:
    return "undefined" # FIXME: not implemented yet!
