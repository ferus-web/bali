## TrimString( string, where )
## Implemented according to the ECMAScript spec.
## 

import std/[strutils, logging]
import mirage/runtime/prelude
import bali/internal/sugar
import bali/runtime/types
import bali/runtime/abstract/[coercible, to_string]

import pretty

type TrimMode* {.pure.} = enum
  Left
  Right
  Both

proc internalTrim*(str: string, things: set[char], mode: TrimMode): string {.inline.} =
  var
    substringStart = 0
    substringLength = str.len

  if mode == TrimMode.Left or mode == TrimMode.Both:
    for c in str:
      if substringLength < 1:
        return

      if not things.contains(c):
        break

      inc substringStart
      dec substringLength
  
  if mode == TrimMode.Right or mode == TrimMode.Both:
    var seenWhitespaceLength = 0

    for c in str:
      if things.contains(c):
        seenWhitespaceLength += 1
      else:
        seenWhitespaceLength = 0

    if seenWhitespaceLength >= substringLength:
      return
    
    echo "wslen: " & $seenWhitespaceLength
    substringLength -= seenWhitespaceLength
  
  echo "start: " & $substringStart
  echo "end: " & $substringLength
  str[substringStart .. substringLength]

proc trimString*(runtime: Runtime, input: MAtom, where: TrimMode): string =
  # 1. Let str be ? RequireObjectCoercible(string).
  let inputString = RequireObjectCoercible(runtime, input)

  # 2. Let S be ? ToString(str).
  let str = ToString(runtime, input)

  # 3. If where is start, let T be the String value that is a copy of S with leading white space removed.
  # 4. Else if where is end, let T be the String value that is a copy of S with trailing white space removed.
  # 5. Else,
  #   a. Assert: where is start+end
  #   b. Let T be the String value that is a copy of S with both leading and trailing white space removed.
  # 6. Return T.
  let trimmedString = str.internalTrim(strutils.Whitespace, where)

  trimmedString
