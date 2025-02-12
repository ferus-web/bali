import std/[logging, math, options]
import bali/runtime/vm/runtime/prelude
import bali/internal/sugar
import bali/runtime/[atom_helpers, types]
import bali/runtime/abstract/to_primitive
import bali/internal/[trim_string, parse_number]

proc StringToNumber*(runtime: Runtime, value: JSValue): float =
  assert value.kind == String, "StringToNumber() was passed a " & $value.kind
  debug "runtime: StringToNumber(" & value.crush() & ')'
  let text = runtime.trimString(value, TrimMode.Both)

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

proc ToNumber*(runtime: Runtime, value: JSValue): float =
  ## 7.1.4 ToNumber ( argument )
  ## The abstract operation ToNumber takes argument argument (an ECMAScript language value) and returns either
  ## a normal completion containing a Number or a throw completion. It converts argument to a value of type Number.
  ## It performs the following steps when called

  case value.kind
  of Integer:
    return float(&value.getInt()) # 1. If argument is a Number, return argument.
  of UnsignedInt:
    return float(&value.getUint())
  of Object:
    if value.isUndefined():
      return NaN # 3. If argument is undefined, return NaN.
    else:
      # 8. Let primValue be ? ToPrimitive(argument, NUMBER).
      let primValue = runtime.ToPrimitive(value, some(Float))
      assert(primValue.kind != Object)

      # 10. Return ? ToNumber(primValue)
      return runtime.ToNumber(primValue)
  of Null:
    return 0f # 4. If argument is either null or false, return +0𝔽.
  of Boolean:
    if not &value.getBool():
      return 0f # 4. If argument is either null or false, return +0𝔽.
    else:
      return 1f # 5. If argument is true, return 1𝔽.
  of String:
    return runtime.StringToNumber(value)
  of Float:
    return &value.getFloat()
  else:
    unreachable

proc ToNumeric*(runtime: Runtime, value: JSValue): JSValue =
  ## 7.1.3 ToNumeric ( value )
  ## This either returns a `BigInteger` atom or a `Floating` atom. Nothing else.

  # 1. Let primValue be ? ToPrimitive(value, NUMBER).
  let primValue = runtime.ToPrimitive(value, some(Integer))

  # 2. If primValue is a BigInt, return primValue.
  if primValue.kind == BigInteger:
    return primValue

  # 3. Return ? ToNumber(primValue)
  floating(runtime.ToNumber(primValue))

proc isFiniteNumber*(runtime: Runtime, number: JSValue): bool {.inline.} =
  if not isNumber(number):
    return false

  let value = runtime.ToNumber(number)

  if value.int32 < int32.high:
    return true

  return value != NaN and value != Inf

proc isIntegralNumber*(runtime: Runtime, number: JSValue): bool {.inline.} =
  if not number.isNumber:
    return false

  let value = runtime.ToNumber(number)

  if value.int32 < int32.high:
    return true

  runtime.isFiniteNumber(number) and value.trunc() == value
