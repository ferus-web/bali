## Implementation of the Web Math API
## Copyright (C) 2024 Trayambak Rai and Ferus Authors
import std/[importutils, tables, math, options, logging]
import mirage/ir/generator
import mirage/runtime/prelude
import bali/runtime/[normalize]
import bali/runtime/abstract/[to_number]
import bali/internal/sugar
import pretty, librng, librng/generator

privateAccess(RNG)

const
  rawAlgo {.strdefine: "BaliRNGAlgorithm".} = "xoroshiro128"

let Algorithm = case rawAlgo
  of "xoroshiro128": Xoroshiro128
  of "xoroshiro128pp": Xoroshiro128PlusPlus
  of "xoroshiro128ss": Xoroshiro128StarStar
  of "mersenne_twister": MersenneTwister
  of "marsaglia": Marsaglia69069
  of "pcg": PCG
  of "lehmer": Lehmer64
  of "splitmix": Splitmix64
  else: 
    Xoroshiro128

# Global RNG source
var rng = newRNG(algo = Algorithm)

proc generateStdIr*(vm: PulsarInterpreter, generator: IRGenerator) =
  info "math: generating IR interfaces"
  
  # Math.random
  # WARN: Do not use this for cryptography! This uses one of eight highly predictable pseudo-random
  # number generation algorithms that librng implements!
  generator.newModule(normalizeIRName "Math.random")
  vm.registerBuiltin("BALI_MATHRANDOM",
    proc(op: Operation) =
      let value = float64(rng.generator.next()) / 1.8446744073709552e+19'f64

      vm.registers.retVal = some floating value
  )
  generator.call("BALI_MATHRANDOM")

  # Math.pow
  generator.newModule(normalizeIRName "Math.pow")
  vm.registerBuiltin("BALI_MATHPOW",
    proc(op: Operation) =
      let
        value = vm.ToNumber(vm.registers.callArgs[0])
        exponent = vm.ToNumber(vm.registers.callArgs[1])
      
      vm.registers.retVal = some floating pow(value, exponent)
  )
  generator.call("BALI_MATHPOW")

  # Math.cos
  generator.newModule(normalizeIRName "Math.cos")
  vm.registerBuiltin("BALI_MATHCOS",
    proc(op: Operation) =
      let value = vm.ToNumber(vm.registers.callArgs[0])
      
      vm.registers.retVal = some floating cos(value)
  )
  generator.call("BALI_MATHCOS")

  # Math.sqrt
  generator.newModule(normalizeIRName "Math.sqrt")
  vm.registerBuiltin("BALI_MATHSQRT",
    proc(op: Operation) =
      let value = vm.ToNumber(vm.registers.callArgs[0])

      vm.registers.retVal = some floating sqrt(value)
  )
  generator.call("BALI_MATHSQRT")

  # Math.tanh
  generator.newModule(normalizeIRName "Math.tanh")
  vm.registerBuiltin("BALI_MATHTANH",
    proc(op: Operation) =
      let value = vm.ToNumber(vm.registers.callArgs[0])

      vm.registers.retVal = some floating tanh(value)
  )
  generator.call("BALI_MATHTANH")

  # Math.sin
  generator.newModule(normalizeIRName "Math.sin")
  vm.registerBuiltin("BALI_MATHSIN",
    proc(op: Operation) =
      let value = vm.ToNumber(vm.registers.callArgs[0])

      vm.registers.retVal = some floating sin(value)
  )
  generator.call("BALI_MATHSIN")

  # Math.sinh
  generator.newModule(normalizeIRName "Math.sinh")
  vm.registerBuiltin("BALI_MATHSINH",
    proc(op: Operation) =
      let value = vm.ToNumber(vm.registers.callArgs[0])

      vm.registers.retVal = some floating sinh(value)
  )
  generator.call("BALI_MATHSINH")
  
  # Math.tan
  generator.newModule(normalizeIRName "Math.tan")
  vm.registerBuiltin("BALI_MATHTAN",
    proc(op: Operation) =
      let value = vm.ToNumber(vm.registers.callArgs[0])

      vm.registers.retVal = some floating tan(value)
  )
  generator.call("BALI_MATHTAN")

  # Math.trunc
  generator.newModule(normalizeIRName "Math.trunc")
  vm.registerBuiltin("BALI_MATHTRUNC",
    proc(op: Operation) =
      let value = vm.ToNumber(vm.registers.callArgs[0])

      vm.registers.retVal = some floating trunc(value)
  )
  generator.call("BALI_MATHTRUNC")

  # Math.floor
  generator.newModule(normalizeIRName "Math.floor")
  vm.registerBuiltin("BALI_MATHFLOOR",
    proc(op: Operation) =
      let value = vm.ToNumber(vm.registers.callArgs[0])

      vm.registers.retVal = some floating floor(value)
  )
  generator.call("BALI_MATHFLOOR")

  # Math.ceil
  generator.newModule(normalizeIRName "Math.ceil")
  vm.registerBuiltin("BALI_MATHCEIL",
    proc(op: Operation) =
      let value = vm.ToNumber(vm.registers.callArgs[0])
      vm.registers.retVal = some floating ceil(value)
  )
  generator.call("BALI_MATHCEIL")

  # Math.cbrt
  generator.newModule(normalizeIRName "Math.cbrt")
  vm.registerBuiltin("BALI_MATHCBRT",
    proc(op: Operation) =
      let value = vm.ToNumber(vm.registers.callArgs[0])

      vm.registers.retVal = some floating cbrt(value)
  )
  generator.call("BALI_MATHCBRT")

  # Math.log
  generator.newModule(normalizeIRName "Math.max")
  vm.registerBuiltin("BALI_MATHMAX",
    proc(op: Operation) =
      let 
        a = vm.ToNumber(vm.registers.callArgs[0])
        b = vm.ToNumber(vm.registers.callArgs[1])

      vm.registers.retVal = some floating max(a, b)
  )
  generator.call("BALI_MATHMAX")

  # Math.abs
  generator.newModule(normalizeIRName "Math.abs")
  vm.registerBuiltin("BALI_MATHABS",
    proc(op: Operation) =
      let value = vm.ToNumber(vm.registers.callArgs[0])

      vm.registers.retVal = some floating abs(value)
  )
  generator.call("BALI_MATHABS")
