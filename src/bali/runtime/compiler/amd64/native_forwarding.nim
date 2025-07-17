## This file contains some helper functions used by the AMD64 JIT.
## These are often called by JIT'd code segments to "forward" work.
import
  pkg/bali/runtime/vm/atom,
  pkg/bali/runtime/atom_helpers,
  pkg/bali/runtime/vm/heap/boehm
import pkg/shakar

proc createFieldRaw*(atom: JSValue, field: cstring) {.cdecl.} =
  atom[$field] = undefined()

proc getRawFloat*(atom: JSValue): float64 {.cdecl.} =
  &atom.getNumeric()

proc allocFloat*(v: float64): JSValue {.cdecl.} =
  floating v

proc allocFloatEncoded*(v: int64): JSValue {.cdecl.} =
  allocFloat(cast[float64](v))

proc allocRaw*(size: int64): pointer {.cdecl.} =
  baliAlloc(size)

proc copyRaw*(dest, source: pointer, size: uint) {.cdecl.} =
  copyMem(dest, source, size)

proc allocBytecodeCallable*(str: cstring): JSValue {.cdecl.} =
  bytecodeCallable($str)

proc strRaw*(value: cstring): JSValue {.cdecl.} =
  str($value)

proc allocInt*(i: int): JSValue {.cdecl.} =
  integer(i)

proc allocUint*(i: uint): JSValue {.cdecl.} =
  integer(i)
