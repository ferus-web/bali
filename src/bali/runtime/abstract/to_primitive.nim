import std/[options, tables]
import bali/runtime/[types, atom_helpers, bridge]
import bali/internal/sugar
import bali/stdlib/errors
import bali/runtime/vm/runtime/prelude

type PrimitiveHint* {.pure.} = enum
  Default
  String
  Number

proc OrdinaryToPrimitive*(
    runtime: Runtime, input: JSValue, hint: PrimitiveHint
): JSValue =
  # 1. If hint is string, then
  let methodNames =
    if hint == PrimitiveHint.String:
      # a. Let methodNames be « "toString", "valueOf" ».
      @["toString", "valueOf"]
    else:
      # 2. Else,
      # a. Let methodNames be « "valueOf", "toString" ».
      @["valueOf", "toString"]

  # 3. For each element name of methodNames, do
  for name in methodNames:
    # a. Let method be ? Get(O, name).
    let meth = runtime.getMethod(input, name)

    if !meth:
      continue

    # b. If IsCallable(method) is true, then
    (&meth)(input)
    # i. Let result be ? Call(method, O).
    let res = runtime.getReturnValue()

    # ii. If result is not an Object, return result.
    if (&res).kind != Object:
      return &res

  # 4. Throw a TypeError exception.
  # Yes Rico, kaboom.
  runtime.typeError("Cannot convert object into primitive")

proc ToPrimitive*(
    runtime: Runtime, input: JSValue, preferredType: Option[MAtomKind] = none(MAtomKind)
): JSValue =
  # 1. If input is an Object, then
  if input.kind == Object:
    # a. Let exoticToPrim be ? GetMethod(input, @@toPrimitive).
    let exoticToPrim = runtime.getMethod(input, "toPrimitive")

    if *exoticToPrim:
      # b. If exoticToPrim is not undefined, then

      let hint =
        if !preferredType:
          # i. If preferredType is not present, then
          # 1. Let hint be "default".
          PrimitiveHint.Default
        elif &preferredType == String:
          # ii. Else if preferredType is string, then
          # 1. Let hint be "string".
          PrimitiveHint.String
        else:
          # iii. Else,
          # 1. Assert: preferredType is number.
          if &preferredType in [Integer, UnsignedInt, Float]:
            # 2. Let hint be "number".
            PrimitiveHint.Number
          else:
            unreachable
            default PrimitiveHint

      # iv. Let result be ? Call(exoticToPrim, input, « hint »).
      (&exoticToPrim)(wrap(toTable {"hint": hint.int.integer(), "input": input}))
      let res = runtime.getReturnValue()
      assert(*res, "BUG: Expected toPrimitive() to return value, got nothing.")

      if (&res).kind != Object:
        # v. If result is not an Object, return result.
        return &res
      else:
        # vi. Throw a TypeError exception.
        runtime.typeError("Cannot convert object into primitive")
    else:
      # c. If preferredType is not present, let preferredType be number.
      return runtime.OrdinaryToPrimitive(input, PrimitiveHint.Number)

  # 2. Return input.
  return input
