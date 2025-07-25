## Implementation of the Web Math API

import std/[importutils, tables, math, options, logging]
import bali/runtime/vm/prelude
import bali/runtime/[arguments, types, bridge]
import bali/runtime/abstract/[to_number]
import bali/stdlib/errors
import bali/internal/sugar
import pkg/[librng, librng/generator]

privateAccess(RNG)

const rawAlgo {.strdefine: "BaliRNGAlgorithm".} = "xoroshiro128"

let Algorithm =
  case rawAlgo
  of "xoroshiro128":
    Xoroshiro128
  of "xoroshiro128pp":
    Xoroshiro128PlusPlus
  of "xoroshiro128ss":
    Xoroshiro128StarStar
  of "mersenne_twister":
    MersenneTwister
  of "marsaglia":
    Marsaglia69069
  of "pcg":
    PCG
  of "lehmer":
    Lehmer64
  of "splitmix":
    Splitmix64
  else:
    assert(off, "Invalid RNG algorithm: " & rawAlgo)
    Xoroshiro128

type JSMath = object
  E*: float = math.E
  PI*: float = math.PI

# Global RNG source
var rng = newRNG(algo = Algorithm)

proc generateStdIr*(runtime: Runtime) =
  info "math: generating IR interfaces"

  runtime.registerType("Math", JSMath)
  runtime.setProperty(JSMath, "LN10", floating(math.ln(10'f64)))
  runtime.setProperty(JSMath, "LN2", floating(math.ln(2'f64)))
  runtime.setProperty(JSMath, "LOG10E", floating(math.log10(math.E)))
  runtime.setProperty(JSMath, "LOG2E", floating(math.log2(math.E)))
  runtime.setProperty(JSMath, "SQRT1_2", floating(math.sqrt(1 / 2)))
  runtime.setProperty(JSMath, "SQRT2", floating(math.sqrt(2'f64)))

  # Math.random
  # WARN: Do not use this for cryptography! This uses one of eight highly predictable pseudo-random
  # number generation algorithms that librng implements!
  runtime.defineFn(
    JSMath,
    "random",
    proc() =
      let value = float64(rng.generator.next()) / 1.8446744073709552e+19'f64
      ret floating(value)
    ,
  )

  # Math.pow
  runtime.defineFn(
    JSMath,
    "pow",
    proc() =
      let
        value = runtime.ToNumber(&runtime.argument(1))
        exponent = runtime.ToNumber(&runtime.argument(2))

      ret floating pow(value, exponent)
    ,
  )

  # Math.cos
  runtime.defineFn(
    JSMath,
    "cos",
    proc() =
      let value = runtime.ToNumber(&runtime.argument(1))
      ret floating cos(value)
    ,
  )

  # Math.sqrt
  runtime.defineFn(
    JSMath,
    "sqrt",
    proc() =
      let value = runtime.ToNumber(&runtime.argument(1))
      ret floating sqrt(value)
    ,
  )

  # Math.tanh
  runtime.defineFn(
    JSMath,
    "tanh",
    proc() =
      let value = runtime.ToNumber(&runtime.argument(1))

      ret floating tanh(value)
    ,
  )

  # Math.sin
  runtime.defineFn(
    JSMath,
    "sin",
    proc() =
      let value = runtime.ToNumber(&runtime.argument(1))

      ret floating sin(value)
    ,
  )

  # Math.sinh
  runtime.defineFn(
    JSMath,
    "sinh",
    proc() =
      let value = runtime.ToNumber(&runtime.argument(1))

      ret floating sinh(value)
    ,
  )

  # Math.tan
  runtime.defineFn(
    JSMath,
    "tan",
    proc() =
      let value = runtime.ToNumber(&runtime.argument(1))

      ret floating tan(value)
    ,
  )

  # Math.trunc
  runtime.defineFn(
    JSMath,
    "trunc",
    proc() =
      let value = runtime.ToNumber(&runtime.argument(1))

      ret floating trunc(value)
    ,
  )

  # Math.floor
  runtime.defineFn(
    JSMath,
    "floor",
    proc() =
      let value = runtime.ToNumber(&runtime.argument(1))

      ret floating floor(value)
    ,
  )

  # Math.ceil
  runtime.defineFn(
    JSMath,
    "ceil",
    proc() =
      let value = runtime.ToNumber(&runtime.argument(1))

      ret floating ceil(value)
    ,
  )

  # Math.cbrt
  runtime.defineFn(
    JSMath,
    "cbrt",
    proc() =
      let value = runtime.ToNumber(&runtime.argument(1))

      ret floating cbrt(value)
    ,
  )

  # Math.log
  runtime.defineFn(
    JSMath,
    "log",
    proc() =
      let value = runtime.ToNumber(&runtime.argument(1))

      ret floating ln(value)
    ,
  )

  # Math.abs
  runtime.defineFn(
    JSMath,
    "abs",
    proc() =
      let value = runtime.ToNumber(&runtime.argument(1))

      ret floating abs(value)
    ,
  )

  # Math.max
  runtime.defineFn(
    JSMath,
    "max",
    proc() =
      let
        a = runtime.ToNumber(&runtime.argument(1))
        b = runtime.ToNumber(&runtime.argument(2))

      ret floating max(a, b)
    ,
  )

  # Math.min
  runtime.defineFn(
    JSMath,
    "min",
    proc() =
      let
        a = runtime.ToNumber(&runtime.argument(1))
        b = runtime.ToNumber(&runtime.argument(2))

      ret floating min(a, b)
    ,
  )
