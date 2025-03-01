## Arbitrary-precision integers
## Author: Trayambak Rai (xtrayambak at disroot dot org)
import std/[options]
import bali/runtime/[arguments, atom_helpers, types, wrapping, bridge]
import bali/runtime/abstract/coercion
import bali/stdlib/errors
import bali/internal/[sugar, trim_string]
import bali/runtime/vm/atom
import pkg/gmp

type JSBigInt* = object
  `@ value`*: JSValue

proc stringToBigInt*(runtime: Runtime, str: JSValue): JSValue =
  # 7.1.14 StringToBigInt ( str )

  # 1. Let text be StringToCodePoints(str).
  let text = runtime.trimString(str, TrimMode.Both)

  var bigint =
    try:
      # 2. Let literal be ParseText(text, StringIntegerLiteral).
      bigint(text)
    except ValueError:
      # 3. If literal is a List of errors, return undefined.
      undefined()

  # 6. Return ℤ(mv).
  var bigintAtom = runtime.createObjFromType(JSBigInt)
  bigintAtom.tag("value", ensureMove(bigint))

  ensureMove(bigintAtom)

proc toBigInt*(runtime: Runtime, atom: JSValue): JSValue =
  ## 7.1.13 ToBigInt ( argument ), https://tc39.es/ecma262/#sec-tobigint

  # 1. Let prim be ? ToPrimitive(argument, number).
  let prim = runtime.ToPrimitive(atom, some(Integer))

  # 2. Return the value that prim corresponds to in Table 12.

  # Number
  if prim.isNumber():
    # Throw a TypeError exception.
    runtime.typeError("Cannot convert number into BigInt")

  # BigInt
  if prim.kind == BigInteger:
    # Return prim.
    var bigint = runtime.createObjFromType(JSBigInt)
    bigint.tag("value", prim)
    return bigint

  # String
  if prim.kind == String:
    # 1. Let n be StringToBigInt(prim).
    let n = runtime.stringToBigInt(prim)

    if n.isUndefined():
      # 2. If n is undefined, throw a SyntaxError exception.
      runtime.syntaxError("invalid BigInt syntax")

    # 3. Return n
    return n

  # Null
  if prim.isNull():
    # Throw a TypeError exception.
    runtime.typeError("can't convert null to BigInt")

  # Undefined
  if prim.isUndefined():
    # Throw a TypeError exception.
    runtime.typeError("can't convert undefined to BigInt")

  # Boolean
  if prim.kind == Boolean:
    # Return 1n if prim is true and 0n if prim is false.

    var bigint = runtime.createObjFromType(JSBigInt)
    bigint.tag("value", bigint(int(&prim.getBool())))
    return bigint

proc numberToBigInt*(runtime: Runtime, primitive: JSValue): JSValue {.inline.} =
  ## 21.2.1.1.1 NumberToBigInt ( number )

  # 1. If IsIntegralNumber(number) is false, throw a RangeError exception.
  if not runtime.isIntegralNumber(primitive):
    runtime.rangeError("Value is out of the valid range")

  # 2. Return ℤ(ℝ(number)).

  var bigint = runtime.createObjFromType(JSBigInt)

  bigint.tag("value", bigint(runtime.ToNumber(primitive).int()))

  bigint

proc generateStdIR*(runtime: Runtime) =
  runtime.registerType(prototype = JSBigInt, name = "BigInt")
  runtime.defineFn(
    "BigInt",
    proc() =
      ## 21.2.1.1 BigInt ( value )

      # 1. If NewTarget is not undefined, throw a TypeError exception.
      # TODO: I have no clue what NewTarget is.

      let value = &runtime.argument(1)

      # 2. Let prim be ? ToPrimitive(value, NUMBER).
      let primitive = runtime.ToPrimitive(value, some(Integer))

      # 3. If Type(prim) is Number, return ? NumberToBigInt(prim).
      if primitive.isNumber():
        ret runtime.numberToBigInt(primitive)

      # 4. Otherwise, return ? ToBigInt(prim).
      ret runtime.toBigInt(primitive)
    ,
  )

  runtime.definePrototypeFn(
    JSBigInt,
    "toString",
    proc(value: JSValue) =
      let bigint = &value.tagged("value")
      ret $bigint.bigint
    ,
  )
