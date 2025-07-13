## Number type
## Author: Trayambak Rai (xtrayambak at disroot dot org)
import std/[math, fenv, logging]
import bali/runtime/[arguments, bridge, atom_helpers, wrapping, types]
import bali/runtime/abstract/[to_number, to_string]
import bali/stdlib/builtins/parse_int
import bali/stdlib/errors
import bali/internal/[sugar]
import pkg/gmp
import bali/runtime/vm/atom

type JSNumber* = object
  `@ value`*: JSValue

proc thisNumberValue*(runtime: Runtime, value: JSValue): JSValue =
  ## 21.1.3.7.1 ThisNumberValue ( value )

  if value.isNumber:
    debug "runtime: ThisNumberValue(): value is a number, returning itself."
    # 1. If value is a Number, return value.
    return value

  if value.isObject and value.contains("@value"):
    debug "runtime: ThisNumberValue(): value is an object and contains a [[NumberData]] slot, this is a boxed Number."
    # 2. If value is an Object and value has a [[NumberData]] internal slot, then

    # a. Let n be value.[[NumberData]].
    let n = &value.tagged("value")

    # b. Assert: n is a Number.
    assert(n.isNumber)

    # c. Return n.
    return n

  debug "runtime: ThisNumberValue(): value is neither a boxed Number (or its [[NumberData]] slot was overwritten) and nor is it a regular primitive integral type."
  # 3. Throw a TypeError exception
  runtime.typeError("Cannot obtain number value of object")

proc generateStdIR*(runtime: Runtime) =
  runtime.registerType("Number", JSNumber)
  runtime.defineConstructor(
    "Number",
    proc() =
      ## 21.1.1.1 Number ( value )
      let value = &runtime.argument(1)

      var number: float

      # 1. If value is present, then
      if not value.isUndefined:
        # a. Let prim be ? ToNumeric(value).
        let prim = runtime.ToNumeric(value)

        number =
          if prim.kind == BigInteger:
            # b. If prim is a BigInt, let n be 𝔽(ℝ(prim))
            prim.bigint.getFloat()
          else:
            # c. Otherwise, let n be prim.
            &getFloat(prim)
      else:
        # 2. Else,
        # a. Let n be +0𝔽.
        number = 0f

      # 4. Let O be ? OrdinaryCreateFromConstructor(NewTarget, "%Number.prototype%", « [[NumberData]] »).
      var obj = runtime.createObjFromType(JSNumber)

      # 5. Set O.[[NumberData]] to n.
      obj.tag("value", runtime.wrap(number))

      # 6. Return 0.
      ret ensureMove(obj)
    ,
  )

  runtime.defineFn(
    JSNumber,
    "isFinite",
    proc() =
      ## 21.1.2.2 Number.isFinite ( number )

      let number = &runtime.argument(1)

      if not number.isNumber:
        # 1. If number is not a Number, return false.
        ret false

      if not runtime.isFiniteNumber(number):
        # 2. If number is not finite, return false.
        ret false

      # 3. Otherwise, return true.
      ret true
    ,
  )

  runtime.defineFn(
    JSNumber,
    "isNaN",
    proc() =
      # 21.1.2.4 Number.isNaN ( number )

      let number = &runtime.argument(1)

      if not number.isNumber:
        # 1. If number is not a Number, return false.
        ret false

      if runtime.ToNumber(number).isNaN:
        # 2. If number is NaN, return true.
        ret true

      # 3. Otherwise, return false.
      ret false
    ,
  )

  runtime.defineFn(
    JSNumber,
    "parseInt",
    proc() =
      # 21.1.2.13 Number.parseInt ( string, radix )
      parseIntFunctionSubstitution,
  )

  # 21.1.2.10 Number.NaN
  # The value of Number.NaN is NaN.
  runtime.setProperty(JSNumber, "NaN", floating(NaN))
  
  # 21.1.2.6 Number.MAX_SAFE_INTEGER
  # The value of Number.MAX_SAFE_INTEGER is 9007199254740991𝔽 (𝔽(253 - 1)).
  runtime.setProperty(JSNumber, "MAX_SAFE_INTEGER", floating(9007199254740991'f64))

  # 21.1.2.14 Number.POSITIVE_INFINITY
  # The value of Number.POSITIVE_INFINITY is +∞𝔽.
  runtime.setProperty(JSNumber, "POSITIVE_INFINITY", floating(Inf))

  # 21.1.2.11 Number.NEGATIVE_INFINITY
  # The value of Number.NEGATIVE_INFINITY is -∞∞𝔽.
  runtime.setProperty(JSNumber, "NEGATIVE_INFINITY", floating(-Inf))

  # 21.1.2.1 Number.EPSILON
  # The value of Number.EPSILON is the Number value for the magnitude of the difference between 1
  # and the smallest value greater than 1 that is representable as a Number value, which is approximately
  # 2.2204460492503130808472633361816 × 10-16.
  runtime.setProperty(JSNumber, "EPSILON", floating(epsilon(float)))

  runtime.definePrototypeFn(
    JSNumber,
    "toString",
    proc(value: JSValue) =
      ## 21.1.3.6 Number.prototype.toString ( [ radix ] )
      # FIXME: Not compliant.

      let number = &value.tagged("value")
      ret runtime.ToString(number)
    ,
  )

  runtime.definePrototypeFn(
    JSNumber,
    "valueOf",
    proc(value: JSValue) =
      ## 21.1.3.7 Number.prototype.valueOf ( )

      # 1. Return ? ThisNumberValue(this value).
      ret runtime.thisNumberValue(value)
    ,
  )
