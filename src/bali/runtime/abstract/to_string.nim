import std/[logging, options]
import bali/runtime/vm/runtime/prelude
import bali/internal/sugar
import bali/runtime/[types]
import bali/runtime/abstract/to_primitive
import pkg/gmp

proc ToString*(runtime: Runtime, value: JSValue): string =
  ## 7.1.17 ToString ( argument )
  ## The abstract operation ToString takes argument argument (an ECMAScript language value) and returns either a normal completion containing a String or a throw completion. It converts argument to a value of type String. It performs the following steps when called
  debug "runtime: toString(): " & value.crush()

  case value.kind
  of String: # 1. If argument is a String, return argument.
    debug "runtime: toString(): atom is a String."
    return &value.getStr()
  of Undefined:
    debug "runtime: toString(): atom is undefined."
    # 3. If argument is undefined, return "undefined".
    return "undefined"
  of Object:
    debug "runtime: toString(): atom is an object."
    # 9. Assert: argument is an Object.
    # 10. Let primValue be ? ToPrimitive(argument, string).
    let primValue = runtime.ToPrimitive(value, some(String))

    # 12. Return ? ToString(primValue).
    return runtime.ToString(primValue)
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
  of BigInteger:
    debug "runtime: toString(): atom is a bigint"
    return $value.bigint
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
    debug "runtime: toString(): atom is an object (sequence)."
    var buffer = "["

    # FIXME: not spec compliant!
    for i, _ in value.sequence:
      buffer &= runtime.ToString(value.sequence[i].addr)
      if i < value.sequence.len - 1:
        buffer &= ", "

    buffer &= ']'

    return buffer
  of NativeCallable:
    # FIXME: not spec compliant!
    return "function () {\n      [native code]\n}"
  of BytecodeCallable:
    # FIXME: not spec compliant!
    return "function " & value.clauseName & "() { }"
