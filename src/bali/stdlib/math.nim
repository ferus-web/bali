## Implementation of the Web Math API
## Copyright (C) 2024 Trayambak Rai and Ferus Authors
import std/[importutils, tables, math, options, logging]
import mirage/ir/generator
import mirage/runtime/prelude
import bali/runtime/normalize
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
      let value = float64(rng.generator.next()) / 1.8446744073709552e+19

      vm.registers.retVal = some floating value
  )
  generator.call("BALI_MATHRANDOM")

  # Math.pow
  generator.newModule(normalizeIRName "Math.pow")
  vm.registerBuiltin("BALI_MATHPOW",
    proc(op: Operation) =
      let
        y = vm.registers.callArgs.pop().getFloat()
        x = vm.registers.callArgs.pop().getFloat()
      
      print vm.registers
      debug pow(&x, &y)
      vm.registers.retVal = some floating pow(&x, &y)
  )
  generator.call("BALI_MATHPOW")
