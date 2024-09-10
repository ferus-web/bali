## TrimString( string, where )
## Implemented according to the ECMAScript spec.
## 
## Copyright (C) 2024 Trayambak Rai and Ferus Authors
import std/[strutils]
import mirage/runtime/prelude
import bali/internal/sugar
import bali/runtime/abstract/coercion

type
  TrimMode* {.pure.} = enum
    Left
    Right
    Both

proc internalTrim(str: string, things: set[char], mode: TrimMode): string {.inline.} =
  var 
    substringStart = 0
    substringLength = str.len

  if mode == TrimMode.Left or mode == TrimMode.Both:
    for c in str:
      if substringLength == 0:
        return

      if not things.contains(c):
        break

      substringStart += 1
      substringLength -= 1

  if mode == TrimMode.Right or mode == TrimMode.Both:
    var seenWhitespaceLength = 0

    for c in str:
      if things.contains(c):
        seenWhitespaceLength += 1
      else:
        seenWhitespaceLength = 0

    if seenWhitespaceLength >= substringLength:
      return

    substringLength -= seenWhitespaceLength

  str[substringStart ..< substringLength]

proc trimString*(
  vm: PulsarInterpreter,
  input: MAtom,
  where: TrimMode
): string =
  # 1. Let str be ? RequireObjectCoercible(string).
  let inputString = RequireObjectCoercible(vm, input)

  # 2. Let S be ? ToString(str).
  let str = ToString(vm, input)

  # 3. If where is start, let T be the String value that is a copy of S with leading white space removed.
  # 4. Else if where is end, let T be the String value that is a copy of S with trailing white space removed.
  # 5. Else,
  #   a. Assert: where is start+end
  #   b. Let T be the String value that is a copy of S with both leading and trailing white space removed.
  # 6. Return T.
  let trimmedString = str.internalTrim(strutils.Whitespace, where)

  trimmedString
