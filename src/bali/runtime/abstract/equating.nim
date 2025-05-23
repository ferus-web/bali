## Equation functions
## Loose (==) and Strict (===)
## Author: Trayambak Rai (xtrayambak at disroot dot org)
import pkg/[bali/runtime/vm/atom, gmp/gmp]
import pkg/ferrite/utf16view
import bali/runtime/[atom_helpers, types, bridge]
import bali/runtime/abstract/[coercion]
import bali/internal/sugar
import bali/stdlib/types/[std_bigint, std_string_type]

proc equateNumbers*(runtime: Runtime, x, y: JSValue): bool =
  runtime.ToNumber(x) == runtime.ToNumber(y)

proc equateSameValueNonNumber*(runtime: Runtime, x, y: JSValue): bool =
  ## 7.2.12 SameValueNonNumber ( x, y )

  # 1. Assert: Type(x) is Type(y).
  assert(x.kind == y.kind)

  # 2. If x is either null or undefined, return true
  if x.kind == Null or x.isUndefined:
    return true

  # 3. If x is a BigInt, then
  if x.isBigInt:
    return (&x.tagged("value")).bigint.bg == (&y.tagged("value")).bigint.bg

  # 4. If x is a String, then
  if runtime.isA(x, JSString):
    # a. If x and y have the same length and the same code units in the same positions, return true; otherwise, return false.
    let
      xVal = newUtf16View(runtime.ToString(x))
      yVal = newUtf16View(runtime.ToString(y))

    if xVal.codePointLen != yVal.codePointLen:
      return false

    let
      xData = xVal.data()
      yData = yVal.data()

    for i in 0 ..< xData.len:
      if xData[i] != yData[i]:
        return false

    return true

  # 5. If x is a Boolean, then
  if x.kind == Boolean:
    # a. If x and y are both true or both false, return true; otherwise, return false.
    return &x.getBool() == &y.getBool()

proc isStrictlyEqual*(runtime: Runtime, x, y: JSValue): bool =
  ## 7.2.15 IsStrictlyEqual ( x, y )

  # 1. If Type(x) is not Type(y), return false.
  if (x.kind != y.kind):
    if not (x.isNumber and y.isNumber):
      return false

  # 2. If x is a Number, then
  if x.isNumber:
    return runtime.equateNumbers(x, y)

  # 3. Return SameValueNonNumber(x, y).
  return runtime.equateSameValueNonNumber(x, y)

proc isLooselyEqual*(runtime: Runtime, x, y: JSValue): bool =
  ## 7.2.14 IsLooselyEqual ( x, y )

  # 1. If Type(x) is Type(y), then
  if (x.isNumber and y.isNumber) or (x.kind == y.kind):
    # a. Return IsStrictlyEqual(x, y)
    return runtime.isStrictlyEqual(x, y)

  # 2. If x is null and y is undefined, return true.
  if x.isNull and y.isUndefined:
    return true

  # FIXME: NON-COMPLIANT: BALI-SPECIFIC HACK TO GET AROUND JSSTRING BOXING!
  if runtime.isA(x, JSString) and runtime.isA(y, JSString):
    # a. If x and y have the same length and the same code units in the same positions, return true; otherwise, return false.
    let
      xVal = newUtf16View(runtime.ToString(x))
      yVal = newUtf16View(runtime.ToString(y))

    if xVal.codePointLen != yVal.codePointLen:
      return false

    let
      xData = xVal.data()
      yData = yVal.data()

    for i in 0 ..< xData.len:
      if xData[i] != yData[i]:
        return false

    return true

  # If x is undefined and y is null, return true.
  if x.isUndefined and y.isNull:
    return true

  # 4. NOTE: This step is replaced in section B.3.6.2.
  # FIXME: Step 4: Not implemented properly

  # 5. If x is a Number and y is a String, return ! IsLooselyEqual(x, ! ToNumber(y))
  if x.isNumber and runtime.isA(y, JSString):
    return runtime.isLooselyEqual(x, floating(runtime.ToNumber(y)))

  # 6. If x is a String and y is a Number, return ! IsLooselyEqual(! ToNumber(x), y).
  if runtime.isA(x, JSString) and y.isNumber:
    return runtime.isLooselyEqual(floating(runtime.ToNumber(x)), y)

  # 7. If x is a BigInt and y is a String, then
  if x.isBigInt and runtime.isA(y, JSString):
    # a. Let n be StringToBigInt(y).
    let n = runtime.stringToBigInt(y)

    # b. If n is undefined, return false.
    if n.isUndefined:
      return false

    # c. Return ! IsLooselyEqual(x, n).
    return runtime.isLooselyEqual(x, n)

  # 8. If x is a String and y is a BigInt, return ! IsLooselyEqual(y, x).
  if runtime.isA(x, JSString) and y.isBigInt:
    # OPTIMIZATION: We can avoid an extra recursion by just writing a bit more code.
    # This follows the same steps as above, except x and y are swapped, so it's still compliant.

    # a. Let n be StringToBigInt(x).
    let n = runtime.stringToBigInt(x)

    # b. If n is undefined, return false.
    if n.isUndefined:
      return false

    # c. Return ! IsLooselyEqual(y, n)
    return runtime.isLooselyEqual(y, n)

  # 9. If x is a Boolean, return ! IsLooselyEqual(! ToNumber(x), y).
  if x.kind == Boolean:
    return runtime.isLooselyEqual(floating(runtime.ToNumber(x)), y)

  # 10. If y is a Boolean, return ! IsLooselyEqual(x, ! ToNumber(y)).
  if y.kind == Boolean:
    return runtime.isLooselyEqual(x, floating(runtime.ToNumber(y)))

  # 11. If x is either a String, a Number, a BigInt, or a Symbol and y is an Object, return ! IsLooselyEqual(x, ? ToPrimitive(y)).
  if (runtime.isA(x, JSString) or x.isBigInt or x.isNumber) and y.isObject:
    # FIXME: does not account for symbols yet, as they aren't a type.
    return runtime.isLooselyEqual(x, runtime.ToPrimitive(y))

  # 12. If x is an Object and y is either a String, a Number, a BigInt or a Symbol, return ! IsLooselyEqual(? ToPrimitive(x), y).
  if (runtime.isA(y, JSString) or y.isBigInt or y.isNumber) and x.isObject:
    # FIXME: does not account for symbols yet
    return runtime.isLooselyEqual(runtime.ToPrimitive(x), y)

  # 13. If x is a BigInt and y is a Number, or if x is a Number and y is a BigInt, then
  if (x.isBigInt and y.isNumber) or (x.isNumber and y.isBigInt):
    # a. If x is not finite or y is not finite, return false.
    if not runtime.isFiniteNumber(x) or not runtime.isFiniteNumber(y):
      return false

    # b. If ℝ(x) = ℝ(y), return true; otherwise return false.
    if runtime.ToNumber(x) == runtime.ToNumber(y):
      return true

  # 14. Return false.
  return false
