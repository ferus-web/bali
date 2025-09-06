## This file contains some helper functions used by the AMD64 JIT.
## These are often called by JIT'd code segments to "forward" work.
import pkg/bali/runtime/vm/atom
import pkg/shakar

proc getRawFloat*(atom: JSValue): float64 {.cdecl.} =
  &atom.getNumeric()

proc copyRaw*(dest, source: pointer, size: uint) {.cdecl.} =
  copyMem(dest, source, size)
