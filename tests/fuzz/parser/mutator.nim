## Mutator routines
## These attempt to generate valid-ish JavaScript code to hit the parser harder.
## 
## Copyright (C) 2025 Trayambak Rai
import std/[strutils, random]
import pkg/bali/internal/sugar

proc genFuncCallArgs(): string =
  case rand(0 .. 2)
  of 0:
    # Integers
    return $rand(int.low .. int.high)
  of 1:
    # Floats
    var nums: seq[int]
    for i in 0 .. rand(1 .. 12):
      nums &= rand(0 .. 9)

    return $rand(int.low .. int.high) & '.' & nums.join()
  of 2:
    # Strings
    var buff = newStringOfCap(64)
    let encloser = if rand(0 .. 1) == 1: '\'' else: '"'

    buff &= encloser
    for i in 0 .. rand(1 .. 16):
      buff &= sample(Letters + Digits + Whitespace - Newlines)
    buff &= encloser

    return ensureMove(buff)
  of 3:
    discard "TODO: Arrays"
  else:
    unreachable

proc genFuncCall(buff: var string) =
  let call = sample(["console.log", "console.error", "console.warn"])

  buff &= call
  buff &= '('
  buff &= genFuncCallArgs()
  buff &= ')'

  if rand(0 .. 1) == 0:
    buff &= ';'

proc genCode*(): string =
  var buffer = newStringOfCap(2048)

  case rand(0 .. 2)
  of 0:
    # Generate random function call
    genFuncCall(buffer)
  else:
    discard "TODO"

  ensureMove(buffer)
