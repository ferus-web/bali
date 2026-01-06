## This file contains some helper functions used by the AMD64 JIT.
## These are often called by JIT'd code segments to "forward" work.
##
## Copyright (C) 2025-2026 Trayambak Rai (xtrayambak@disroot.org)
import pkg/bali/runtime/vm/atom
import pkg/shakar

proc getRawFloat*(atom: JSValue): float64 {.cdecl.} =
  &atom.getNumeric()

proc getRawInt*(atom: JSValue): int {.cdecl.} =
  &atom.getInt()

proc copyRaw*(dest, source: pointer, size: uint) {.cdecl.} =
  copyMem(dest, source, size)
